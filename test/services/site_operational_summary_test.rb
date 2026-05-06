require "test_helper"

class SiteOperationalSummaryTest < ActiveSupport::TestCase
  setup do
    build_tenant_tree
    @site = @site_a
    @site.update!(nameplate_kw: 10.0, latitude: 33.45, longitude: -112.07)
    # Mid-day on 2026-05-05 (UTC). Picked so today/MTD/YTD are all distinct
    # windows we can stuff readings into deterministically.
    @reference = Time.utc(2026, 5, 5, 12, 0, 0)
  end

  test "totals integrate kWh across lifetime / YTD / MTD / today windows" do
    insert_telemetry([
      # Two readings 1h apart at constant 4 kW two months back -> +4 kWh
      # in lifetime + YTD only (not MTD, not today).
      { offset: -60.days,            power_kw: 4.0 },
      { offset: -60.days + 1.hour,   power_kw: 4.0 },
      # Earlier this month, before today -> +4 kWh in lifetime + YTD + MTD only.
      { offset: -3.days,             power_kw: 4.0 },
      { offset: -3.days + 1.hour,    power_kw: 4.0 },
      # Today -> +4 kWh in every window.
      { offset: 0.hours,             power_kw: 4.0 },
      { offset: 1.hour,              power_kw: 4.0 }
    ])

    totals = SiteOperationalSummary.new(@site, now: @reference + 2.hours).to_h[:totals]

    assert_in_delta 12.0, totals[:lifetime_kwh], 0.01
    assert_in_delta 12.0, totals[:ytd_kwh],      0.01
    assert_in_delta  8.0, totals[:mtd_kwh],      0.01
    assert_in_delta  4.0, totals[:today_kwh],    0.01
  end

  test "today section splits exported kWh and self-consumption from grid_flow_kw" do
    insert_telemetry([
      { offset: 0.hours, power_kw: 4.0, grid_flow_kw:  1.0 },
      { offset: 1.hour,  power_kw: 4.0, grid_flow_kw:  1.0 },
      { offset: 2.hours, power_kw: 4.0, grid_flow_kw: -1.0 }
    ])

    today = SiteOperationalSummary.new(@site, now: @reference + 3.hours).to_h[:today]

    # Solar = ∫4 kW · 2h = 8 kWh.
    # Export = trapezoid of max(grid,0): (1+1)/2·1 + (1+0)/2·1 = 1.5 kWh.
    # Self-consumption = solar - export = 6.5 kWh.
    assert_in_delta 1.5, today[:exported_kwh],         0.01
    assert_in_delta 6.5, today[:self_consumption_kwh], 0.01
  end

  test "today section reports the latest current_kw_in_out (signed grid flow)" do
    insert_telemetry([
      { offset: 0.hours, power_kw: 4.0, grid_flow_kw: 2.0 },
      { offset: 1.hour,  power_kw: 4.0, grid_flow_kw: 3.5 }
    ])

    today = SiteOperationalSummary.new(@site, now: @reference + 2.hours).to_h[:today]

    assert_equal 3.5, today[:current_kw_in_out]
    assert_equal (@reference + 1.hour).to_i, today[:latest_at].to_i
  end

  test "latest section surfaces the inverter electrical vector from the newest reading" do
    insert_telemetry([
      {
        offset:          0.hours,
        power_kw:        4.0,
        dc_power_kw:     4.2,
        dc_amps:         10.5,
        ac_amps:         16.7,
        string_voltage:  400,
        ac_voltage:      240,
        inverter_status: "online"
      }
    ])

    latest = SiteOperationalSummary.new(@site, now: @reference + 1.hour).to_h[:latest]

    assert_equal 4.0,      latest[:ac_power_kw]
    assert_equal 4.2,      latest[:dc_power_kw]
    assert_equal 10.5,     latest[:dc_amps]
    assert_equal 16.7,     latest[:ac_amps]
    assert_equal 400,      latest[:dc_voltage]
    assert_equal 240,      latest[:ac_voltage]
    assert_equal "online", latest[:inverter_status]
  end

  test "chart section exposes the today solar generation series" do
    insert_telemetry([
      { offset: 0.hours, power_kw: 0.0 },
      { offset: 1.hour,  power_kw: 4.0 },
      { offset: 2.hours, power_kw: 4.0 }
    ])

    chart = SiteOperationalSummary.new(@site, now: @reference + 3.hours).to_h[:chart]

    assert_equal 3, chart[:solar_today_series].length
    assert_equal [ 0.0, 4.0, 4.0 ], chart[:solar_today_series].map { |p| p[:kw] }
    assert chart[:solar_series_by_range].key?("1d")
    assert_equal 3, chart[:solar_series_by_range]["1d"].length
    assert_equal "1d", chart[:default_chart_range]
    # The today's import/export pie lives on the Diagnostics page, not the
    # Dashboard — so it must NOT be in the operational summary.
    assert_not chart.key?(:pie),
               "pie chart belongs to SiteDiagnostics#today_pie, not SiteOperationalSummary#chart"
  end

  test "gauges report current_kw and use the Site's nameplate_kw as the max scale" do
    insert_telemetry([
      { offset: 0.hours, power_kw: 5.5, dc_power_kw: 5.8 }
    ])

    gauges = SiteOperationalSummary.new(@site, now: @reference + 1.hour).to_h[:gauges]

    assert_equal 5.8,  gauges[:dc][:current_kw]
    assert_equal 5.5,  gauges[:ac][:current_kw]
    assert_equal 10.0, gauges[:dc][:max_kw]
    assert_equal 10.0, gauges[:ac][:max_kw]
  end

  test "gauges fall back to a sensible max when nameplate_kw is unset" do
    @site.update!(nameplate_kw: nil)
    insert_telemetry([
      { offset: 0.hours, power_kw: 3.0, dc_power_kw: 3.2 }
    ])

    gauges = SiteOperationalSummary.new(@site, now: @reference + 1.hour).to_h[:gauges]

    assert_not_nil gauges[:dc][:max_kw], "max_kw must always be present so the gauge can render"
    assert gauges[:dc][:max_kw] >= 3.2,  "fallback must be >= the current value"
  end

  test "no telemetry returns zeroed totals, nil latest, and empty chart" do
    payload = SiteOperationalSummary.new(@site, now: @reference).to_h

    assert_equal 0.0, payload[:totals][:lifetime_kwh]
    assert_equal 0.0, payload[:totals][:ytd_kwh]
    assert_equal 0.0, payload[:totals][:mtd_kwh]
    assert_equal 0.0, payload[:totals][:today_kwh]
    assert_equal 0.0, payload[:today][:exported_kwh]
    assert_equal 0.0, payload[:today][:self_consumption_kwh]
    assert_nil payload[:today][:current_kw_in_out]
    assert_nil payload[:today][:latest_at]
    assert_nil payload[:latest][:ac_power_kw]
    assert_empty payload[:chart][:solar_today_series]
    assert_equal({}, payload[:chart][:solar_series_by_range])
    assert_nil payload[:chart][:default_chart_range]
    assert_equal({}, payload[:environment])
  end

  private

  def insert_telemetry(rows)
    rows.each do |r|
      payload = {
        "power_kw"        => r[:power_kw],
        "grid_flow_kw"    => r[:grid_flow_kw],
        "dc_power_kw"     => r[:dc_power_kw],
        "dc_amps"         => r[:dc_amps],
        "ac_amps"         => r[:ac_amps],
        "ac_voltage"      => r[:ac_voltage],
        "string_voltage"  => r[:string_voltage],
        "inverter_status" => r[:inverter_status]
      }.compact
      Telemetry.create!(
        site:           @site,
        organization:   @site.organization,
        recorded_at:    @reference + r[:offset],
        metric_payload: payload,
        alarm_state:    "normal"
      )
    end
  end
end
