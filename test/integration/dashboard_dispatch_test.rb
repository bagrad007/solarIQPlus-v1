require "test_helper"

class DashboardDispatchTest < ActionDispatch::IntegrationTest
  setup { build_tenant_tree }

  test "Maverick lands on the partners dashboard" do
    sign_in_as(@maverick_admin)
    get dashboard_path
    assert_response :success
    assert_select "h1", text: "Partners"
  end

  test "Partner lands on the customers dashboard" do
    sign_in_as(@acme_user)
    get dashboard_path
    assert_response :success
    assert_select "h1", text: @acme.name
  end

  test "Customer with multiple sites lands on the sites dashboard" do
    Site.create!(organization: @northwind, name: "Second site", polling_interval_seconds: 30)
    sign_in_as(@northwind_user)
    get dashboard_path
    assert_response :success
    assert_select "h1", text: @northwind.name
  end

  test "Customer sites dashboard links each site to its diagnostics page" do
    plant_b = Site.create!(organization: @northwind, name: "Plant B", polling_interval_seconds: 30)
    sign_in_as(@northwind_user)
    get dashboard_path
    assert_response :success
    assert_select "a[href=?]", site_diagnostics_path(@site_a), text: /Diagnostics/i
    assert_select "a[href=?]", site_diagnostics_path(plant_b), text: /Diagnostics/i
  end

  test "Customer with exactly one site is redirected to that site" do
    sign_in_as(@northwind_user)
    get dashboard_path
    assert_redirected_to site_path(@site_a)
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
