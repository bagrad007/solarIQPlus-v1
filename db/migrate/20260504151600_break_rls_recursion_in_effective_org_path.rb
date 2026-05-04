class BreakRlsRecursionInEffectiveOrgPath < ActiveRecord::Migration[8.1]
  # The RLS policy on `organizations` reduces to `can_see(path)`, which calls
  # `effective_org_path()`, which `SELECTS path FROM organizations`, which
  # re-triggers RLS — infinite recursion.
  #
  # Fix: make effective_org_path SECURITY DEFINER and lock its search_path
  # down. The function runs as the migration owner (a superuser locally /
  # BYPASSRLS in production), which sees the bare table and breaks the loop.
  # This is integrity, not authorization: the function looks up a single
  # immutable column on a row already chosen by the caller's GUCs.

  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION app.effective_org_path() RETURNS ltree AS $f$
      DECLARE
        result ltree;
      BEGIN
        SELECT path INTO result FROM organizations WHERE id = app.effective_org_id();
        RETURN result;
      END
      $f$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, app;
    SQL
  end

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION app.effective_org_path() RETURNS ltree AS $f$
      DECLARE
        result ltree;
      BEGIN
        SELECT path INTO result FROM organizations WHERE id = app.effective_org_id();
        RETURN result;
      END
      $f$ LANGUAGE plpgsql STABLE;
    SQL
  end
end
