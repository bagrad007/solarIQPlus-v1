# frozen_string_literal: true

# Server-side rollup for the per-Site Dashboard view (the ERB tiles + the
# small React island in app/javascript/dashboard/). Returns a single Hash
# the view drops directly onto its data-payload attribute.
#
# All queries run under the caller's RLS context — the controller has already
# stamped GUCs and dropped into `app_user`, so this object never thinks about
# authorization. If a caller can't see telemetry for the Site, the queries
# return empty and every section reads as zero / nil.
#
# Energy totals (kWh) are integrated from sampled power (kW) using
# Telemetry::TrapezoidIntegrator with a 1h gap cap so a long polling outage
# can't manufacture phantom energy.
class SiteOperationalSummary
  MAX_INTEGRATION_GAP   = 1.hour
  GAUGE_FALLBACK_FLOOR  = 5.0   # absolute minimum max_kw when nameplate unset
  GAUGE_FALLBACK_HEADROOM = 1.25  # 25% headroom over the current value
  MAX_CHART_POINTS      = 400
  LIVE_CHART_WINDOW     = 6.hours

  def initialize(site, now: Time.current)
    @site = site
    @now  = now
  end

  # +weather:+ optional Open-Meteo shaped hash from Weather::Cache (today/tomorrow
  # slices) for the dashboard environment strip; omit when unknown.
  def to_h(weather: nil)
    today_rows  = telemetry_between(today_start, @now)
    mtd_rows    = telemetry_between(@now.utc.beginning_of_month, @now)
    ytd_rows    = telemetry_between(@now.utc.beginning_of_year, @now)
    all_rows    = telemetry_between(Time.utc(1970, 1, 1), @now)
    latest      = today_rows.last || mtd_rows.last || ytd_rows.last || all_rows.last

    {
      totals: {
        lifetime_kwh: round_kwh(integrate(all_rows,  :power_kw)),
        ytd_kwh:      round_kwh(integrate(ytd_rows,  :power_kw)),
        mtd_kwh:      round_kwh(integrate(mtd_rows,  :power_kw)),
        today_kwh:    round_kwh(integrate(today_rows, :power_kw))
      },
      today: today_section(today_rows, latest),
      latest: latest_section(latest),
      environment: environment_section(latest, weather),
      chart: chart_section(today_rows),
      gauges: gauges_section(latest)
    }
  end

  private

  # --- data access ------------------------------------------------------------

  def telemetry_between(from, to)
    Telemetry
      .where(site_id: @site.id)
      .where(recorded_at: from..to)
      .order(:recorded_at)
      .to_a
  end

  # --- section builders -------------------------------------------------------

  def today_section(rows, latest)
    solar  = integrate(rows, :power_kw)
    export = integrate(rows) { |p| [ (p["grid_flow_kw"] || 0).to_f, 0 ].max }
    self_c = [ solar - export, 0 ].max

    {
      exported_kwh:         round_kwh(export),
      self_consumption_kwh: round_kwh(self_c),
      current_kw_in_out:    latest && (latest.metric_payload || {})["grid_flow_kw"]&.to_f,
      latest_at:            latest&.recorded_at
    }
  end

  def latest_section(row)
    payload = row&.metric_payload || {}
    {
      ac_power_kw:     payload["power_kw"]&.to_f,
      dc_power_kw:     payload["dc_power_kw"]&.to_f,
      dc_amps:         payload["dc_amps"]&.to_f,
      ac_amps:         payload["ac_amps"]&.to_f,
      dc_voltage:      payload["string_voltage"],
      ac_voltage:      payload["ac_voltage"],
      alarm_state:     row&.alarm_state,
      inverter_status: payload["inverter_status"]
    }
  end

  def solar_today_series(rows)
    rows.map do |r|
      {
        t:  r.recorded_at.utc.iso8601,
        kw: ((r.metric_payload || {})["power_kw"] || 0).to_f.round(2)
      }
    end
  end

  # Multi-window solar kW (+ optional AC voltage) for dashboard range toggles.
  def chart_section(today_rows)
    live_rows  = telemetry_between(@now - LIVE_CHART_WINDOW, @now)
    week_rows  = telemetry_between(@now - 7.days, @now)
    month_rows = telemetry_between(@now - 30.days, @now)

    ranges = {}
    add_range!(ranges, "live", series_points(live_rows))
    add_range!(ranges, "1d",  series_points(today_rows))
    add_range!(ranges, "1w",  series_points(week_rows))
    add_range!(ranges, "1m",  series_points(month_rows))

    {
      solar_today_series: solar_today_series(today_rows),
      solar_series_by_range: ranges,
      default_chart_range: pick_default_chart_range(ranges)
    }
  end

  def add_range!(ranges, key, points)
    ranges[key] = points if points.length >= 2
  end

  def pick_default_chart_range(ranges)
    %w[1d live 1w 1m].each { |k| return k if ranges[k]&.length.to_i >= 2 }
    ranges.keys.first
  end

  # Each point: { t:, kw:, ac_v? } — +ac_v+ only when the row carried ac_voltage.
  def series_points(rows)
    raw = rows.map do |r|
      mp = r.metric_payload || {}
      pt = {
        t:  r.recorded_at.utc.iso8601,
        kw: (mp["power_kw"] || 0).to_f.round(2)
      }
      v = mp["ac_voltage"]
      pt[:ac_v] = v.to_f.round(1) if v.present?
      pt
    end
    return raw if raw.length <= MAX_CHART_POINTS

    downsample_points(raw, MAX_CHART_POINTS)
  end

  def downsample_points(points, max_n)
    n = points.length
    return points if n <= max_n

    idxs = (0...max_n).map { |i| ((n - 1) * i.to_f / (max_n - 1)).round.clamp(0, n - 1) }.uniq.sort
    idxs.map { |idx| points[idx] }
  end

  def environment_section(latest, weather)
    payload = latest&.metric_payload || {}
    wt = weather&.dig(:today)
    out = {}
    amb_f = TemperatureConversion.fahrenheit_from_celsius(payload["ambient_temp_c"]&.to_f)
    inv_f = TemperatureConversion.fahrenheit_from_celsius(payload["inverter_temp_c"]&.to_f)
    out[:ambient_temp_f] = amb_f unless amb_f.nil?
    out[:inverter_temp_f] = inv_f unless inv_f.nil?
    if wt
      psh = wt[:peak_sun_hours]
      out[:peak_sun_hours_today] = psh.to_f.round(2) if psh.present?
      out[:sky_condition] = wt[:condition].to_s if wt[:condition].present?
    end
    out
  end

  def gauges_section(latest)
    payload = latest&.metric_payload || {}
    ac_kw = payload["power_kw"]&.to_f
    dc_kw = payload["dc_power_kw"]&.to_f

    {
      dc: { current_kw: dc_kw, max_kw: gauge_max(dc_kw) },
      ac: { current_kw: ac_kw, max_kw: gauge_max(ac_kw) }
    }
  end

  # --- helpers ----------------------------------------------------------------

  # Pull a numeric field directly out of metric_payload. The block form is
  # available too for derived fields like signed grid flow.
  def integrate(rows, field = nil, &block)
    block ||= ->(p) { (p[field.to_s] || 0).to_f }
    Telemetry::TrapezoidIntegrator.integrate(rows, max_gap: MAX_INTEGRATION_GAP, &block)
  end

  # nameplate_kw is the truth source; if absent (older rows, freshly created
  # Sites), pick a max that's just above the current reading so the gauge has
  # a sensible needle position.
  def gauge_max(current_kw)
    nameplate = @site.nameplate_kw
    return nameplate.to_f if nameplate.present?
    return GAUGE_FALLBACK_FLOOR if current_kw.nil? || current_kw <= 0

    [ current_kw * GAUGE_FALLBACK_HEADROOM, GAUGE_FALLBACK_FLOOR ].max
  end

  def round_kwh(value)
    value.to_f.round(2)
  end

  def today_start
    @now.utc.beginning_of_day
  end
end
