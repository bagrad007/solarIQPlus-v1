require "test_helper"

class OrgPathInvariantsTest < ActiveSupport::TestCase
  # Architectural Invariant 2: org_path and organization_id are NOT NULL
  # at the column level. Bad writes fail loudly, never silently weaken RLS.

  setup { build_tenant_tree }

  test "Site insert without organization_id fails (trigger or NOT NULL)" do
    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO sites (id, name, polling_interval_seconds)
        VALUES (gen_random_uuid(), 'orphan', 30)
      SQL
    end
  end

  test "Customer org cannot be created without parent_id (DB CHECK fires when validation skipped)" do
    customer = Organization.new(org_type: "customer", name: "Floating customer")
    assert_raises(ActiveRecord::StatementInvalid) do
      customer.save(validate: false)
    end
  end

  test "Path is immutable on organizations" do
    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.connection.execute(<<~SQL)
        UPDATE organizations SET path = 'foo'::ltree WHERE id = '#{@northwind.id}'
      SQL
    end
  end

  test "Hierarchy depth is enforced at the DB layer (Customer must have a Partner parent)" do
    customer = Organization.new(org_type: "customer", name: "Deep customer", parent: @maverick)
    error = assert_raises(ActiveRecord::StatementInvalid) do
      customer.save(validate: false)
    end
    assert_match(/customer must be a direct child of a partner/, error.message)
  end
end
