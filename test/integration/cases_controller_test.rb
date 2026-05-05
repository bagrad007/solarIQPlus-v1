require "test_helper"

class CasesControllerTest < ActionDispatch::IntegrationTest
  setup { build_tenant_tree }

  test "create ignores client supplied status" do
    sign_in_as(@northwind_user)

    post site_cases_path(@site_a), params: {
      case: {
        site_id: @site_a.id,
        subject: "Attempted closed case",
        status: "closed"
      }
    }

    created_case = Case.order(created_at: :desc).first
    assert_equal "open", created_case.status
  end

  test "show renders when view-as hides the opener user" do
    support_case = Case.create!(
      site:              @site_a,
      organization:      @northwind,
      opened_by:         @maverick_admin,
      subject:           "Opened from Maverick while inspecting"
    )

    sign_in_as(@maverick_admin)
    post admin_view_as_path, params: { org_id: @acme.id }
    get case_path(support_case)

    assert_response :success
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
