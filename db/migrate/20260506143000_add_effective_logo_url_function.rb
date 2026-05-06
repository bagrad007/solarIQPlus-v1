class AddEffectiveLogoUrlFunction < ActiveRecord::Migration[8.1]
  # Effective Logo (see docs/UBIQUITOUS-LANGUAGE.md): the logo URL the
  # sidebar / mobile top app bar render for the current request, walking
  # own → parent → ancestor → ... → root with a fallback at each step.
  #
  # The Ruby walk on Organization#effective_logo_url calls `parent.logo_url`,
  # which loads the parent org row through Active Record. Under RLS,
  # Customer-tier users cannot see their parent Partner's row (the
  # `tenant_visibility` policy uses `target_path <@ effective_org_path()`
  # — descendant-or-equal — so ancestors are invisible). The Ruby method
  # therefore returns nil for every Customer user, and the sidebar falls
  # back to the org-name text instead of rendering the inherited logo.
  #
  # Fix: a SECURITY DEFINER function that walks the ancestry by ltree path
  # and returns the closest non-empty `branding_config.logo_url`. Same
  # idiom used by `app.effective_org_path()` (see migration #20260504151600).
  # The function exposes only a tenant-public string (a logo URL) — not a
  # privilege expansion, just the precomputed Effective Logo value.

  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION app.effective_logo_url(target_org_id uuid) RETURNS text AS $f$
      DECLARE
        result text;
      BEGIN
        SELECT nullif(branding_config->>'logo_url', '')
        INTO result
        FROM organizations
        WHERE path @> (SELECT path FROM organizations WHERE id = target_org_id)
          AND nullif(branding_config->>'logo_url', '') IS NOT NULL
        ORDER BY nlevel(path) DESC
        LIMIT 1;

        RETURN result;
      END
      $f$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, app;
    SQL
  end

  def down
    execute "DROP FUNCTION IF EXISTS app.effective_logo_url(uuid);"
  end
end
