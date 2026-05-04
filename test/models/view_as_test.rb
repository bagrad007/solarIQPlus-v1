require "test_helper"

class ViewAsTest < ActiveSupport::TestCase
  setup { build_tenant_tree }

  test "Maverick in view-as sees exactly the impersonated org's scope" do
    with_rls(user: @maverick_admin, view_as_org_id: @beta.id) do
      assert_equal %w[Beta Contoso].sort, Organization.pluck(:name).sort
      refute_includes Organization.pluck(:name), "Acme"
      refute_includes Organization.pluck(:name), "Northwind"
    end
  end

  test "Maverick in view-as as a Customer sees only that Customer" do
    Site.create!(organization: @fabrikam, name: "Fabrikam Array", polling_interval_seconds: 30)
    with_rls(user: @maverick_admin, view_as_org_id: @northwind.id) do
      assert_equal [@northwind.id], Organization.where(org_type: "customer").pluck(:id)
      assert_equal [@site_a.id],    Site.pluck(:id)
    end
  end

  test "Exiting view-as restores Maverick global visibility" do
    with_rls(user: @maverick_admin, view_as_org_id: @beta.id) do
      assert_equal 1, Organization.where(org_type: "customer").count
    end
    with_rls(user: @maverick_admin) do
      assert_equal 3, Organization.where(org_type: "customer").count
    end
  end
end
