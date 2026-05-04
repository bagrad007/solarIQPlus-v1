class CreateTelemetryPartitioned < ActiveRecord::Migration[8.1]
  # Append-only time-series of device readings. Partitioned monthly by
  # recorded_at; PG requires the partition key be part of every unique
  # constraint, so the PK is composite (id, recorded_at).
  #
  # ids use uuidv7() (PG18+) for time-locality on disk and in indexes.
  # Time ordering is still taken from recorded_at, never from id, because
  # uuidv7 only guarantees per-generator monotonicity (see UBIQUITOUS-LANGUAGE.md).

  def up
    execute <<~SQL
      CREATE TYPE alarm_state AS ENUM ('normal', 'warn', 'critical');

      CREATE TABLE telemetry (
        id              uuid NOT NULL DEFAULT uuidv7(),
        site_id         uuid NOT NULL REFERENCES sites(id) ON DELETE RESTRICT,
        organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
        org_path        ltree NOT NULL,
        recorded_at     timestamptz NOT NULL,
        metric_payload  jsonb NOT NULL,
        alarm_state     alarm_state NOT NULL DEFAULT 'normal',

        CONSTRAINT telemetry_metric_payload_is_object CHECK (jsonb_typeof(metric_payload) = 'object'),
        PRIMARY KEY (id, recorded_at)
      ) PARTITION BY RANGE (recorded_at);

      CREATE TRIGGER trg_telemetry_populate_org_path
        BEFORE INSERT OR UPDATE OF organization_id ON telemetry
        FOR EACH ROW
        EXECUTE FUNCTION app.populate_tenant_org_path();

      -- Past month (for seed history) + current + next 3 + default catch-all.
      -- Plan B will add a scheduled job that rolls these forward.
      CREATE TABLE telemetry_y2026m04 PARTITION OF telemetry
        FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
      CREATE TABLE telemetry_y2026m05 PARTITION OF telemetry
        FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
      CREATE TABLE telemetry_y2026m06 PARTITION OF telemetry
        FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
      CREATE TABLE telemetry_y2026m07 PARTITION OF telemetry
        FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
      CREATE TABLE telemetry_y2026m08 PARTITION OF telemetry
        FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
      CREATE TABLE telemetry_default PARTITION OF telemetry DEFAULT;
    SQL
  end

  def down
    execute <<~SQL
      DROP TABLE IF EXISTS telemetry CASCADE;
      DROP TYPE IF EXISTS alarm_state;
    SQL
  end
end
