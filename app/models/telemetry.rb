class Telemetry < ApplicationRecord
  # Append-only time-series. Composite primary key (id, recorded_at) because
  # PG requires the partition key be part of every uniqueness constraint.
  # AR 8.1 supports composite PKs natively.
  #
  # Soft-schema for `metric_payload` (jsonb). New fields are introduced here
  # rather than via migrations so the ingestion contract can evolve without
  # touching telemetry partitioning. Consumers must treat missing keys as nil.
  #
  #   power_kw         Float  AC output of the inverter (kW). Always >= 0.
  #   capacity_factor  Float  power_kw / nameplate, clamped 0..1.
  #   string_voltage   Int    DC string voltage at the inverter input (V).
  #                            Surfaced in the UI as "Inverter DC Voltage".
  #   ambient_temp_c   Int    Outdoor air temperature near the array (°C).
  #   grid_flow_kw     Float  Signed flow at the grid meter (kW).
  #                            Positive = exporting to grid.
  #                            Negative = importing from grid.
  #   inverter_temp_c  Int    Internal inverter heatsink temperature (°C).
  #                            Distinct from ambient_temp_c — runs hotter.
  #   inverter_status  String "online" | "fault" | "offline".
  #   dc_power_kw      Float  DC side of the inverter (kW). Typically
  #                            ~1.05 × power_kw, accounting for inversion loss.
  #   dc_amps          Float  DC current at the inverter input (A) =
  #                            dc_power_kw × 1000 / string_voltage.
  #   ac_voltage       Int    AC mains voltage (V). Residential split-phase
  #                            ~240; commercial / industrial three-phase ~415.
  #   ac_amps          Float  AC output current (A) = power_kw × 1000 / ac_voltage.
  self.table_name = "telemetry"
  self.primary_key = [:id, :recorded_at]

  enum :alarm_state, { normal: "normal", warn: "warn", critical: "critical" }

  belongs_to :site
  belongs_to :organization
end
