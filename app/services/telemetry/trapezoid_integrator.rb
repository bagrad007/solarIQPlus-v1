# frozen_string_literal: true

# Reopens the Telemetry AR class so the integrator can live in a Telemetry::
# namespace alongside the model. This is a true reopen (not a module) because
# Telemetry inherits from ApplicationRecord — Zeitwerk handles the load order.
class Telemetry < ApplicationRecord
  # Integrates a per-row kW value against `recorded_at` using the trapezoid
  # rule, returning kWh. Caps each interval at `max_gap`, so a missing-data
  # period reads as zero rather than extrapolating across an outage.
  #
  # Inputs only need to respond to `recorded_at` (any time-like) and
  # `metric_payload` (any hash-like or nil). The block is yielded each
  # consecutive row's payload and must return the kW value to integrate.
  #
  #   Telemetry::TrapezoidIntegrator.integrate(rows, max_gap: 1.hour) do |p|
  #     (p["power_kw"] || 0).to_f
  #   end
  #   # => 12.4 (kWh)
  module TrapezoidIntegrator
    module_function

    def integrate(rows, max_gap:)
      return 0.0 if rows.size < 2

      total = 0.0
      rows.each_cons(2) do |a, b|
        dt_seconds = b.recorded_at - a.recorded_at
        next if dt_seconds <= 0
        next if dt_seconds > max_gap

        v_a = yield(a.metric_payload || {})
        v_b = yield(b.metric_payload || {})
        total += ((v_a + v_b) / 2.0) * (dt_seconds / 3600.0)
      end
      total
    end
  end
end
