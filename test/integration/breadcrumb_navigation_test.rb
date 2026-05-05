# frozen_string_literal: true

require "test_helper"

class BreadcrumbNavigationTest < ActionDispatch::IntegrationTest
  setup do
    build_tenant_tree
    @case_record = Case.create!(
      organization: @northwind,
      site: @site_a,
      opened_by: @acme_user,
      subject: "Telemetry drift on string A"
    )
  end

  test "Partner sees Dashboard crumb linking home on customer drill" do
    sign_in_as(@acme_user)
    get organization_path(@fabrikam)
    assert_response :success
    assert_select '[data-testid="breadcrumb-trail"]' do
      assert_select "a", text: "Dashboard", count: 1
      assert_select "a[href=?]", dashboard_path, count: 1
    end
    assert_match(/Back to Dashboard/, @response.body)
  end

  test "Maverick sees Partners crumb linking dashboard on partner drill" do
    sign_in_as(@maverick_admin)
    get organization_path(@acme)
    assert_response :success
    assert_select '[data-testid="breadcrumb-trail"]' do
      assert_select "a", text: "Partners", count: 1
      assert_select "a[href=?]", dashboard_path, count: 1
    end
  end

  test "Maverick in view-as anchors trail at Partners then impersonated partner" do
    sign_in_as(@maverick_admin)
    post admin_view_as_path, params: { org_id: @acme.id }
    follow_redirect!
    assert_response :success
    assert_select '[data-testid="breadcrumb-trail"]' do
      assert_select "a", text: "Partners", count: 1
      assert_select "a", text: @acme.name, count: 1
      assert_select "a[href=?]", organization_path(@acme), count: 1
    end
  end

  test "Maverick case show includes partner and customer crumbs" do
    sign_in_as(@maverick_admin)
    get case_path(@case_record)
    assert_response :success
    assert_select '[data-testid="breadcrumb-trail"]' do
      assert_select "a", text: @acme.name
      assert_select "a", text: @northwind.name
    end
  end

  test "Customer user does not see breadcrumb trail" do
    sign_in_as(@northwind_user)
    get dashboard_path
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_select '[data-testid="breadcrumb-trail"]', count: 0
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
