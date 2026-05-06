class CreateAlarmCodes < ActiveRecord::Migration[8.1]
  # Global lookup catalog for Alarm Codes (the "404"-style integer plus a
  # human label and a default Severity). No RLS — this is a system-wide
  # catalog read by every persona; rows arrive via seeds. The Alarm row
  # carries its own severity (denormalized at insert) so the catalog can
  # evolve without rewriting historical alarms.
  #
  # See docs/UBIQUITOUS-LANGUAGE.md → "Alarm Code".

  def up
    execute <<~SQL
      CREATE TYPE alarm_severity AS ENUM ('critical', 'warning', 'cleared');

      CREATE TABLE alarm_codes (
        id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        code              integer NOT NULL,
        label             text NOT NULL,
        default_severity  alarm_severity NOT NULL,
        description       text,
        created_at        timestamptz NOT NULL DEFAULT now(),
        updated_at        timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT alarm_codes_code_unique UNIQUE (code),
        CONSTRAINT alarm_codes_label_not_blank CHECK (length(btrim(label)) > 0),
        CONSTRAINT alarm_codes_code_positive CHECK (code > 0)
      );

      CREATE TRIGGER trg_alarm_codes_touch_updated_at
        BEFORE UPDATE ON alarm_codes
        FOR EACH ROW
        EXECUTE FUNCTION app.touch_updated_at();
    SQL
  end

  def down
    execute <<~SQL
      DROP TABLE IF EXISTS alarm_codes CASCADE;
      DROP TYPE IF EXISTS alarm_severity;
    SQL
  end
end
