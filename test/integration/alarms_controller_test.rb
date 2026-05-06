require "test_helper"

# End-to-end tests for /alarms. Every assertion goes through the public
# HTTP interface; the controller does no business logic so any failure
# here points at the model, the filter, or the view contract — not at
# branching that lives in the controller.
class AlarmsControllerTest < ActionDispatch::IntegrationTest
  setup do
    build_tenant_tree

    @code_inverter = AlarmCode.create!(code: 100, label: "Inverter Offline",    default_severity: "critical")
    @code_voltage  = AlarmCode.create!(code: 200, label: "Low String Voltage",  default_severity: "warning")
    @code_gateway  = AlarmCode.create!(code: 404, label: "Gateway No Response", default_severity: "critical")

    @northwind_alarm_firing = Alarm.create!(site: @site_a, organization: @northwind, code: @code_inverter)
    @northwind_alarm_warn   = Alarm.create!(site: @site_a, organization: @northwind, code: @code_voltage)
    @contoso_alarm          = Alarm.create!(site: @site_b, organization: @contoso,   code: @code_gateway)
  end

  test "renders for a Maverick (sees every alarm in the tree)" do
    sign_in_as(@maverick_admin)
    get alarms_path
    assert_response :success
    assert_select '[data-testid="alarms-table"] [data-testid="alarm-row"]', count: 3
  end

  test "renders for a Partner (sees only their subtree's alarms)" do
    sign_in_as(@acme_user)
    get alarms_path
    assert_response :success
    assert_select '[data-testid="alarms-table"] [data-testid="alarm-row"]', count: 2
  end

  test "renders for a Customer (sees only their own alarms)" do
    sign_in_as(@northwind_user)
    get alarms_path
    assert_response :success
    assert_select '[data-testid="alarms-table"] [data-testid="alarm-row"]', count: 2
  end

  test "filtering by severity narrows the rows" do
    sign_in_as(@maverick_admin)
    get alarms_path(severity: ["critical"])
    assert_response :success
    rendered_ids = css_select('[data-testid="alarm-row"]').map { |el| el["data-alarm-id"] }
    assert_equal [@northwind_alarm_firing.id, @contoso_alarm.id].sort, rendered_ids.sort
  end

  test "search by site name narrows the rows" do
    sign_in_as(@maverick_admin)
    get alarms_path(q: "Northwind")
    assert_response :success
    rendered_ids = css_select('[data-testid="alarm-row"]').map { |el| el["data-alarm-id"] }
    assert_equal [@northwind_alarm_firing.id, @northwind_alarm_warn.id].sort, rendered_ids.sort
  end

  test "search by alarm code label narrows the rows" do
    sign_in_as(@maverick_admin)
    get alarms_path(q: "Gateway")
    assert_response :success
    rendered_ids = css_select('[data-testid="alarm-row"]').map { |el| el["data-alarm-id"] }
    assert_equal [@contoso_alarm.id], rendered_ids
  end

  test "Customer can acknowledge their own alarm" do
    sign_in_as(@northwind_user)
    post acknowledge_alarm_path(@northwind_alarm_firing)
    assert_response :redirect
    assert_equal "acknowledged", @northwind_alarm_firing.reload.status
    assert_equal @northwind_user.id, @northwind_alarm_firing.acknowledged_by_user_id
  end

  test "Customer can clear their own alarm" do
    sign_in_as(@northwind_user)
    post clear_alarm_path(@northwind_alarm_firing)
    assert_response :redirect
    assert_equal "cleared", @northwind_alarm_firing.reload.status
  end

  test "Customer cannot acknowledge another Customer's alarm — RLS surfaces 404" do
    sign_in_as(@northwind_user)
    post acknowledge_alarm_path(@contoso_alarm)
    assert_response :not_found
  end

  test "Acknowledging an already-cleared alarm surfaces a flash[:alert]" do
    @northwind_alarm_firing.update!(status: "cleared", cleared_at: Time.current, cleared_by_user_id: @northwind_user.id)
    sign_in_as(@northwind_user)
    post acknowledge_alarm_path(@northwind_alarm_firing)
    follow_redirect!
    assert_match(/final|cannot|invalid/i, flash[:alert].to_s + response.body)
  end

  test "in view-as the Acknowledge / Clear CTAs are hidden in the rendered HTML" do
    sign_in_as(@maverick_admin)
    post admin_view_as_path, params: { org_id: @acme.id }
    get alarms_path
    assert_response :success
    assert_select '[data-testid="alarm-acknowledge"]', count: 0
    assert_select '[data-testid="alarm-clear"]',       count: 0
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
