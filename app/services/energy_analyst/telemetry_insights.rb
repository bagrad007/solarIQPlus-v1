# frozen_string_literal: true

module EnergyAnalyst
  # Pure-function knowledge layer over the parsed telemetry payload. Every
  # public method returns a plain Hash (or Array of Hashes) so the same shape
  # works as both Ruby data for the mock adapter *and* serialized context
  # for a future LLM call.
  #
  # All callers go through one entry point — `TelemetryInsights.new` — which
  # caches the parsed Hash from `TelemetryRepository`. No method here mutates
  # state; the underlying Hash is deeply frozen.
  class TelemetryInsights
    DEFAULT_DAYS = 30
    UNDERPERFORMING_PR_THRESHOLD = 0.85

    def initialize(payload: TelemetryRepository.data)
      @payload = payload
    end

    def company_overview
      total_actual = 0.0
      total_expected = 0.0
      online_inverters = Set.new
      offline_inverters = Set.new
      open_faults = Hash.new(0)

      walk_recent(DEFAULT_DAYS) do |_site, array, _panel, reading|
        total_actual += reading[:daily_energy_kwh].to_f
        total_expected += reading[:expected_energy_kwh].to_f
        if reading[:inverter_status] == "offline"
          offline_inverters << array[:inverter_id]
        else
          online_inverters << array[:inverter_id]
        end
        Array(reading[:fault_codes]).each { |code| open_faults[code] += 1 }
      end

      pr = total_expected.zero? ? 0.0 : (total_actual / total_expected)

      {
        company_name: @payload[:company_name],
        region: @payload[:region],
        site_count: sites.size,
        fleet_capacity_kw: @payload[:fleet_capacity_kw],
        window_days: DEFAULT_DAYS,
        actual_energy_kwh: total_actual.round(1),
        expected_energy_kwh: total_expected.round(1),
        performance_ratio: pr.round(3),
        online_inverter_count: (online_inverters - offline_inverters).size,
        offline_inverter_count: offline_inverters.size,
        active_fault_codes: open_faults
      }
    end

    # Per-day fleet-wide PR over the last `days` days, returned as an
    # ordered array suitable for line-chart rendering.
    def efficiency_trend(days: DEFAULT_DAYS)
      buckets = Hash.new { |h, k| h[k] = { actual: 0.0, expected: 0.0 } }

      walk_recent(days) do |_site, _array, _panel, reading|
        bucket = buckets[reading[:date]]
        bucket[:actual] += reading[:daily_energy_kwh].to_f
        bucket[:expected] += reading[:expected_energy_kwh].to_f
      end

      points = buckets.keys.sort.map do |date|
        b = buckets[date]
        pr = b[:expected].zero? ? 0.0 : (b[:actual] / b[:expected])
        { date: date, performance_ratio: pr.round(3) }
      end

      mean_pr =
        if points.empty?
          0.0
        else
          (points.sum { |p| p[:performance_ratio] } / points.size).round(3)
        end

      { window_days: days, mean_performance_ratio: mean_pr, points: points }
    end

    # Anomaly summary: pulls from the prebuilt `events` array for narrative
    # accuracy, plus surfaces any reading whose `anomaly_score` exceeds
    # the threshold within the requested window.
    def anomalies(days: DEFAULT_DAYS)
      cutoff = reference_date - days
      narrative = Array(@payload[:events]).select do |evt|
        Date.parse(evt[:started_on]) >= cutoff
      end

      hot_readings = []
      walk_recent(days) do |site, array, panel, reading|
        next if reading[:anomaly_score].to_f < 0.25
        hot_readings << {
          date: reading[:date],
          site_id: site[:id],
          site_name: site[:name],
          array_id: array[:id],
          panel_label: panel[:label],
          anomaly_score: reading[:anomaly_score],
          fault_codes: reading[:fault_codes],
          performance_ratio: reading[:performance_ratio]
        }
      end

      hot_readings.sort_by! { |r| -r[:anomaly_score] }

      {
        window_days: days,
        events: narrative,
        flagged_readings: hot_readings.first(8),
        flagged_reading_count: hot_readings.size
      }
    end

    # Panels whose mean PR over the window sits below the threshold.
    def underperforming_panels(days: DEFAULT_DAYS)
      results = []

      sites.each do |site|
        site[:arrays].each do |array|
          array[:panels].each do |panel|
            recent = panel[:daily_readings].last(days)
            next if recent.empty?
            mean_pr = recent.sum { |r| r[:performance_ratio].to_f } / recent.size
            next if mean_pr >= UNDERPERFORMING_PR_THRESHOLD

            results << {
              site_id: site[:id],
              site_name: site[:name],
              array_id: array[:id],
              array_name: array[:name],
              panel_id: panel[:id],
              panel_label: panel[:label],
              mean_performance_ratio: mean_pr.round(3),
              days_observed: recent.size
            }
          end
        end
      end

      results.sort_by { |r| r[:mean_performance_ratio] }
    end

    # Field-tech actionable list. Prefer events that have a clear next step.
    def maintenance_recommendations
      Array(@payload[:events]).map do |evt|
        {
          event_id: evt[:id],
          site_id: evt[:site_id],
          severity: evt[:severity],
          recommendation: recommendation_for(evt),
          context: evt[:description]
        }
      end
    end

    # Frequency table of fault codes within the window, plus per-day
    # totals for chart rendering.
    def fault_trend(days: DEFAULT_DAYS)
      counts = Hash.new(0)
      per_day = Hash.new(0)

      walk_recent(days) do |_site, _array, _panel, reading|
        Array(reading[:fault_codes]).each do |code|
          counts[code] += 1
          per_day[reading[:date]] += 1
        end
      end

      {
        window_days: days,
        total_faults: counts.values.sum,
        by_code: counts.sort_by { |_c, n| -n }.to_h,
        per_day: per_day.keys.sort.map { |d| { date: d, count: per_day[d] } }
      }
    end

    # Daily fleet production vs expected — for the dual-series chart.
    def daily_production_vs_expected(days: DEFAULT_DAYS)
      actual = Hash.new(0.0)
      expected = Hash.new(0.0)

      walk_recent(days) do |_site, _array, _panel, reading|
        actual[reading[:date]] += reading[:daily_energy_kwh].to_f
        expected[reading[:date]] += reading[:expected_energy_kwh].to_f
      end

      points = actual.keys.sort.map do |date|
        { date: date, actual_kwh: actual[date].round(1), expected_kwh: expected[date].round(1) }
      end

      { window_days: days, points: points }
    end

    # The "anchor" date of the dataset. Real-time clock would be wrong here
    # because the JSON is generated against a fixed reference date.
    def reference_date
      @reference_date ||= Date.parse(@payload[:reference_date])
    end

    def sites
      @payload[:sites]
    end

    private

    # Yields every (site, array, panel, reading) tuple within the last
    # `days` days. Cheap because the inner array is tiny (90 entries).
    def walk_recent(days)
      sites.each do |site|
        site[:arrays].each do |array|
          array[:panels].each do |panel|
            panel[:daily_readings].last(days).each do |reading|
              yield site, array, panel, reading
            end
          end
        end
      end
    end

    def recommendation_for(evt)
      case evt[:kind]
      when "outage"      then "Dispatch a technician to inspect inverter #{evt[:inverter_id]} and verify firmware integrity."
      when "degradation" then "Schedule infrared inspection of string #{evt[:panel_label]} on #{evt[:site_id]}; consider partial string replacement if cell-level hot spots are confirmed."
      when "weather"     then "Cross-check insurance / SLA reporting; no field action required unless damage is observed on next site walk."
      when "soiling"     then "Reinstate the missed cleaning cycle on #{evt[:site_id]}; expect ~10 percentage points of PR recovery within 48 hours."
      else                    "Open a case for review by partner ops."
      end
    end
  end
end
