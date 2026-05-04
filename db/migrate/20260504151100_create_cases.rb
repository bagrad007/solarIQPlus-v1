class CreateCases < ActiveRecord::Migration[8.1]
  # Support tickets on Sites. Status state machine enforced in DB:
  # open/in_progress/resolved are freely interchangeable; closed is terminal.
  # Escalation is one-way set: only a Maverick session may flip
  # escalated_to_maverick from true back to false (INTEGRITY trigger reads
  # app.is_maverick(); it does not decide visibility — that's RLS).

  def up
    execute <<~SQL
      CREATE TYPE case_status AS ENUM ('open', 'in_progress', 'resolved', 'closed');

      CREATE TABLE cases (
        id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        site_id                  uuid NOT NULL REFERENCES sites(id) ON DELETE RESTRICT,
        organization_id          uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
        org_path                 ltree NOT NULL,
        opened_by_user_id        uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        subject                  text NOT NULL,
        notes                    text NOT NULL DEFAULT '',
        status                   case_status NOT NULL DEFAULT 'open',
        escalated_to_maverick    boolean NOT NULL DEFAULT false,
        escalated_at             timestamptz,
        closed_at                timestamptz,
        created_at               timestamptz NOT NULL DEFAULT now(),
        updated_at               timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT cases_subject_not_blank CHECK (length(btrim(subject)) > 0),
        CONSTRAINT cases_escalated_at_set_when_escalated CHECK (
          (escalated_to_maverick AND escalated_at IS NOT NULL) OR
          (NOT escalated_to_maverick)
        )
      );

      CREATE TRIGGER trg_cases_populate_org_path
        BEFORE INSERT OR UPDATE OF organization_id ON cases
        FOR EACH ROW
        EXECUTE FUNCTION app.populate_tenant_org_path();

      -- Status state machine: closed is terminal.
      CREATE OR REPLACE FUNCTION app.enforce_case_status_machine() RETURNS trigger AS $f$
      BEGIN
        IF OLD.status = 'closed' AND NEW.status <> OLD.status THEN
          RAISE EXCEPTION 'cases.status is final once closed';
        END IF;

        IF NEW.status = 'closed' AND NEW.closed_at IS NULL THEN
          NEW.closed_at := now();
        END IF;
        IF NEW.status <> 'closed' AND NEW.closed_at IS NOT NULL THEN
          NEW.closed_at := NULL;
        END IF;

        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_cases_status_machine
        BEFORE UPDATE OF status ON cases
        FOR EACH ROW
        EXECUTE FUNCTION app.enforce_case_status_machine();

      -- Escalation lifecycle: setting true stamps escalated_at; reversal requires Maverick.
      -- This reads app.is_maverick() because it's a domain rule about WHO can de-escalate;
      -- it does NOT decide row visibility, so it's an INTEGRITY trigger (Taxonomy A), not authz.
      CREATE OR REPLACE FUNCTION app.enforce_case_escalation_lifecycle() RETURNS trigger AS $f$
      BEGIN
        IF TG_OP = 'INSERT' THEN
          IF NEW.escalated_to_maverick AND NEW.escalated_at IS NULL THEN
            NEW.escalated_at := now();
          END IF;
          RETURN NEW;
        END IF;

        IF NEW.escalated_to_maverick AND NOT OLD.escalated_to_maverick THEN
          NEW.escalated_at := COALESCE(NEW.escalated_at, now());
        END IF;

        IF OLD.escalated_to_maverick AND NOT NEW.escalated_to_maverick THEN
          IF NOT app.is_maverick() THEN
            RAISE EXCEPTION 'only a Maverick session may de-escalate a case';
          END IF;
        END IF;

        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_cases_escalation_lifecycle
        BEFORE INSERT OR UPDATE OF escalated_to_maverick ON cases
        FOR EACH ROW
        EXECUTE FUNCTION app.enforce_case_escalation_lifecycle();

      -- Notes are append-only. New notes value must start with the prior value.
      CREATE OR REPLACE FUNCTION app.enforce_case_notes_append_only() RETURNS trigger AS $f$
      BEGIN
        IF NEW.notes IS NULL THEN NEW.notes := ''; END IF;
        IF OLD.notes IS NOT NULL AND length(OLD.notes) > 0 AND
           substring(NEW.notes FROM 1 FOR length(OLD.notes)) <> OLD.notes THEN
          RAISE EXCEPTION 'cases.notes is append-only';
        END IF;
        RETURN NEW;
      END
      $f$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_cases_notes_append_only
        BEFORE UPDATE OF notes ON cases
        FOR EACH ROW
        EXECUTE FUNCTION app.enforce_case_notes_append_only();

      CREATE TRIGGER trg_cases_touch_updated_at
        BEFORE UPDATE ON cases
        FOR EACH ROW
        EXECUTE FUNCTION app.touch_updated_at();
    SQL
  end

  def down
    execute <<~SQL
      DROP TABLE IF EXISTS cases CASCADE;
      DROP FUNCTION IF EXISTS app.enforce_case_notes_append_only();
      DROP FUNCTION IF EXISTS app.enforce_case_escalation_lifecycle();
      DROP FUNCTION IF EXISTS app.enforce_case_status_machine();
      DROP TYPE IF EXISTS case_status;
    SQL
  end
end
