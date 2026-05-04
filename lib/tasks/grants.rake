# Re-applies the privileges from db/grants.sql after every db:schema:load.
#
# Why this exists: Rails dumps db/structure.sql with `pg_dump -x`, which
# strips ACLs. So loading the dump (db:reset, db:test:prepare, fresh checkouts)
# rebuilds the schema but leaves app_user with no access to the `app` schema
# or its functions, breaking every authenticated request.
#
# This is enhancement, not replacement: the GRANTs in migration #2 still run
# during normal `db:migrate`. This hook only matters for the schema-load path.
namespace :db do
  namespace :grants do
    desc "Re-apply privileges that pg_dump -x strips from structure.sql"
    task apply: :load_config do
      grants_path = Rails.root.join("db", "grants.sql")
      next unless grants_path.exist?

      ActiveRecord::Base.connection.execute(grants_path.read)
      puts "  ✔ db:grants:apply (#{grants_path.relative_path_from(Rails.root)})"
    end
  end
end

# Hook the load-from-dump paths so a fresh DB always lands with grants.
Rake::Task["db:schema:load"].enhance do
  Rake::Task["db:grants:apply"].invoke
end
