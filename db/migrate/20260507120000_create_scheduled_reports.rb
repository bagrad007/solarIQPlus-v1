# frozen_string_literal: true

class CreateScheduledReports < ActiveRecord::Migration[8.1]
  # Tenant-scoped scheduled report definitions (demo). Mirrors alarms' pattern:
  # organization_id + denormalized org_path + populate_tenant_org_path trigger,
  # then FORCE RLS + uniform tenant_visibility for app_user.

  def up
    execute <<~SQL
      CREATE TABLE scheduled_reports (
        id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
        org_path         ltree NOT NULL,
        name             text NOT NULL,
        recipients       text[] NOT NULL DEFAULT '{}',
        ai_prompt        text NOT NULL DEFAULT '',
        frequency        text NOT NULL DEFAULT 'daily',
        hour             integer NOT NULL DEFAULT 8,
        time_zone        text NOT NULL DEFAULT 'UTC',
        next_run_at      timestamptz,
        enabled          boolean NOT NULL DEFAULT true,
        created_at       timestamptz NOT NULL DEFAULT now(),
        updated_at       timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT scheduled_reports_name_not_blank CHECK (length(btrim(name)) > 0),
        CONSTRAINT scheduled_reports_frequency_valid CHECK (frequency IN ('daily', 'weekly', 'monthly')),
        CONSTRAINT scheduled_reports_hour_range CHECK (hour >= 0 AND hour <= 23)
      );

      CREATE TRIGGER trg_scheduled_reports_populate_org_path
        BEFORE INSERT OR UPDATE OF organization_id ON scheduled_reports
        FOR EACH ROW
        EXECUTE FUNCTION app.populate_tenant_org_path();

      CREATE TRIGGER trg_scheduled_reports_touch_updated_at
        BEFORE UPDATE ON scheduled_reports
        FOR EACH ROW
        EXECUTE FUNCTION app.touch_updated_at();

      ALTER TABLE scheduled_reports ENABLE ROW LEVEL SECURITY;
      ALTER TABLE scheduled_reports FORCE ROW LEVEL SECURITY;

      CREATE POLICY tenant_visibility ON scheduled_reports
        AS PERMISSIVE
        FOR ALL
        TO app_user
        USING      (app.can_see(org_path))
        WITH CHECK (app.can_see(org_path));

      GRANT SELECT, INSERT, UPDATE, DELETE ON scheduled_reports TO app_user;

      CREATE INDEX index_scheduled_reports_on_org_path ON scheduled_reports USING gist (org_path);
      CREATE INDEX index_scheduled_reports_on_organization_id ON scheduled_reports (organization_id);
      CREATE INDEX index_scheduled_reports_on_next_run_at ON scheduled_reports (next_run_at)
        WHERE enabled = true AND next_run_at IS NOT NULL;
    SQL
  end

  def down
    execute <<~SQL
      DROP TABLE IF EXISTS scheduled_reports CASCADE;
    SQL
  end
end
