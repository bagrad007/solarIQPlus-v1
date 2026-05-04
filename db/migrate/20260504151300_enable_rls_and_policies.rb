class EnableRlsAndPolicies < ActiveRecord::Migration[8.1]
  # The single enforcement layer (Architectural Invariant 1).
  # ENABLE + FORCE on every tenant-bearing table; one uniform policy per
  # table that reduces every access decision to app.can_see(...).
  #
  # FORCE ROW LEVEL SECURITY makes RLS apply even to the table owner; this is
  # critical because Rails connects as a privileged user. Each request issues
  # SET LOCAL ROLE app_user to drop into the constrained role.

  TENANT_TABLES = {
    "organizations" => "path",
    "users"         => "org_path",
    "sites"         => "org_path",
    "telemetry"     => "org_path",
    "cases"         => "org_path",
    "audit_logs"    => "org_path"
  }.freeze

  def up
    TENANT_TABLES.each do |table, path_column|
      execute <<~SQL
        ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
        ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;

        CREATE POLICY tenant_visibility ON #{table}
          AS PERMISSIVE
          FOR ALL
          TO app_user
          USING      (app.can_see(#{path_column}))
          WITH CHECK (app.can_see(#{path_column}));

        GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO app_user;
      SQL
    end

    # Defense in depth for partitioned tables. PG14 doesn't propagate RLS from
    # parent partitioned table to its partitions for direct queries against the
    # partition. We enable+force+policy on every existing telemetry partition.
    # Future partitions (added by Plan B's roll-forward job) must do the same.
    partitions = ActiveRecord::Base.connection.select_values(<<~SQL)
      SELECT child.relname
      FROM pg_inherits
      JOIN pg_class child  ON child.oid  = pg_inherits.inhrelid
      JOIN pg_class parent ON parent.oid = pg_inherits.inhparent
      WHERE parent.relname = 'telemetry'
    SQL

    partitions.each do |partition|
      execute <<~SQL
        ALTER TABLE #{partition} ENABLE ROW LEVEL SECURITY;
        ALTER TABLE #{partition} FORCE ROW LEVEL SECURITY;

        CREATE POLICY tenant_visibility ON #{partition}
          AS PERMISSIVE
          FOR ALL
          TO app_user
          USING      (app.can_see(org_path))
          WITH CHECK (app.can_see(org_path));

        GRANT SELECT, INSERT, UPDATE, DELETE ON #{partition} TO app_user;
      SQL
    end
  end

  def down
    partitions = ActiveRecord::Base.connection.select_values(<<~SQL)
      SELECT child.relname
      FROM pg_inherits
      JOIN pg_class child  ON child.oid  = pg_inherits.inhrelid
      JOIN pg_class parent ON parent.oid = pg_inherits.inhparent
      WHERE parent.relname = 'telemetry'
    SQL
    partitions.each do |partition|
      execute <<~SQL
        REVOKE SELECT, INSERT, UPDATE, DELETE ON #{partition} FROM app_user;
        DROP POLICY IF EXISTS tenant_visibility ON #{partition};
        ALTER TABLE #{partition} NO FORCE ROW LEVEL SECURITY;
        ALTER TABLE #{partition} DISABLE ROW LEVEL SECURITY;
      SQL
    end

    TENANT_TABLES.each_key do |table|
      execute <<~SQL
        REVOKE SELECT, INSERT, UPDATE, DELETE ON #{table} FROM app_user;
        DROP POLICY IF EXISTS tenant_visibility ON #{table};
        ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY;
        ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY;
      SQL
    end
  end
end
