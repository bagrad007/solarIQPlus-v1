# frozen_string_literal: true

# Server-side rollup for the per-Site Diagnostics page (the React island in
# app/javascript/diagnostics/). Returns a self-contained JSON-serializable Hash
# that the view drops into a data-payload attribute on the mount div.
#
# All queries run under the caller's RLS context — the controller has already
# stamped GUCs and dropped into `app_user`, so this object never thinks about
# authorization. If a caller can't see telemetry for the Site, the queries
# return empty and the page renders zeros.
#
# Time windows are fixed:
#   - import/export series: trailing 12 hours (matches the mock header).
#   - 7-day series + last-7-days totals: trailing 7 calendar days (UTC).
#   - "today" tiles: midnight-UTC to now.
#
# Energy totals (kWh) are integrated from sampled power (kW) using the trapezoid
# rule between consecutive readings. We cap the per-step gap at 1 hour so a long
# polling outage can't manufacture phantom energy.
class SiteDiagnostics
  IMPORT_EXPORT_WINDOW = 12.hours
  SEVEN_DAY_WINDOW     = 7.days
  MAX_INTEGRATION_GAP  = 1.hour

  def initialize(site, now: Time.current)
    @site = site
    @now  = now
  end

  def to_h
    today_rows = telemetry_between(today_start, @now)
    week_rows  = telemetry_between(@now - SEVEN_DAY_WINDOW, @now)
    chart_rows = telemetry_between(@now - IMPORT_EXPORT_WINDOW, @now)
    latest     = week_rows.last

    {
      site: { id: @site.id, name: @site.name },
      today: today_tiles(today_rows, latest),
      today_pie: today_pie(today_rows),
      energy_flow: energy_flow(latest),
      last_7_days: week_totals(week_rows),
      import_export_series: import_export_series(chart_rows),
      solar_7d_series: solar_7d_series(week_rows)
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

  # --- "today" tiles ----------------------------------------------------------

  # solar_today_kwh = ∫ power_kw dt over today
  # export_today_kwh = ∫ max(grid_flow_kw, 0) dt over today
  # import_today_kwh = ∫ max(-grid_flow_kw, 0) dt over today
  # self_consumption_today_kwh = solar_today_kwh - export_today_kwh
  # consumed_today_kwh = self_consumption_today_kwh + import_today_kwh
  def today_tiles(rows, latest)
    solar  = integrate(rows) { |p| (p["power_kw"] || 0).to_f }
    export = integrate(rows) { |p| [ (p["grid_flow_kw"] || 0).to_f, 0 ].max }
    import = integrate(rows) { |p| [ -(p["grid_flow_kw"] || 0).to_f, 0 ].max }
    self_c = [ solar - export, 0 ].max

    temp_c = latest_payload(latest)["inverter_temp_c"]&.to_f
    {
      self_consumption_kwh: round_kwh(self_c),
      grid_consumption_kwh: round_kwh(import),
      consumed_kwh:         round_kwh(self_c + import),
      inverter_temp_c:      temp_c,
      inverter_temp_f:      TemperatureConversion.fahrenheit_from_celsius(temp_c)
    }
  end

  # --- today's import/export pie ---------------------------------------------

  # Two-slice breakdown for the Diagnostics pie chart: of today's solar kWh,
  # how much was exported vs. how much was self-consumed. Mirrors the
  # integration done in today_tiles but exposes the values the chart needs in
  # one named slice so the React island doesn't have to reach across keys.
  def today_pie(rows)
    solar  = integrate(rows) { |p| (p["power_kw"] || 0).to_f }
    export = integrate(rows) { |p| [ (p["grid_flow_kw"] || 0).to_f, 0 ].max }
    {
      exported_kwh:         round_kwh(export),
      self_consumption_kwh: round_kwh([ solar - export, 0 ].max)
    }
  end

  # --- live energy flow snapshot ----------------------------------------------

  # Instantaneous "where is energy flowing right now" view, derived from the
  # most recent telemetry row. Powers the EnergyFlowPanel on the Diagnostics
  # page (icon schematic + four metric tiles).
  #
  # Sign convention follows the existing telemetry model:
  #   solar_w  = power_kw × 1000                  (always >= 0)
  #   grid_w   = grid_flow_kw × 1000              (positive = exporting)
  #   house_w  = (power_kw - grid_flow_kw) × 1000 (always >= 0 in practice)
  #
  # Battery is stubbed to nil — we don't model batteries yet. The presence of
  # the keys in the payload is the seam for when we do.
  def energy_flow(latest)
    base = {
      solar_w:               nil,
      grid_w:                nil,
      house_w:               nil,
      battery_w:             nil,
      battery_soc_pct:       nil,
      self_sufficiency_pct:  nil,
      self_consumption_pct:  nil,
      solar_net_w:           nil,
      recorded_at:           nil
    }
    return base if latest.nil?

    payload    = latest.metric_payload || {}
    # Defensive clamp: the Telemetry contract says power_kw >= 0 (solar can't
    # go negative), but seeds and noisy ingestion can violate that. Clamp here
    # so the panel never surfaces "-79,200 W solar".
    solar_kw   = [ (payload["power_kw"] || 0).to_f, 0 ].max
    grid_kw    = (payload["grid_flow_kw"] || 0).to_f
    house_kw   = solar_kw - grid_kw
    import_kw  = [ -grid_kw, 0 ].max
    export_kw  = [ grid_kw,  0 ].max

    base.merge(
      solar_w:              (solar_kw * 1000).round,
      grid_w:               (grid_kw  * 1000).round,
      house_w:              (house_kw * 1000).round,
      self_sufficiency_pct: self_sufficiency_pct(house_kw, import_kw),
      self_consumption_pct: self_consumption_pct(solar_kw, export_kw),
      solar_net_w:          (-import_kw * 1000 + export_kw * 1000).round,
      recorded_at:          latest.recorded_at
    )
  end

  # Self-sufficiency = share of consumption met without grid import.
  # Undefined (nil) when consumption is zero.
  def self_sufficiency_pct(house_kw, import_kw)
    return nil if house_kw <= 0

    (((house_kw - import_kw) / house_kw) * 100).clamp(0, 100).round(1)
  end

  # Self-consumption = share of solar generation consumed on-site (not exported).
  # Undefined (nil) when solar is zero.
  def self_consumption_pct(solar_kw, export_kw)
    return nil if solar_kw <= 0

    (((solar_kw - export_kw) / solar_kw) * 100).clamp(0, 100).round(1)
  end

  # --- last 7 days totals -----------------------------------------------------

  def week_totals(rows)
    {
      export_kwh: round_kwh(integrate(rows) { |p| [ (p["grid_flow_kw"] || 0).to_f, 0 ].max }),
      import_kwh: round_kwh(integrate(rows) { |p| [ -(p["grid_flow_kw"] || 0).to_f, 0 ].max })
    }
  end

  # --- 12h signed series ------------------------------------------------------

  def import_export_series(rows)
    rows.map do |r|
      {
        t: r.recorded_at.utc.iso8601,
        kw: ((r.metric_payload || {})["grid_flow_kw"] || 0).to_f.round(2)
      }
    end
  end

  # --- 7-day daily kWh bars ---------------------------------------------------

  # Bucket telemetry into UTC calendar days, then integrate within each bucket.
  # The chart always renders 7 bars even on days with zero readings.
  def solar_7d_series(rows)
    by_day = rows.group_by { |r| r.recorded_at.utc.to_date }
    week_start = (@now.utc.to_date - 6)

    (0..6).map do |offset|
      day = week_start + offset
      day_rows = by_day[day] || []
      {
        d: day.iso8601,
        kwh: round_kwh(integrate(day_rows) { |p| (p["power_kw"] || 0).to_f })
      }
    end
  end

  # --- integration primitive --------------------------------------------------

  def integrate(rows, &block)
    Telemetry::TrapezoidIntegrator.integrate(rows, max_gap: MAX_INTEGRATION_GAP, &block)
  end

  def latest_payload(row)
    row&.metric_payload || {}
  end

  def round_kwh(value)
    value.to_f.round(2)
  end

  def today_start
    @now.utc.beginning_of_day
  end
end
