class CreateIndexes < ActiveRecord::Migration[8.1]
  # GiST indexes on every ltree column so RLS predicates (target_path <@ effective_path)
  # are O(log n). Btree indexes on common foreign keys, sort keys, and filter columns.
  # The (site_id, recorded_at DESC) composite supports the per-site time-series read pattern.

  def up
    add_index :organizations, :path,      using: :gist
    add_index :organizations, :parent_id
    add_index :organizations, :org_type

    add_index :users, :org_path,        using: :gist
    add_index :users, :organization_id
    add_index :users, :role

    add_index :sites, :org_path,        using: :gist
    add_index :sites, :organization_id

    add_index :telemetry, :org_path,    using: :gist
    add_index :telemetry, :organization_id
    add_index :telemetry, [:site_id, :recorded_at], order: { recorded_at: :desc }
    add_index :telemetry, :alarm_state

    add_index :cases, :org_path,        using: :gist
    add_index :cases, :organization_id
    add_index :cases, :site_id
    add_index :cases, :status
    add_index :cases, :escalated_to_maverick,
              where: "escalated_to_maverick = true",
              name:  "index_cases_on_escalated_to_maverick_open"

    add_index :audit_logs, :org_path,   using: :gist
    add_index :audit_logs, :organization_id
    add_index :audit_logs, :actor_user_id
    add_index :audit_logs, [:auditable_type, :auditable_id]
    add_index :audit_logs, :created_at, order: { created_at: :desc }
  end

  def down
    remove_index :audit_logs, [:auditable_type, :auditable_id]
    remove_index :audit_logs, :created_at
    remove_index :audit_logs, :actor_user_id
    remove_index :audit_logs, :organization_id
    remove_index :audit_logs, :org_path

    remove_index :cases, name: "index_cases_on_escalated_to_maverick_open"
    remove_index :cases, :status
    remove_index :cases, :site_id
    remove_index :cases, :organization_id
    remove_index :cases, :org_path

    remove_index :telemetry, :alarm_state
    remove_index :telemetry, [:site_id, :recorded_at]
    remove_index :telemetry, :organization_id
    remove_index :telemetry, :org_path

    remove_index :sites, :organization_id
    remove_index :sites, :org_path

    remove_index :users, :role
    remove_index :users, :organization_id
    remove_index :users, :org_path

    remove_index :organizations, :org_type
    remove_index :organizations, :parent_id
    remove_index :organizations, :path
  end
end
