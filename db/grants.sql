-- Privileges that pg_dump -x strips from db/structure.sql.
--
-- Migration #2 (create_app_schema_and_role) is the source of truth for these
-- grants at migration time, but every subsequent db:schema:load (including
-- db:reset and db:test:prepare) loads from the privilege-less structure dump
-- and would otherwise leave app_user with no access to the schema/functions
-- it needs.
--
-- Loaded by:
--   - lib/tasks/grants.rake (after db:schema:load)
--   - test/test_helper.rb   (once per test process)
--
-- Idempotent: every statement is a GRANT, safe to re-run any number of times.

GRANT app_user TO CURRENT_USER;

GRANT USAGE ON SCHEMA app    TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO app_user;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO app_user;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA public TO app_user;
