class RunCaseStatusMachineOnInsert < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DROP TRIGGER IF EXISTS trg_cases_status_machine ON cases;

      CREATE TRIGGER trg_cases_status_machine
        BEFORE INSERT OR UPDATE OF status ON cases
        FOR EACH ROW
        EXECUTE FUNCTION app.enforce_case_status_machine();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS trg_cases_status_machine ON cases;

      CREATE TRIGGER trg_cases_status_machine
        BEFORE UPDATE OF status ON cases
        FOR EACH ROW
        EXECUTE FUNCTION app.enforce_case_status_machine();
    SQL
  end
end
