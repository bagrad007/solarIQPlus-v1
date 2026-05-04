require "test_helper"

class CrossTenantTest < ActiveSupport::TestCase
  # Architectural Invariants 1 + 2: RLS is the only access control, and
  # org_path is always the predicate. A Customer must never see a sibling
  # Customer's data even if it shares a Partner.

  setup { build_tenant_tree }

  test "Customer sees only their own organization, sites, and cases" do
    Site.create!(organization: @fabrikam, name: "Fabrikam Array", polling_interval_seconds: 30)

    with_rls(user: @northwind_user) do
      assert_equal [@northwind.id], Organization.where(org_type: "customer").pluck(:id)
      assert_equal [@site_a.id],    Site.pluck(:id)
    end
  end

  test "Partner sees only their own Customers and not the sibling Partner's" do
    with_rls(user: @acme_user) do
      assert_equal %w[Acme Fabrikam Northwind].sort, Organization.pluck(:name).sort
      refute_includes Organization.pluck(:name), "Beta"
      refute_includes Organization.pluck(:name), "Contoso"
    end
  end

  test "Maverick sees the entire tree (no view-as)" do
    with_rls(user: @maverick_admin) do
      assert_equal 6, Organization.count
      assert_equal 2, Site.count
    end
  end

  test "Customer cannot read sibling Customer's site even with the id" do
    fabrikam_site = Site.create!(organization: @fabrikam, name: "Fabrikam Array", polling_interval_seconds: 30)
    with_rls(user: @northwind_user) do
      assert_raises(ActiveRecord::RecordNotFound) { Site.find(fabrikam_site.id) }
    end
  end
end
