require "test_helper"

class NullSafetyTest < ActiveSupport::TestCase
  # When the request connects as app_user but no GUCs are set (or GUCs are
  # malformed), can_see() must explicitly deny — never accidentally permit.

  setup { build_tenant_tree }

  test "missing GUCs deny all reads (can_see returns false on missing path)" do
    with_no_rls_context do
      assert_equal 0, Organization.count
      assert_equal 0, Site.count
      assert_equal 0, Case.count
    end
  end

  test "non-Maverick user with mode=view_as cannot widen scope" do
    with_rls(user: @acme_user, view_as_org_id: @maverick.id) do
      refute_includes Organization.pluck(:name), "Beta"
      refute_includes Organization.pluck(:name), "Contoso"
      assert_includes Organization.pluck(:name), "Acme"
    end
  end
end
