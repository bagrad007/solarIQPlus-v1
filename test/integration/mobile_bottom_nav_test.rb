# frozen_string_literal: true

require "test_helper"

# The mobile bottom nav must be a persistent affordance for any signed-in
# user — it is the only navigation surface available below the md
# breakpoint, so hiding it on any authenticated route strands the user
# without a way to move between sections of the app.
#
# `data-testid="mobile-bottom-nav"` pins the contract so future markup
# refactors can't silently remove the bar.
class MobileBottomNavTest < ActionDispatch::IntegrationTest
  setup { build_tenant_tree }

  test "renders on Audit Logs for a signed-in Maverick admin" do
    sign_in_as(@maverick_admin)

    get audit_logs_path

    assert_response :success
    assert_select '[data-testid="mobile-bottom-nav"]', count: 1
  end

  test "Maverick's bottom nav links to Audit Logs" do
    sign_in_as(@maverick_admin)

    get dashboard_path

    assert_response :success
    assert_select '[data-testid="mobile-bottom-nav"]' do
      assert_select "a[href=?]", audit_logs_path, text: /Audit Logs/, count: 1
    end
  end

  test "Partner's bottom nav links to Customer Manager" do
    sign_in_as(@acme_user)

    get dashboard_path

    assert_response :success
    assert_select '[data-testid="mobile-bottom-nav"]' do
      assert_select "a[href=?]", customer_manager_path, text: /Customer Manager/, count: 1
    end
  end

  test "bottom nav contains only navigation items (Account moved to top app bar)" do
    sign_in_as(@acme_user)

    get dashboard_path

    assert_response :success
    assert_select '[data-testid="mobile-bottom-nav"]' do
      assert_select "button", count: 0
      assert_select "li.flex-1", count: nav_items_count_for(@acme_user)
    end
  end

  test "account sheet carries tenant scope and a Sign out form posting DELETE" do
    sign_in_as(@acme_user)

    get dashboard_path

    assert_response :success
    assert_select '[data-testid="mobile-account-sheet"]', count: 1 do
      assert_select "*", text: /#{Regexp.escape(@acme_user.organization.name)}/
      assert_select "form[action=?][method=?]", destroy_user_session_path, "post" do
        assert_select "input[name=_method][value=delete]", count: 1
        assert_select "button", text: /Sign out/i, count: 1
      end
    end
  end

  # JS behavior (toggle on tap, close on Esc/outside) is verified manually in
  # the browser — the codebase has no JS test runner. The integration check
  # here only pins the static wiring (controller, target, action) so the
  # markup contract can't be silently broken. After the mobile top app bar
  # work, the trigger lives in the top bar; the sheet stays bottom-anchored;
  # both share the controller wrapper hoisted to application.html.erb.
  test "account sheet is wired into the layout-level Stimulus controller" do
    sign_in_as(@acme_user)

    get dashboard_path

    assert_response :success
    assert_select '[data-controller="mobile-account-sheet"]' do
      assert_select 'button[data-mobile-account-sheet-target="button"][data-action*="mobile-account-sheet#toggle"]', count: 1
      assert_select '[data-mobile-account-sheet-target="sheet"]', count: 1
    end
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end

  # Mirror ApplicationHelper#nav_items so the test doesn't drift if the
  # persona-specific item set changes — but stays decoupled from the helper's
  # exact paths. After the Alarms tab landed (Plan A wave 2): Maverick = 5,
  # Partner = 5, Customer = 4.
  def nav_items_count_for(user)
    case user.organization.org_type
    when "maverick", "partner" then 5
    when "customer"            then 4
    end
  end
end
