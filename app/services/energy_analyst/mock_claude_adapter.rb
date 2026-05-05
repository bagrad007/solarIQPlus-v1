# frozen_string_literal: true

module EnergyAnalyst
  # Rule-based stand-in for a real Claude call. The intent of this class is
  # narrow: route the user's message to one of `TelemetryInsights`'s
  # query methods and turn the resulting Hash into a short analyst-tone
  # paragraph plus zero or more chart specs.
  #
  # Visualization (`ChartSpec`) shape used everywhere in this module:
  #
  #   { kind: "line",  title: String, points: [{x, y}], markers?: [...] }
  #   { kind: "bar",   title: String, points: [{label, value}] }
  #   { kind: "dual",  title: String,
  #     series_a: { label: "Actual",   points: [{x, y}] },
  #     series_b: { label: "Expected", points: [{x, y}] } }
  #
  # The widget JS knows how to render exactly these three `kind`s.
  class MockClaudeAdapter
    include LlmClient

    # Order matters — first matching intent wins. More specific intents
    # (production, weather) sit above broader ones (efficiency) so that a
    # message like "how much energy did we produce" is not stolen by a
    # generic keyword match.
    INTENT_KEYWORDS = {
      production:    %w[production produce produced producing energy kwh generation generated],
      weather:       %w[weather irradiance storm cloudy rain],
      anomalies:     %w[anomaly anomalies spike spikes drop drops irregular],
      faults:        %w[fault faults inverter offline outage error errors],
      maintenance:   %w[maintenance investigate service repair recommend recommendation recommendations],
      underperform:  %w[panel panels string strings underperform underperforming weak],
      efficiency:    %w[efficiency efficient performance ratio output]
    }.freeze

    DEFAULT_INTENT = :overview

    def complete(user_message:, insights:)
      message = user_message.to_s.downcase.strip
      intent = detect_intent(message)
      window_days = detect_window_days(message)

      case intent
      when :efficiency   then efficiency_reply(insights, window_days)
      when :faults       then fault_reply(insights, window_days)
      when :maintenance  then maintenance_reply(insights)
      when :anomalies    then anomaly_reply(insights, window_days)
      when :underperform then underperform_reply(insights, window_days)
      when :weather      then weather_reply(insights, window_days)
      when :production   then production_reply(insights, window_days)
      else                    overview_reply(insights)
      end
    end

    private

    # Word-boundary match avoids substring traps (e.g. "produce" containing
    # "pr"). Tokens are matched against `\b#{kw}\b` rather than `include?`.
    def detect_intent(message)
      tokens = message.scan(/\b[a-z]+\b/)
      INTENT_KEYWORDS.each do |intent, keywords|
        return intent if (tokens & keywords).any?
      end
      DEFAULT_INTENT
    end

    # Recognize "7", "30", "60", "90 day(s)" or "last month/week" phrases.
    # Falls back to `TelemetryInsights::DEFAULT_DAYS`.
    def detect_window_days(message)
      if (m = message.match(/(\d{1,3})\s*(?:days?|d)\b/))
        m[1].to_i.clamp(1, 90)
      elsif message.include?("last month") || message.include?("past month")
        30
      elsif message.include?("last week") || message.include?("past week")
        7
      elsif message.include?("quarter")
        90
      else
        TelemetryInsights::DEFAULT_DAYS
      end
    end

    def overview_reply(insights)
      o = insights.company_overview
      text = <<~MD.strip
        #{o[:company_name]} fleet overview (last #{o[:window_days]} days):
        Producing #{format_kwh(o[:actual_energy_kwh])} against an expected #{format_kwh(o[:expected_energy_kwh])} — a fleet-wide performance ratio of #{format_pr(o[:performance_ratio])}.
        #{o[:online_inverter_count]} of #{o[:online_inverter_count] + o[:offline_inverter_count]} inverters online across #{o[:site_count]} sites.
        Ask me about anomalies, underperforming panels, fault trends, weather impact, or maintenance.
      MD

      ChatTurn.new(
        reply_text: text,
        visualizations: [ efficiency_chart(insights, o[:window_days]) ],
        intent: :overview
      )
    end

    def efficiency_reply(insights, days)
      trend = insights.efficiency_trend(days: days)
      points = trend[:points]
      best = points.max_by { |p| p[:performance_ratio] }
      worst = points.min_by { |p| p[:performance_ratio] }
      text = <<~MD.strip
        Fleet performance ratio averaged #{format_pr(trend[:mean_performance_ratio])} over the last #{days} days.
        Best day: #{worst_or_best_phrase(best)}; weakest day: #{worst_or_best_phrase(worst)}.
        #{trend_commentary(trend[:mean_performance_ratio])}
      MD

      ChatTurn.new(
        reply_text: text,
        visualizations: [ efficiency_chart_from(trend) ],
        intent: :efficiency
      )
    end

    def fault_reply(insights, days)
      trend = insights.fault_trend(days: days)
      if trend[:total_faults].zero?
        return ChatTurn.new(
          reply_text: "No fault codes were logged in the last #{days} days. All inverters reporting clean.",
          visualizations: [],
          intent: :faults
        )
      end

      top = trend[:by_code].first(3).map { |code, count| "#{code} (#{count})" }.join(", ")
      text = <<~MD.strip
        #{trend[:total_faults]} fault events logged in the last #{days} days.
        Top codes: #{top}.
        #{fault_commentary(trend[:by_code])}
      MD

      ChatTurn.new(
        reply_text: text,
        visualizations: [
          {
            kind: "bar",
            title: "Fault frequency (last #{days}d)",
            points: trend[:by_code].map { |code, count| { label: code, value: count } }
          }
        ],
        intent: :faults
      )
    end

    def maintenance_reply(insights)
      recs = insights.maintenance_recommendations
      if recs.empty?
        return ChatTurn.new(
          reply_text: "No outstanding maintenance recommendations on the fleet.",
          visualizations: [],
          intent: :maintenance
        )
      end

      lines = recs.first(5).map do |r|
        "• [#{r[:severity].upcase}] #{r[:site_id]} — #{r[:recommendation]}"
      end
      text = ([
        "Top maintenance recommendations across the fleet:",
        *lines,
        "Each item maps to a logged event in the diagnostics history."
      ]).join("\n")

      ChatTurn.new(reply_text: text, visualizations: [], intent: :maintenance)
    end

    def anomaly_reply(insights, days)
      a = insights.anomalies(days: days)
      if a[:events].empty? && a[:flagged_reading_count].zero?
        return ChatTurn.new(
          reply_text: "No anomalies detected in the last #{days} days. Fleet operating within tolerance.",
          visualizations: [],
          intent: :anomalies
        )
      end

      narrative_lines = a[:events].first(3).map do |evt|
        "• #{evt[:started_on]} — #{evt[:description]} (#{evt[:severity]})"
      end
      flagged_summary =
        if a[:flagged_reading_count].positive?
          "Plus #{a[:flagged_reading_count]} reading(s) above the anomaly-score threshold; the most acute is on #{a[:flagged_readings].first[:site_name]} string #{a[:flagged_readings].first[:panel_label]} on #{a[:flagged_readings].first[:date]}."
        else
          ""
        end

      text = ([
        "Anomalies in the last #{days} days:",
        *narrative_lines,
        flagged_summary
      ]).reject(&:empty?).join("\n")

      ChatTurn.new(
        reply_text: text,
        visualizations: [ efficiency_chart(insights, days, anomaly_markers: a[:events]) ],
        intent: :anomalies
      )
    end

    def underperform_reply(insights, days)
      panels = insights.underperforming_panels(days: days)
      if panels.empty?
        return ChatTurn.new(
          reply_text: "No panels are running below the #{format_pr(TelemetryInsights::UNDERPERFORMING_PR_THRESHOLD)} performance-ratio threshold.",
          visualizations: [],
          intent: :underperform
        )
      end

      worst = panels.first(3).map do |p|
        "#{p[:site_name]} / #{p[:array_name]} / #{p[:panel_label]} — PR #{format_pr(p[:mean_performance_ratio])}"
      end
      text = <<~MD.strip
        #{panels.size} panel(s) below the #{format_pr(TelemetryInsights::UNDERPERFORMING_PR_THRESHOLD)} PR floor over the last #{days} days.
        Most degraded:
        • #{worst.join("\n• ")}
        Recommend prioritizing the highest-capacity sites first; degradation patterns suggest #{degradation_hint(panels)}.
      MD

      ChatTurn.new(
        reply_text: text,
        visualizations: [
          {
            kind: "bar",
            title: "Worst panels by mean PR (last #{days}d)",
            points: panels.first(8).map { |p| { label: "#{p[:site_id].sub('site_', '').capitalize}-#{p[:panel_label]}", value: (p[:mean_performance_ratio] * 100).round(1) } }
          }
        ],
        intent: :underperform
      )
    end

    def weather_reply(insights, days)
      production = insights.daily_production_vs_expected(days: days)
      lost = production[:points].sum { |p| (p[:expected_kwh] - p[:actual_kwh]).clamp(0, Float::INFINITY) }
      text = <<~MD.strip
        Estimated #{format_kwh(lost.round(1))} of production deferred over the last #{days} days, primarily concentrated on weather-impacted days (storm, overcast, rain).
        See the actual vs expected curve for daily detail.
      MD

      ChatTurn.new(
        reply_text: text,
        visualizations: [ dual_chart(production) ],
        intent: :weather
      )
    end

    def production_reply(insights, days)
      production = insights.daily_production_vs_expected(days: days)
      total_actual = production[:points].sum { |p| p[:actual_kwh] }
      total_expected = production[:points].sum { |p| p[:expected_kwh] }
      pr = total_expected.zero? ? 0.0 : (total_actual / total_expected)
      text = <<~MD.strip
        Last #{days} days: produced #{format_kwh(total_actual.round(1))} against an expected #{format_kwh(total_expected.round(1))} — overall ratio #{format_pr(pr)}.
        See daily actual vs expected below.
      MD

      ChatTurn.new(
        reply_text: text,
        visualizations: [ dual_chart(production) ],
        intent: :production
      )
    end

    # ---- chart helpers ----

    def efficiency_chart(insights, days, anomaly_markers: [])
      efficiency_chart_from(insights.efficiency_trend(days: days), anomaly_markers: anomaly_markers)
    end

    def efficiency_chart_from(trend, anomaly_markers: [])
      {
        kind: "line",
        title: "Performance ratio (last #{trend[:window_days]}d)",
        points: trend[:points].map { |p| { x: p[:date], y: (p[:performance_ratio] * 100).round(2) } },
        markers: Array(anomaly_markers).map { |evt| { x: evt[:started_on], label: evt[:kind] } }
      }
    end

    def dual_chart(production)
      {
        kind: "dual",
        title: "Actual vs expected (last #{production[:window_days]}d)",
        series_a: { label: "Actual",   points: production[:points].map { |p| { x: p[:date], y: p[:actual_kwh] } } },
        series_b: { label: "Expected", points: production[:points].map { |p| { x: p[:date], y: p[:expected_kwh] } } }
      }
    end

    # ---- copy helpers ----

    def trend_commentary(pr)
      if pr >= 0.95
        "Operating within design tolerance; continue routine inspections."
      elsif pr >= 0.88
        "Below nameplate but within acceptable utility-scale operating bands."
      elsif pr >= 0.75
        "Material gap to expected production. Likely a combination of weather, soiling, and at least one fault contributing."
      else
        "Significant production gap — escalate for partner ops review."
      end
    end

    def fault_commentary(by_code)
      if by_code.key?("INVERTER_OFFLINE")
        "INVERTER_OFFLINE drives the bulk of the count — confirm the corresponding outage window has been dispatched."
      elsif by_code.key?("THERMAL_HOTSPOT")
        "Thermal hotspots typically indicate cell-level damage; recommend infrared imaging on next site visit."
      elsif by_code.key?("VOLTAGE_DIP")
        "Voltage dips align with weather windows; cross-check the storm log before treating as a hardware fault."
      else
        "No dominant fault pattern; review the bar chart for distribution."
      end
    end

    def degradation_hint(panels)
      sites = panels.map { |p| p[:site_id] }.uniq
      if sites.size == 1
        "a localized issue at #{sites.first.tr('_', ' ').capitalize}."
      elsif panels.first[:panel_label].start_with?("A")
        "early-stage thermal degradation concentrated on string A."
      else
        "fleet-wide drift consistent with soiling or seasonal change."
      end
    end

    def worst_or_best_phrase(point)
      "PR #{format_pr(point[:performance_ratio])} on #{point[:date]}"
    end

    def format_pr(value)
      "#{(value.to_f * 100).round(1)}%"
    end

    def format_kwh(value)
      "#{value.is_a?(Numeric) ? format('%.1f', value) : value} kWh"
    end
  end
end
