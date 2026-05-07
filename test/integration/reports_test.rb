# frozen_string_literal: true

require "test_helper"

class ReportsTest < ActionDispatch::IntegrationTest
  setup do
    build_tenant_tree
    @north_report = ScheduledReport.create!(
      organization: @northwind,
      name: "North KPI Pack",
      recipients: ["ops@north.test"],
      ai_prompt: "Northwind fleet summary",
      frequency: "daily",
      hour: 8,
      time_zone: "UTC"
    )
    @fab_report = ScheduledReport.create!(
      organization: @fabrikam,
      name: "Fabrikam Weekly Ops",
      recipients: ["ops@fab.test"],
      ai_prompt: "Fabrikam digest",
      frequency: "weekly",
      hour: 7,
      time_zone: "UTC"
    )
  end

  test "Maverick in view-as as a Customer only sees that customer's scheduled reports" do
    sign_in_as(@maverick_admin)
    assert_response :redirect
    refute_match(%r{/users/sign_in}, response.location.to_s, "Devise sign-in failed for Maverick admin")

    post admin_view_as_path, params: { org_id: @northwind.id }
    assert_response :redirect
    # Skip follow_redirect!: rack-test can drop the Devise session between the
    # dashboard redirect hop and the next GET (view_as_affordance_test avoids
    # that pattern too).

    get reports_path
    assert_response :success
    assert_match(/North KPI Pack/, @response.body)
    refute_match(/Fabrikam Weekly Ops/, @response.body)
  end

  test "POST create persists a distinctive ai_prompt and lists it on index" do
    sign_in_as(@northwind_user)
    prompt = "Weekly efficiency of Site B vs Site A — include 日本語 unicode smoke."

    assert_difference -> { ScheduledReport.where(organization_id: @northwind.id).count }, 1 do
      post reports_path,
           params: {
             scheduled_report: {
               name: "Customer digest",
               recipients_line: "lead@north.test",
               ai_prompt: prompt,
               frequency: "monthly",
               hour: 14,
               time_zone: "UTC",
               enabled: "1"
             }
           }
    end
    assert_redirected_to reports_path
    follow_redirect!
    assert_match(/#{Regexp.escape(prompt)}/, @response.body)
  end

  test "GET index shows editable report body field and schedule status in table" do
    sign_in_as(@northwind_user)
    get reports_path
    assert_response :success

    assert_select "[data-testid='report-content-preview']", count: 1
    assert_match(/Active/, @response.body)
    assert_match(/Scheduled reports/, @response.body)
    assert_match(/curtailment/, @response.body)
  end

  test "POST reports/draft_body returns templated body from ai_prompt (demo)" do
    sign_in_as(@northwind_user)
    post reports_draft_body_path, params: { ai_prompt: "Daily kWh and revenue" }
    assert_response :success
    body = response.parsed_body["report_content_preview"]
    assert_includes body, "Daily kWh and revenue"
    assert_includes body, "[Draft — edit before recipients see this]"
  end

  test "POST dispatch enqueues ScheduledReports::DispatchJob immediately" do
    sign_in_as(@northwind_user)

    assert_enqueued_jobs(1, only: ScheduledReports::DispatchJob) do
      post dispatch_report_path(@north_report)
    end
    assert_redirected_to reports_path
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
