require "test_helper"

class SiteDiagnosticsTest < ActiveSupport::TestCase
  setup do
    build_tenant_tree
    @site = @site_a
    @reference = Time.utc(2026, 5, 5, 12, 0, 0)
  end

  test "today tiles integrate solar, import and export from the trapezoid rule" do
    # Three readings, 1h apart. Trapezoid of:
    #   solar  ∫power_kw      = (0+4)/2 + (4+0)/2 = 4.0 kWh
    #   export ∫max(grid,0)   = (0+1)/2 + (1+0)/2 = 1.0 kWh
    #   import ∫max(-grid,0)  = (2+0)/2 + (0+2)/2 = 2.0 kWh
    # Self consumption = solar − export = 3.0 kWh
    # Total consumed   = self_cons + import = 5.0 kWh
    insert_telemetry([
      { offset: 0.hours,  power_kw: 0.0,  grid_flow_kw: -2.0, inverter_temp_c: 35 },
      { offset: 1.hour,   power_kw: 4.0,  grid_flow_kw:  1.0, inverter_temp_c: 45 },
      { offset: 2.hours,  power_kw: 0.0,  grid_flow_kw: -2.0, inverter_temp_c: 40 }
    ])

    payload = SiteDiagnostics.new(@site, now: @reference + 3.hours).to_h
    today   = payload[:today]

    assert_in_delta 3.0, today[:self_consumption_kwh], 0.01
    assert_in_delta 2.0, today[:grid_consumption_kwh], 0.01
    assert_in_delta 5.0, today[:consumed_kwh],         0.01
    assert_equal 40.0, today[:inverter_temp_c]
    assert_in_delta 104.0, today[:inverter_temp_f], 0.01
  end

  test "today_pie surfaces exported_kwh and self_consumption_kwh for today's pie chart" do
    insert_telemetry([
      { offset: 0.hours, power_kw: 0.0, grid_flow_kw: -1.0 },
      { offset: 1.hour,  power_kw: 4.0, grid_flow_kw:  1.0 },
      { offset: 2.hours, power_kw: 4.0, grid_flow_kw:  2.0 }
    ])

    pie = SiteDiagnostics.new(@site, now: @reference + 3.hours).to_h[:today_pie]

    # Solar today = (0+4)/2 + (4+4)/2 = 6 kWh
    # Export today = (0+1)/2 + (1+2)/2 = 2.0 kWh
    # Self-consumption = 6 - 2 = 4 kWh
    assert_in_delta 2.0, pie[:exported_kwh],         0.01
    assert_in_delta 4.0, pie[:self_consumption_kwh], 0.01
  end

  test "energy_flow snapshots the latest reading when the site is importing from grid" do
    insert_telemetry([
      { offset: -2.minutes, power_kw: 0.721, grid_flow_kw: -2.865 }
    ])

    flow = SiteDiagnostics.new(@site, now: @reference).to_h[:energy_flow]

    assert_equal 721,    flow[:solar_w]
    assert_equal(-2865,  flow[:grid_w])      # negative = importing from grid
    assert_equal 3586,   flow[:house_w]      # consumption = solar - grid_flow
    assert_nil flow[:battery_w]              # battery stubbed off
    assert_nil flow[:battery_soc_pct]
    assert_in_delta 20.1,  flow[:self_sufficiency_pct], 0.2
    assert_equal 100.0,    flow[:self_consumption_pct] # nothing exported when importing
    assert_equal(-2865,    flow[:solar_net_w])         # consumption - solar
    assert_equal((@reference - 2.minutes).to_i, flow[:recorded_at].to_i)
  end

  test "energy_flow reports a positive solar_net and partial self-consumption when exporting" do
    # Solar 5 kW, grid_flow +2 kW (exporting). Consumption = 5 - 2 = 3 kW.
    insert_telemetry([
      { offset: 0.hours, power_kw: 5.0, grid_flow_kw: 2.0 }
    ])

    flow = SiteDiagnostics.new(@site, now: @reference + 1.hour).to_h[:energy_flow]

    assert_equal 5000, flow[:solar_w]
    assert_equal 2000, flow[:grid_w]
    assert_equal 3000, flow[:house_w]
    assert_equal 100.0, flow[:self_sufficiency_pct]              # zero import
    assert_in_delta 60.0, flow[:self_consumption_pct], 0.1       # 3 of 5 kW consumed on-site
    assert_equal 2000, flow[:solar_net_w]                        # surplus
  end

  test "energy_flow handles zero-solar nighttime gracefully" do
    insert_telemetry([
      { offset: 0.hours, power_kw: 0.0, grid_flow_kw: -1.5 }
    ])

    flow = SiteDiagnostics.new(@site, now: @reference + 1.hour).to_h[:energy_flow]

    assert_equal 0,     flow[:solar_w]
    assert_equal 1500,  flow[:house_w]
    assert_equal 0.0,   flow[:self_sufficiency_pct]
    assert_nil flow[:self_consumption_pct], "self-consumption is undefined when solar is 0"
    assert_equal(-1500, flow[:solar_net_w])
  end

  test "energy_flow clamps negative power_kw to 0 (telemetry contract guarantees solar >= 0)" do
    # The seed used to dip below zero at night; the model contract still says
    # power_kw is non-negative. The presenter must defend the panel from any
    # noisy / out-of-contract reading rather than rendering "-79,200 W solar".
    insert_telemetry([
      { offset: 0.hours, power_kw: -1.5, grid_flow_kw: -2.0 }
    ])

    flow = SiteDiagnostics.new(@site, now: @reference + 1.hour).to_h[:energy_flow]

    assert_equal 0,    flow[:solar_w],  "solar_w must never be negative"
    assert_equal 2000, flow[:house_w],  "house_w = max(solar, 0) - grid_flow when importing"
    assert_nil flow[:self_consumption_pct], "self-consumption is undefined when solar is 0"
  end

  test "energy_flow returns nil values when there is no telemetry at all" do
    flow = SiteDiagnostics.new(@site, now: @reference).to_h[:energy_flow]

    assert_nil flow[:solar_w]
    assert_nil flow[:grid_w]
    assert_nil flow[:house_w]
    assert_nil flow[:self_sufficiency_pct]
    assert_nil flow[:self_consumption_pct]
    assert_nil flow[:solar_net_w]
    assert_nil flow[:recorded_at]
  end

  test "last_7_days totals split signed grid flow into import and export" do
    insert_telemetry([
      { offset: 0.hours, power_kw: 0.0, grid_flow_kw:  2.0 },
      { offset: 1.hour,  power_kw: 0.0, grid_flow_kw:  4.0 },
      { offset: 2.hours, power_kw: 0.0, grid_flow_kw: -3.0 },
      { offset: 3.hours, power_kw: 0.0, grid_flow_kw: -3.0 }
    ])

    week = SiteDiagnostics.new(@site, now: @reference + 4.hours).to_h[:last_7_days]

    assert_in_delta 5.0, week[:export_kwh], 0.01
    assert_in_delta 4.5, week[:import_kwh], 0.01
  end

  test "import_export_series is restricted to the trailing 12 hours" do
    insert_telemetry([
      { offset: -20.hours, power_kw: 1.0, grid_flow_kw: 1.0 },
      { offset: -2.hours,  power_kw: 2.0, grid_flow_kw: -1.5 },
      { offset: -1.hour,   power_kw: 3.0, grid_flow_kw: 2.5 }
    ])

    series = SiteDiagnostics.new(@site, now: @reference).to_h[:import_export_series]

    assert_equal 2, series.length, "should drop the 20h-old reading"
    assert_equal [ -1.5, 2.5 ], series.map { |p| p[:kw] }
    assert series.all? { |p| p[:t].is_a?(String) }
  end

  test "solar_7d_series always returns 7 buckets, zero-filled when missing" do
    insert_telemetry([
      { offset: -6.hours, power_kw: 4.0, grid_flow_kw: 0.0 },
      { offset: -5.hours, power_kw: 4.0, grid_flow_kw: 0.0 }
    ])

    series = SiteDiagnostics.new(@site, now: @reference).to_h[:solar_7d_series]

    assert_equal 7, series.length
    assert series.map { |p| p[:d] }.uniq.length == 7,
           "expected 7 distinct calendar days"
    today_bucket = series.last
    assert_in_delta 4.0, today_bucket[:kwh], 0.01
    earlier = series[0..-2]
    assert earlier.all? { |p| p[:kwh] == 0.0 }, "missing days should read zero kWh"
  end

  test "integration ignores gaps larger than the cap" do
    insert_telemetry([
      { offset: 0.hours,  power_kw: 5.0, grid_flow_kw: 0.0 },
      { offset: 4.hours,  power_kw: 5.0, grid_flow_kw: 0.0 }
    ])

    today = SiteDiagnostics.new(@site, now: @reference + 5.hours).to_h[:today]

    assert_equal 0.0, today[:self_consumption_kwh],
                 "a 4h gap exceeds the 1h cap so the trapezoid contribution is dropped"
  end

  test "latest section exposes the most recent inverter snapshot for the diagnostics rail" do
    insert_telemetry([
      {
        offset:          -10.minutes,
        power_kw:        4.21,
        grid_flow_kw:    1.5,
        inverter_temp_c: 41,
        dc_power_kw:     4.42,
        dc_amps:         11.05,
        ac_amps:         17.6,
        string_voltage:  400,
        ac_voltage:      240,
        inverter_status: "online",
        alarm_state:     "warn"
      }
    ])

    latest = SiteDiagnostics.new(@site, now: @reference).to_h[:latest]

    assert_equal 4.21,      latest[:ac_power_kw]
    assert_equal 4.42,      latest[:dc_power_kw]
    assert_equal 17.6,      latest[:ac_amps]
    assert_equal 11.05,     latest[:dc_amps]
    assert_equal 240,       latest[:ac_voltage]
    assert_equal 400,       latest[:dc_voltage]
    assert_equal "online",  latest[:inverter_status]
    assert_equal "warn",    latest[:alarm_state]
    assert_equal((@reference - 10.minutes).to_i, latest[:recorded_at].to_i)
  end

  test "latest section returns nil values when there is no telemetry at all" do
    latest = SiteDiagnostics.new(@site, now: @reference).to_h[:latest]

    assert_nil latest[:ac_power_kw]
    assert_nil latest[:dc_power_kw]
    assert_nil latest[:ac_amps]
    assert_nil latest[:dc_amps]
    assert_nil latest[:ac_voltage]
    assert_nil latest[:dc_voltage]
    assert_nil latest[:alarm_state]
    assert_nil latest[:inverter_status]
    assert_nil latest[:recorded_at]
  end

  test "import_export_series carries ac_v only when the underlying telemetry has ac_voltage" do
    insert_telemetry([
      { offset: -1.hour,    power_kw: 3.0, grid_flow_kw: 1.0, ac_voltage: 240 },
      { offset: -30.minutes, power_kw: 3.5, grid_flow_kw: 1.5 }
    ])

    series = SiteDiagnostics.new(@site, now: @reference).to_h[:import_export_series]

    assert_equal 2, series.length
    assert_equal 240.0, series.first[:ac_v], "first point should expose AC mains voltage"
    assert_nil series.last[:ac_v], "second point has no ac_voltage in telemetry, must omit ac_v as nil"
  end

  test "no telemetry returns zeroed tiles and seven empty buckets" do
    payload = SiteDiagnostics.new(@site, now: @reference).to_h

    assert_equal 0.0, payload[:today][:self_consumption_kwh]
    assert_equal 0.0, payload[:today][:grid_consumption_kwh]
    assert_equal 0.0, payload[:today][:consumed_kwh]
    assert_nil payload[:today][:inverter_temp_c]
    assert_nil payload[:today][:inverter_temp_f]
    assert_equal 0.0, payload[:last_7_days][:export_kwh]
    assert_equal 0.0, payload[:last_7_days][:import_kwh]
    assert_equal 0.0, payload[:today_pie][:exported_kwh]
    assert_equal 0.0, payload[:today_pie][:self_consumption_kwh]
    assert_empty payload[:import_export_series]
    assert_equal 7, payload[:solar_7d_series].length
    assert payload[:solar_7d_series].all? { |b| b[:kwh] == 0.0 }
  end

  private

  def insert_telemetry(rows)
    rows.each do |r|
      Telemetry.create!(
        site:            @site,
        organization:    @site.organization,
        recorded_at:     @reference + r[:offset],
        metric_payload: {
          "power_kw"        => r[:power_kw],
          "grid_flow_kw"    => r[:grid_flow_kw],
          "inverter_temp_c" => r[:inverter_temp_c],
          "dc_power_kw"     => r[:dc_power_kw],
          "dc_amps"         => r[:dc_amps],
          "ac_amps"         => r[:ac_amps],
          "ac_voltage"      => r[:ac_voltage],
          "string_voltage"  => r[:string_voltage],
          "inverter_status" => r[:inverter_status]
        }.compact,
        alarm_state: r[:alarm_state] || "normal"
      )
    end
  end
end
