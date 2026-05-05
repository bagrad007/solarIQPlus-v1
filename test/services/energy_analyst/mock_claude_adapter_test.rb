require "test_helper"

class EnergyAnalyst::MockClaudeAdapterTest < ActiveSupport::TestCase
  # Tiny in-memory fixture — exercises every branch of the keyword router
  # without needing the 1.3 MB committed file. Keeps the test independent
  # of the dataset's exact numerical values.
  def self.build_reading(date, pr:, faults:, status: "online")
    {
      date: date, timestamp: "#{date}T12:00:00Z",
      voltage: 38.0, current: 24.0, power_output: 0.9,
      temperature: 38.0, irradiance: 5.0, efficiency: pr,
      inverter_status: status, fault_codes: faults, maintenance_events: [],
      weather_conditions: { code: "clear", label: "Clear", factor: 1.0 },
      daily_energy_kwh: 100.0 * pr, expected_energy_kwh: 100.0,
      performance_ratio: pr, anomaly_score: (1.0 - pr).round(3)
    }
  end

  FIXTURE = {
    company_id: "company_a",
    company_name: "Company A — Industrial Solar",
    region: "Test Region",
    fleet_capacity_kw: 100,
    reference_date: "2026-05-01",
    sites: [
      {
        id: "site_alpha",
        name: "Site Alpha",
        location: "Test, AZ",
        capacity_kw: 50,
        commissioned_on: "2024-01-01",
        arrays: [
          {
            id: "array_a",
            name: "Array A",
            inverter_id: "INV-1",
            azimuth_deg: 180,
            tilt_deg: 25,
            panels: [
              {
                id: "p1",
                label: "A1",
                nameplate_kw: 5,
                daily_readings: [
                  build_reading("2026-04-25", pr: 0.95, faults: []),
                  build_reading("2026-04-26", pr: 0.40, faults: [ "INVERTER_OFFLINE" ], status: "offline"),
                  build_reading("2026-04-27", pr: 0.70, faults: [ "THERMAL_HOTSPOT" ]),
                  build_reading("2026-04-28", pr: 0.93, faults: []),
                  build_reading("2026-04-29", pr: 0.91, faults: []),
                  build_reading("2026-04-30", pr: 0.89, faults: []),
                  build_reading("2026-05-01", pr: 0.96, faults: [])
                ]
              }
            ]
          }
        ]
      }
    ],
    events: [
      { id: "evt_1", site_id: "site_alpha", kind: "outage", started_on: "2026-04-26",
        ended_on: "2026-04-27", severity: "critical", inverter_id: "INV-1",
        description: "Inverter offline." }
    ]
  }

  setup do
    EnergyAnalyst::TelemetryRepository.install(FIXTURE)
    @insights = EnergyAnalyst::TelemetryInsights.new
    @adapter = EnergyAnalyst::MockClaudeAdapter.new
  end

  teardown { EnergyAnalyst::TelemetryRepository.reset! }

  test "efficiency keyword routes to efficiency intent with line chart" do
    turn = @adapter.complete(user_message: "How efficient was my system last month?", insights: @insights)
    assert_equal :efficiency, turn.intent
    assert_match(/performance ratio/i, turn.reply_text)
    assert_equal "line", turn.visualizations.first[:kind]
  end

  test "fault keyword routes to faults intent with bar chart" do
    turn = @adapter.complete(user_message: "Show me the fault trends", insights: @insights)
    assert_equal :faults, turn.intent
    assert_equal "bar", turn.visualizations.first[:kind]
  end

  test "maintenance keyword returns recommendations text and no chart" do
    turn = @adapter.complete(user_message: "What maintenance should I do?", insights: @insights)
    assert_equal :maintenance, turn.intent
    assert_match(/inverter/i, turn.reply_text)
    assert_empty turn.visualizations
  end

  test "anomaly keyword surfaces dataset events" do
    turn = @adapter.complete(user_message: "Show me anomalies in the last 7 days", insights: @insights)
    assert_equal :anomalies, turn.intent
    assert_match(/inverter offline/i, turn.reply_text.downcase)
  end

  test "underperform keyword routes to underperforming panels" do
    turn = @adapter.complete(user_message: "Which panels are underperforming?", insights: @insights)
    assert_equal :underperform, turn.intent
  end

  test "weather keyword returns dual-series production chart" do
    turn = @adapter.complete(user_message: "Was the weather hurting irradiance?", insights: @insights)
    assert_equal :weather, turn.intent
    assert_equal "dual", turn.visualizations.first[:kind]
  end

  test "production keyword returns dual chart" do
    turn = @adapter.complete(user_message: "How much energy did we produce?", insights: @insights)
    assert_equal :production, turn.intent
    assert_equal "dual", turn.visualizations.first[:kind]
  end

  test "unknown question falls back to overview intent" do
    turn = @adapter.complete(user_message: "Tell me a joke about photons", insights: @insights)
    assert_equal :overview, turn.intent
    assert_match(/Company A/, turn.reply_text)
  end

  test "numeric window phrase narrows the time range" do
    turn = @adapter.complete(user_message: "Show efficiency for the last 7 days", insights: @insights)
    assert_match(/last 7 days/, turn.reply_text)
  end

  test "ChatTurn#to_h is JSON-friendly" do
    turn = @adapter.complete(user_message: "overview", insights: @insights)
    json = JSON.generate(turn.to_h)
    parsed = JSON.parse(json)
    assert_kind_of String, parsed["reply_text"]
    assert_kind_of Array,  parsed["visualizations"]
  end
end
