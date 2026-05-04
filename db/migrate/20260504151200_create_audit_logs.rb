class CreateAuditLogs < ActiveRecord::Migration[8.1]
  # Insert-only audit trail of changes to audit-bearing fields on tenant rows.
  # Plan A audits Site config (gateway_ip, device_credentials_encrypted,
  # polling_interval_seconds). Updates and deletes are forbidden by trigger.

  def up
    execute <<~SQL
      CREATE TABLE audit_logs (
        id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
        org_path        ltree NOT NULL,
        actor_user_id   uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        auditable_type  text NOT NULL,
        auditable_id    uuid NOT NULL,
        field_name      text NOT NULL,
        old_value       text,
        new_value       text,
        created_at      timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT audit_logs_auditable_type_not_blank CHECK (length(btrim(auditable_type)) > 0),
        CONSTRAINT audit_logs_field_name_not_blank     CHECK (length(btrim(field_name)) > 0)
      );

      CREATE TRIGGER trg_audit_logs_populate_org_path
        BEFORE INSERT ON audit_logs
        FOR EACH ROW
        EXECUTE FUNCTION app.populate_tenant_org_path();

      CREATE OR REPLACE FUNCTION app.enforce_audit_logs_insert_only() RETURNS trigger AS $f$
      BEGIN
        RAISE EXCEPTION 'audit_logs is insert-only (% denied)', TG_OP;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_audit_logs_no_update
        BEFORE UPDATE ON audit_logs
        FOR EACH ROW
        EXECUTE FUNCTION app.enforce_audit_logs_insert_only();

      CREATE TRIGGER trg_audit_logs_no_delete
        BEFORE DELETE ON audit_logs
        FOR EACH ROW
        EXECUTE FUNCTION app.enforce_audit_logs_insert_only();
    SQL
  end

  def down
    execute <<~SQL
      DROP TABLE IF EXISTS audit_logs CASCADE;
      DROP FUNCTION IF EXISTS app.enforce_audit_logs_insert_only();
    SQL
  end
end
