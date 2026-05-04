class CreateAppSchemaAndRole < ActiveRecord::Migration[8.1]
  # Tier 1: identity (pure GUC reads, no authz).
  # Tier 2: scope (composes identity into the Effective Tenant).
  # Tier 3: authorization (the single function that decides visibility).
  #
  # NOTE: app.effective_org_path() references the `organizations` table, which
  # does not exist yet at this point in the migration sequence. We use PL/pgSQL
  # so the body is parsed at first execution rather than at CREATE FUNCTION time.

  def up
    execute <<~SQL
      CREATE SCHEMA IF NOT EXISTS app;

      DO $do$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
          CREATE ROLE app_user NOLOGIN;
        END IF;
      END
      $do$;

      GRANT app_user TO CURRENT_USER;

      GRANT USAGE ON SCHEMA app    TO app_user;
      GRANT USAGE ON SCHEMA public TO app_user;

      ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public
        GRANT USAGE, SELECT ON SEQUENCES TO app_user;

      CREATE OR REPLACE FUNCTION app.current_user_id() RETURNS uuid AS $f$
        SELECT NULLIF(current_setting('app.user_id', true), '')::uuid
      $f$ LANGUAGE sql STABLE;

      CREATE OR REPLACE FUNCTION app.current_org_id() RETURNS uuid AS $f$
        SELECT NULLIF(current_setting('app.org_id', true), '')::uuid
      $f$ LANGUAGE sql STABLE;

      CREATE OR REPLACE FUNCTION app.is_maverick() RETURNS boolean AS $f$
        SELECT current_setting('app.is_maverick', true) = 'true'
      $f$ LANGUAGE sql STABLE;

      CREATE OR REPLACE FUNCTION app.in_view_as() RETURNS boolean AS $f$
        SELECT current_setting('app.mode', true) = 'view_as'
      $f$ LANGUAGE sql STABLE;

      CREATE OR REPLACE FUNCTION app.impersonated_org_id() RETURNS uuid AS $f$
        SELECT NULLIF(current_setting('app.impersonated_org_id', true), '')::uuid
      $f$ LANGUAGE sql STABLE;

      CREATE OR REPLACE FUNCTION app.effective_org_id() RETURNS uuid AS $f$
        SELECT COALESCE(app.impersonated_org_id(), app.current_org_id())
      $f$ LANGUAGE sql STABLE;

      CREATE OR REPLACE FUNCTION app.effective_org_path() RETURNS ltree AS $f$
      DECLARE
        result ltree;
      BEGIN
        SELECT path INTO result FROM organizations WHERE id = app.effective_org_id();
        RETURN result;
      END
      $f$ LANGUAGE plpgsql STABLE;

      CREATE OR REPLACE FUNCTION app.can_see(target_path ltree) RETURNS boolean AS $f$
        SELECT CASE
          WHEN target_path IS NULL THEN false
          WHEN app.is_maverick() AND NOT app.in_view_as() THEN true
          WHEN app.effective_org_path() IS NULL THEN false
          ELSE target_path <@ app.effective_org_path()
        END
      $f$ LANGUAGE sql STABLE;

      GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO app_user;
      ALTER DEFAULT PRIVILEGES IN SCHEMA app
        GRANT EXECUTE ON FUNCTIONS TO app_user;
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION IF EXISTS app.can_see(ltree);
      DROP FUNCTION IF EXISTS app.effective_org_path();
      DROP FUNCTION IF EXISTS app.effective_org_id();
      DROP FUNCTION IF EXISTS app.impersonated_org_id();
      DROP FUNCTION IF EXISTS app.in_view_as();
      DROP FUNCTION IF EXISTS app.is_maverick();
      DROP FUNCTION IF EXISTS app.current_org_id();
      DROP FUNCTION IF EXISTS app.current_user_id();

      ALTER DEFAULT PRIVILEGES IN SCHEMA public
        REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM app_user;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public
        REVOKE USAGE, SELECT ON SEQUENCES FROM app_user;

      REVOKE USAGE ON SCHEMA public FROM app_user;
      REVOKE USAGE ON SCHEMA app    FROM app_user;
      REVOKE app_user FROM CURRENT_USER;

      DROP SCHEMA IF EXISTS app;
      DROP ROLE IF EXISTS app_user;
    SQL
  end
end
