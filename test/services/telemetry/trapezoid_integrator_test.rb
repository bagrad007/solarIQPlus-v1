require "test_helper"

class Telemetry::TrapezoidIntegratorTest < ActiveSupport::TestCase
  # Lightweight in-memory stand-in so we don't touch the DB. The integrator
  # only needs `recorded_at` and `metric_payload` — anything that responds to
  # those is a valid input shape.
  Sample = Struct.new(:recorded_at, :metric_payload, keyword_init: true)

  setup do
    @t0 = Time.utc(2026, 5, 5, 12, 0, 0)
  end

  test "empty input integrates to zero" do
    result = Telemetry::TrapezoidIntegrator.integrate([], max_gap: 1.hour) { |p| p["kw"].to_f }
    assert_equal 0.0, result
  end

  test "single sample integrates to zero (no interval to integrate over)" do
    rows = [ sample(@t0, kw: 5.0) ]
    result = Telemetry::TrapezoidIntegrator.integrate(rows, max_gap: 1.hour) { |p| p["kw"].to_f }
    assert_equal 0.0, result
  end

  test "two samples one hour apart at constant 4 kW yield 4 kWh" do
    rows = [
      sample(@t0, kw: 4.0),
      sample(@t0 + 1.hour, kw: 4.0)
    ]
    result = Telemetry::TrapezoidIntegrator.integrate(rows, max_gap: 1.hour) { |p| p["kw"].to_f }
    assert_in_delta 4.0, result, 0.0001
  end

  test "trapezoid rule averages a ramp from 0 to 4 kW over one hour to 2 kWh" do
    rows = [
      sample(@t0, kw: 0.0),
      sample(@t0 + 1.hour, kw: 4.0)
    ]
    result = Telemetry::TrapezoidIntegrator.integrate(rows, max_gap: 1.hour) { |p| p["kw"].to_f }
    assert_in_delta 2.0, result, 0.0001
  end

  test "intervals exceeding max_gap contribute zero (outage protection)" do
    rows = [
      sample(@t0,            kw: 5.0),
      sample(@t0 + 4.hours,  kw: 5.0)
    ]
    result = Telemetry::TrapezoidIntegrator.integrate(rows, max_gap: 1.hour) { |p| p["kw"].to_f }
    assert_equal 0.0, result, "a 4h gap exceeds the 1h cap — the segment must be dropped"
  end

  test "non-positive time deltas are skipped" do
    rows = [
      sample(@t0,            kw: 3.0),
      sample(@t0 - 1.hour,   kw: 3.0)
    ]
    result = Telemetry::TrapezoidIntegrator.integrate(rows, max_gap: 1.hour) { |p| p["kw"].to_f }
    assert_equal 0.0, result
  end

  test "block receives the metric_payload hash, not the row wrapper" do
    received = []
    rows = [
      sample(@t0,            kw: 1.0),
      sample(@t0 + 1.hour,   kw: 2.0)
    ]
    Telemetry::TrapezoidIntegrator.integrate(rows, max_gap: 1.hour) do |payload|
      received << payload
      payload["kw"].to_f
    end
    assert_equal [ { "kw" => 1.0 }, { "kw" => 2.0 } ], received
  end

  test "rows with nil metric_payload yield an empty hash to the block" do
    rows = [
      sample(@t0,            payload: nil),
      sample(@t0 + 1.hour,   kw: 3.0)
    ]
    result = Telemetry::TrapezoidIntegrator.integrate(rows, max_gap: 1.hour) { |p| (p["kw"] || 0).to_f }
    # First sample contributes 0 kw; second contributes 3 kw; trapezoid avg = 1.5; ×1h = 1.5 kWh
    assert_in_delta 1.5, result, 0.0001
  end

  test "multi-segment integration sums each interval independently" do
    rows = [
      sample(@t0,                   kw: 0.0),
      sample(@t0 + 1.hour,          kw: 4.0),
      sample(@t0 + 2.hours,         kw: 0.0)
    ]
    result = Telemetry::TrapezoidIntegrator.integrate(rows, max_gap: 1.hour) { |p| p["kw"].to_f }
    # Two trapezoids, each (0+4)/2 × 1h = 2 kWh. Total 4 kWh.
    assert_in_delta 4.0, result, 0.0001
  end

  private

  def sample(t, payload: :default, **payload_kwargs)
    payload_value =
      if payload == :default
        payload_kwargs.transform_keys(&:to_s)
      else
        payload
      end
    Sample.new(recorded_at: t, metric_payload: payload_value)
  end
end
