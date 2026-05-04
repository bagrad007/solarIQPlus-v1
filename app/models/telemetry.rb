class Telemetry < ApplicationRecord
  # Append-only time-series. Composite primary key (id, recorded_at) because
  # PG requires the partition key be part of every uniqueness constraint.
  # AR 8.1 supports composite PKs natively.
  self.table_name = "telemetry"
  self.primary_key = [:id, :recorded_at]

  enum :alarm_state, { normal: "normal", warn: "warn", critical: "critical" }

  belongs_to :site
  belongs_to :organization
end
