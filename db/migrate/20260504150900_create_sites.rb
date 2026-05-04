class CreateSites < ActiveRecord::Migration[8.1]
  # A Site is a physical solar installation. It belongs to a Customer
  # organization (enforced by INTEGRITY trigger).

  def up
    execute <<~SQL
      CREATE TABLE sites (
        id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        organization_id               uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
        org_path                      ltree NOT NULL,
        name                          text NOT NULL,
        gateway_ip                    inet,
        device_credentials_encrypted  text,
        polling_interval_seconds      integer NOT NULL DEFAULT 30,
        created_at                    timestamptz NOT NULL DEFAULT now(),
        updated_at                    timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT sites_name_not_blank CHECK (length(btrim(name)) > 0),
        CONSTRAINT sites_polling_interval_positive CHECK (polling_interval_seconds > 0)
      );

      CREATE OR REPLACE FUNCTION app.validate_site_parent_is_customer() RETURNS trigger AS $f$
      DECLARE
        org_type_val organization_type;
      BEGIN
        SELECT o.org_type INTO org_type_val FROM organizations o WHERE o.id = NEW.organization_id;
        IF org_type_val <> 'customer' THEN
          RAISE EXCEPTION 'sites.organization_id % is a %, must be a customer', NEW.organization_id, org_type_val;
        END IF;
        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_sites_populate_org_path
        BEFORE INSERT OR UPDATE OF organization_id ON sites
        FOR EACH ROW
        EXECUTE FUNCTION app.populate_tenant_org_path();

      CREATE TRIGGER trg_sites_validate_parent_is_customer
        BEFORE INSERT OR UPDATE OF organization_id ON sites
        FOR EACH ROW
        EXECUTE FUNCTION app.validate_site_parent_is_customer();

      CREATE TRIGGER trg_sites_touch_updated_at
        BEFORE UPDATE ON sites
        FOR EACH ROW
        EXECUTE FUNCTION app.touch_updated_at();
    SQL
  end

  def down
    execute <<~SQL
      DROP TABLE IF EXISTS sites CASCADE;
      DROP FUNCTION IF EXISTS app.validate_site_parent_is_customer();
    SQL
  end
end
