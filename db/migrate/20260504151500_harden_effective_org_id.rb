class HardenEffectiveOrgId < ActiveRecord::Migration[8.1]
  # Defense in depth (Architectural Invariant 3). The application controller
  # refuses to write impersonated_org_id for non-Maverick users; this SQL
  # change makes the safety property hold even if those guards are bypassed.
  #
  # Old: SELECT COALESCE(impersonated_org_id, current_org_id).
  # New: only honor impersonated_org_id when is_maverick AND in_view_as.

  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION app.effective_org_id() RETURNS uuid AS $f$
        SELECT CASE
          WHEN app.is_maverick()
               AND app.in_view_as()
               AND app.impersonated_org_id() IS NOT NULL
            THEN app.impersonated_org_id()
          ELSE app.current_org_id()
        END
      $f$ LANGUAGE sql STABLE;
    SQL
  end

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION app.effective_org_id() RETURNS uuid AS $f$
        SELECT COALESCE(app.impersonated_org_id(), app.current_org_id())
      $f$ LANGUAGE sql STABLE;
    SQL
  end
end
