require "test_helper"

class EnergyAnalyst::TelemetryInsightsTest < ActiveSupport::TestCase
  # Reuse the same fixture shape as the adapter test to keep coverage cheap.
  FIXTURE = EnergyAnalyst::MockClaudeAdapterTest::FIXTURE

  setup do
    EnergyAnalyst::TelemetryRepository.install(FIXTURE)
    @insights = EnergyAnalyst::TelemetryInsights.new
  end

  teardown { EnergyAnalyst::TelemetryRepository.reset! }

  test "company_overview returns headline numbers" do
    o = @insights.company_overview
    assert_equal "Company A — Industrial Solar", o[:company_name]
    assert_equal 1, o[:site_count]
    assert_kind_of Float, o[:performance_ratio]
    assert o[:expected_energy_kwh] > o[:actual_energy_kwh],
           "expected energy should exceed actual when at least one offline reading is present"
  end

  test "efficiency_trend returns one ordered point per date in window" do
    trend = @insights.efficiency_trend(days: 7)
    assert_equal 7, trend[:points].size
    assert_equal trend[:points].sort_by { |p| p[:date] }, trend[:points]
  end

  test "anomalies surfaces both narrative events and high-anomaly readings" do
    a = @insights.anomalies(days: 30)
    assert a[:events].any?, "expected at least the seeded outage event"
    assert_kind_of Integer, a[:flagged_reading_count]
  end

  test "underperforming_panels respects the PR threshold" do
    panels = @insights.underperforming_panels(days: 30)
    assert panels.all? { |p| p[:mean_performance_ratio] < EnergyAnalyst::TelemetryInsights::UNDERPERFORMING_PR_THRESHOLD },
           "all returned panels must be below the threshold"
  end

  test "fault_trend tallies fault codes" do
    trend = @insights.fault_trend(days: 30)
    assert trend[:total_faults] >= 1
    assert trend[:by_code].key?("INVERTER_OFFLINE") || trend[:by_code].key?("THERMAL_HOTSPOT")
  end

  test "daily_production_vs_expected returns ordered actual+expected points" do
    p = @insights.daily_production_vs_expected(days: 7)
    assert_equal 7, p[:points].size
    p[:points].each do |pt|
      assert_kind_of Numeric, pt[:actual_kwh]
      assert_kind_of Numeric, pt[:expected_kwh]
    end
  end
end
