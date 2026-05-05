require "test_helper"

# The widget renders only on Customer-scoped pages. This test pins the
# "URL-driven" rule from the plan so a future controller change can't
# silently leak the demo widget onto roll-up pages.
class AiEnergyAnalystWidgetVisibilityTest < ActionDispatch::IntegrationTest
  WIDGET_MARKER = 'data-controller="ai-energy-analyst"'

  setup { build_tenant_tree }

  test "widget renders on a customer's site show page" do
    sign_in_as(@northwind_user)
    get site_path(@site_a)
    assert_response :success
    assert_includes response.body, WIDGET_MARKER
  end

  test "widget is hidden on the Maverick partners roll-up dashboard" do
    sign_in_as(@maverick_admin)
    get dashboard_path
    assert_response :success
    assert_not_includes response.body, WIDGET_MARKER
  end

  test "widget is hidden on the Partner customers roll-up dashboard" do
    sign_in_as(@acme_user)
    get dashboard_path
    assert_response :success
    assert_not_includes response.body, WIDGET_MARKER
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
