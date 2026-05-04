class CreateUsers < ActiveRecord::Migration[8.1]
  # Devise 5.0.3 database_authenticatable + recoverable + rememberable.
  # citext email so case-insensitive uniqueness is enforced at the DB level.
  # role enum is bound to the parent organization's org_type by an INTEGRITY trigger.

  def up
    execute <<~SQL
      CREATE TYPE user_role AS ENUM ('maverick_admin', 'partner_user', 'customer_user');

      CREATE TABLE users (
        id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        organization_id        uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
        org_path               ltree NOT NULL,
        role                   user_role NOT NULL,
        email                  citext NOT NULL,
        encrypted_password     text NOT NULL DEFAULT '',
        reset_password_token   text,
        reset_password_sent_at timestamptz,
        remember_created_at    timestamptz,
        name                   text,
        created_at             timestamptz NOT NULL DEFAULT now(),
        updated_at             timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT users_email_unique UNIQUE (email),
        CONSTRAINT users_reset_password_token_unique UNIQUE (reset_password_token)
      );

      -- Reusable trigger function: every tenant-bearing table denormalizes
      -- organizations.path into its own org_path column. The function is shared
      -- across users / sites / telemetry / cases / audit_logs.
      CREATE OR REPLACE FUNCTION app.populate_tenant_org_path() RETURNS trigger AS $f$
      DECLARE
        ref_path ltree;
      BEGIN
        IF NEW.organization_id IS NULL THEN
          RAISE EXCEPTION '%.organization_id cannot be null', TG_TABLE_NAME;
        END IF;
        SELECT path INTO ref_path FROM organizations WHERE id = NEW.organization_id;
        IF ref_path IS NULL THEN
          RAISE EXCEPTION '%.organization_id % not found', TG_TABLE_NAME, NEW.organization_id;
        END IF;
        NEW.org_path := ref_path;
        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_users_populate_org_path
        BEFORE INSERT OR UPDATE OF organization_id ON users
        FOR EACH ROW
        EXECUTE FUNCTION app.populate_tenant_org_path();

      -- Role must match parent org's tier. INTEGRITY trigger (Trigger Taxonomy A);
      -- this is a domain rule, not authorization.
      CREATE OR REPLACE FUNCTION app.validate_user_role_matches_org_type() RETURNS trigger AS $f$
      DECLARE
        org_type_val organization_type;
      BEGIN
        SELECT o.org_type INTO org_type_val FROM organizations o WHERE o.id = NEW.organization_id;
        IF (NEW.role = 'maverick_admin' AND org_type_val <> 'maverick') OR
           (NEW.role = 'partner_user'   AND org_type_val <> 'partner')  OR
           (NEW.role = 'customer_user'  AND org_type_val <> 'customer') THEN
          RAISE EXCEPTION 'user role % does not match org_type %', NEW.role, org_type_val;
        END IF;
        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_users_validate_role_matches_org_type
        BEFORE INSERT OR UPDATE OF role, organization_id ON users
        FOR EACH ROW
        EXECUTE FUNCTION app.validate_user_role_matches_org_type();

      CREATE TRIGGER trg_users_touch_updated_at
        BEFORE UPDATE ON users
        FOR EACH ROW
        EXECUTE FUNCTION app.touch_updated_at();
    SQL
  end

  def down
    execute <<~SQL
      DROP TABLE IF EXISTS users CASCADE;
      DROP FUNCTION IF EXISTS app.validate_user_role_matches_org_type();
      DROP FUNCTION IF EXISTS app.populate_tenant_org_path();
      DROP TYPE IF EXISTS user_role;
    SQL
  end
end
