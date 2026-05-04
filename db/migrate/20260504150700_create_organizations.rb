class CreateOrganizations < ActiveRecord::Migration[8.1]
  # Three-tier hierarchy stored as a single self-referential table.
  # Domain language uses Maverick / Partner / Customer; the table name is
  # an implementation detail. See docs/UBIQUITOUS-LANGUAGE.md.
  #
  # `path` (ltree) is denormalized from the parent chain by an INTEGRITY trigger
  # (Trigger Taxonomy A). Subsequent updates to `path`, `parent_id`, and
  # `org_type` are forbidden — reparenting is a Phase-2 migration event.

  def up
    execute <<~SQL
      CREATE TYPE organization_type AS ENUM ('maverick', 'partner', 'customer');

      CREATE TABLE organizations (
        id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        parent_id       uuid REFERENCES organizations(id) ON DELETE RESTRICT,
        org_type        organization_type NOT NULL,
        name            text NOT NULL,
        branding_config jsonb NOT NULL DEFAULT '{}'::jsonb,
        path            ltree NOT NULL,
        created_at      timestamptz NOT NULL DEFAULT now(),
        updated_at      timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT organizations_name_not_blank CHECK (length(btrim(name)) > 0),
        CONSTRAINT organizations_maverick_has_no_parent CHECK (
          (org_type = 'maverick' AND parent_id IS NULL) OR
          (org_type <> 'maverick' AND parent_id IS NOT NULL)
        ),
        CONSTRAINT organizations_branding_config_is_object CHECK (
          jsonb_typeof(branding_config) = 'object'
        )
      );

      -- Reusable touch_updated_at; lives in app schema, used by every tenant table.
      CREATE OR REPLACE FUNCTION app.touch_updated_at() RETURNS trigger AS $f$
      BEGIN
        NEW.updated_at := now();
        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      -- Generate path from parent chain. ltree labels can only contain [A-Za-z0-9_],
      -- so we substitute UUID dashes for underscores. Also enforce hierarchy depth.
      CREATE OR REPLACE FUNCTION app.populate_organization_path() RETURNS trigger AS $f$
      DECLARE
        parent_path ltree;
        my_label    text := replace(NEW.id::text, '-', '_');
      BEGIN
        IF NEW.parent_id IS NULL THEN
          NEW.path := my_label::ltree;
        ELSE
          SELECT path INTO parent_path FROM organizations WHERE id = NEW.parent_id;
          IF parent_path IS NULL THEN
            RAISE EXCEPTION 'organization %: parent % not found', NEW.id, NEW.parent_id;
          END IF;
          NEW.path := parent_path || my_label::ltree;
        END IF;

        -- Hierarchy depth invariant: maverick=1, partner=2, customer=3.
        IF NEW.org_type = 'maverick' AND nlevel(NEW.path) <> 1 THEN
          RAISE EXCEPTION 'maverick must be the root (depth 1, got %)', nlevel(NEW.path);
        END IF;
        IF NEW.org_type = 'partner' AND nlevel(NEW.path) <> 2 THEN
          RAISE EXCEPTION 'partner must be a direct child of maverick (depth 2, got %)', nlevel(NEW.path);
        END IF;
        IF NEW.org_type = 'customer' AND nlevel(NEW.path) <> 3 THEN
          RAISE EXCEPTION 'customer must be a direct child of a partner (depth 3, got %)', nlevel(NEW.path);
        END IF;

        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_organizations_populate_path
        BEFORE INSERT ON organizations
        FOR EACH ROW
        EXECUTE FUNCTION app.populate_organization_path();

      -- path/parent_id/org_type are immutable. Treat reparenting as a migration
      -- event, not a feature toggle.
      CREATE OR REPLACE FUNCTION app.enforce_organization_immutable_columns() RETURNS trigger AS $f$
      BEGIN
        IF NEW.path IS DISTINCT FROM OLD.path THEN
          RAISE EXCEPTION 'organizations.path is immutable';
        END IF;
        IF NEW.parent_id IS DISTINCT FROM OLD.parent_id THEN
          RAISE EXCEPTION 'organizations.parent_id is immutable';
        END IF;
        IF NEW.org_type IS DISTINCT FROM OLD.org_type THEN
          RAISE EXCEPTION 'organizations.org_type is immutable';
        END IF;
        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_organizations_immutable_columns
        BEFORE UPDATE ON organizations
        FOR EACH ROW
        EXECUTE FUNCTION app.enforce_organization_immutable_columns();

      CREATE TRIGGER trg_organizations_touch_updated_at
        BEFORE UPDATE ON organizations
        FOR EACH ROW
        EXECUTE FUNCTION app.touch_updated_at();
    SQL
  end

  def down
    execute <<~SQL
      DROP TABLE IF EXISTS organizations CASCADE;
      DROP FUNCTION IF EXISTS app.enforce_organization_immutable_columns();
      DROP FUNCTION IF EXISTS app.populate_organization_path();
      DROP FUNCTION IF EXISTS app.touch_updated_at();
      DROP TYPE IF EXISTS organization_type;
    SQL
  end
end
