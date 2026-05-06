class CreateAlarms < ActiveRecord::Migration[8.1]
  # Operational fault rows tied to a Site. Tenant-bearing (organization_id +
  # denormalized org_path) so RLS narrows visibility uniformly with every
  # other tenant table (Architectural Invariant 2).
  #
  # State machine (INTEGRITY trigger, Trigger Taxonomy A):
  #   firing ──▶ acknowledged ──▶ cleared
  #          ╰────────────────▶ cleared
  # No transition out of `cleared`. No reverse to `firing` from
  # `acknowledged` or `cleared`. Stamp metadata (acknowledged_*/cleared_*)
  # is auto-populated by the same trigger when the corresponding state
  # is entered without an explicit timestamp.
  #
  # Severity is one RGY dimension (critical/warning/cleared); the column
  # is denormalized from alarm_codes.default_severity at insert via trigger
  # so editorial overrides on individual alarms remain possible without
  # mutating the catalog row.
  #
  # See docs/UBIQUITOUS-LANGUAGE.md → "Alarm" / "Severity" / "Alarm Lifecycle".

  def up
    execute <<~SQL
      CREATE TYPE alarm_status AS ENUM ('firing', 'acknowledged', 'cleared');

      CREATE TABLE alarms (
        id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        organization_id          uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
        org_path                 ltree NOT NULL,
        site_id                  uuid NOT NULL REFERENCES sites(id) ON DELETE RESTRICT,
        code_id                  uuid NOT NULL REFERENCES alarm_codes(id) ON DELETE RESTRICT,
        severity                 alarm_severity NOT NULL,
        status                   alarm_status NOT NULL DEFAULT 'firing',
        title                    text NOT NULL,
        opened_at                timestamptz NOT NULL DEFAULT now(),
        acknowledged_by_user_id  uuid REFERENCES users(id) ON DELETE RESTRICT,
        acknowledged_at          timestamptz,
        cleared_by_user_id       uuid REFERENCES users(id) ON DELETE RESTRICT,
        cleared_at               timestamptz,
        created_at               timestamptz NOT NULL DEFAULT now(),
        updated_at               timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT alarms_title_not_blank CHECK (length(btrim(title)) > 0),
        CONSTRAINT alarms_acknowledged_pair CHECK (
          (acknowledged_at IS NULL     AND acknowledged_by_user_id IS NULL) OR
          (acknowledged_at IS NOT NULL AND acknowledged_by_user_id IS NOT NULL)
        ),
        CONSTRAINT alarms_cleared_pair CHECK (
          (cleared_at IS NULL     AND cleared_by_user_id IS NULL) OR
          (cleared_at IS NOT NULL AND cleared_by_user_id IS NOT NULL)
        ),
        CONSTRAINT alarms_acknowledged_set_when_acknowledged CHECK (
          status <> 'acknowledged' OR acknowledged_at IS NOT NULL
        ),
        CONSTRAINT alarms_cleared_set_when_cleared CHECK (
          status <> 'cleared' OR cleared_at IS NOT NULL
        ),
        CONSTRAINT alarms_firing_has_no_terminal_metadata CHECK (
          status <> 'firing' OR (acknowledged_at IS NULL AND cleared_at IS NULL)
        )
      );

      CREATE TRIGGER trg_alarms_populate_org_path
        BEFORE INSERT OR UPDATE OF organization_id ON alarms
        FOR EACH ROW
        EXECUTE FUNCTION app.populate_tenant_org_path();

      -- Site must belong to a Customer org. Reuses the validator from sites
      -- via a domain-specific wrapper that also confirms the Site's owning
      -- org matches alarms.organization_id (no cross-tenant fan-out).
      CREATE OR REPLACE FUNCTION app.validate_alarm_site_ownership() RETURNS trigger AS $f$
      DECLARE
        site_org uuid;
      BEGIN
        SELECT organization_id INTO site_org FROM sites WHERE id = NEW.site_id;
        IF site_org IS NULL THEN
          RAISE EXCEPTION 'alarms.site_id % not found', NEW.site_id;
        END IF;
        IF site_org <> NEW.organization_id THEN
          RAISE EXCEPTION 'alarms.organization_id % does not own site %', NEW.organization_id, NEW.site_id;
        END IF;
        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_alarms_validate_site_ownership
        BEFORE INSERT OR UPDATE OF site_id, organization_id ON alarms
        FOR EACH ROW
        EXECUTE FUNCTION app.validate_alarm_site_ownership();

      -- Severity defaults to alarm_codes.default_severity when not provided.
      -- title defaults to alarm_codes.label when not provided. Both are
      -- denormalized at insert so the index can sort/search without a join.
      CREATE OR REPLACE FUNCTION app.populate_alarm_defaults_from_code() RETURNS trigger AS $f$
      DECLARE
        code_row alarm_codes%ROWTYPE;
      BEGIN
        SELECT * INTO code_row FROM alarm_codes WHERE id = NEW.code_id;
        IF code_row.id IS NULL THEN
          RAISE EXCEPTION 'alarms.code_id % not found in alarm_codes', NEW.code_id;
        END IF;
        IF NEW.severity IS NULL THEN
          NEW.severity := code_row.default_severity;
        END IF;
        IF NEW.title IS NULL OR length(btrim(NEW.title)) = 0 THEN
          NEW.title := code_row.label;
        END IF;
        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_alarms_populate_defaults_from_code
        BEFORE INSERT ON alarms
        FOR EACH ROW
        EXECUTE FUNCTION app.populate_alarm_defaults_from_code();

      -- State machine: firing → acknowledged → cleared, plus firing → cleared.
      -- cleared is terminal. Stamp acknowledged_*/cleared_* automatically when
      -- the row enters those states without explicit timestamps.
      --
      -- INTEGRITY trigger (Trigger Taxonomy A): decides whether a proposed
      -- change to row state is legal. Does NOT decide row visibility — RLS
      -- (app.can_see) remains the only function that does.
      CREATE OR REPLACE FUNCTION app.enforce_alarm_state_machine() RETURNS trigger AS $f$
      BEGIN
        IF NEW.status = OLD.status THEN
          RETURN NEW;
        END IF;

        IF OLD.status = 'cleared' THEN
          RAISE EXCEPTION 'alarms.status is final once cleared';
        END IF;

        IF OLD.status = 'acknowledged' AND NEW.status = 'firing' THEN
          RAISE EXCEPTION 'alarms.status cannot move from acknowledged back to firing';
        END IF;

        -- firing → acknowledged: stamp ack metadata if the caller didn't.
        IF NEW.status = 'acknowledged' THEN
          IF NEW.acknowledged_at IS NULL THEN
            NEW.acknowledged_at := now();
          END IF;
          IF NEW.acknowledged_by_user_id IS NULL THEN
            NEW.acknowledged_by_user_id := app.current_user_id();
          END IF;
        END IF;

        -- → cleared: stamp clear metadata if the caller didn't.
        IF NEW.status = 'cleared' THEN
          IF NEW.cleared_at IS NULL THEN
            NEW.cleared_at := now();
          END IF;
          IF NEW.cleared_by_user_id IS NULL THEN
            NEW.cleared_by_user_id := app.current_user_id();
          END IF;
        END IF;

        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_alarms_state_machine
        BEFORE UPDATE OF status ON alarms
        FOR EACH ROW
        EXECUTE FUNCTION app.enforce_alarm_state_machine();

      CREATE TRIGGER trg_alarms_touch_updated_at
        BEFORE UPDATE ON alarms
        FOR EACH ROW
        EXECUTE FUNCTION app.touch_updated_at();

      -- RLS: same uniform policy shape as every other tenant table.
      -- Architectural Invariant 1: app.can_see is the single authorization
      -- function; alarms participates via its denormalized org_path.
      ALTER TABLE alarms ENABLE ROW LEVEL SECURITY;
      ALTER TABLE alarms FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_visibility ON alarms
        AS PERMISSIVE
        FOR ALL
        TO app_user
        USING      (app.can_see(org_path))
        WITH CHECK (app.can_see(org_path));

      GRANT SELECT, INSERT, UPDATE, DELETE ON alarms      TO app_user;
      GRANT SELECT                         ON alarm_codes TO app_user;

      CREATE INDEX index_alarms_on_org_path                    ON alarms USING gist (org_path);
      CREATE INDEX index_alarms_on_org_status_opened_at_desc   ON alarms (organization_id, status, opened_at DESC);
      CREATE INDEX index_alarms_on_site_opened_at_desc         ON alarms (site_id, opened_at DESC);
      CREATE INDEX index_alarms_on_code_id                     ON alarms (code_id);
      CREATE INDEX index_alarms_on_firing
        ON alarms (organization_id, opened_at DESC)
        WHERE status = 'firing';
    SQL
  end

  def down
    execute <<~SQL
      DROP TABLE IF EXISTS alarms CASCADE;
      DROP FUNCTION IF EXISTS app.enforce_alarm_state_machine();
      DROP FUNCTION IF EXISTS app.populate_alarm_defaults_from_code();
      DROP FUNCTION IF EXISTS app.validate_alarm_site_ownership();
      DROP TYPE IF EXISTS alarm_status;
    SQL
  end
end
