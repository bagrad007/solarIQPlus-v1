# frozen_string_literal: true

require "test_helper"

# The Site operational dashboard surfaces a "firing alarms" badge in the
# page header that links to the filtered Alarms page. The badge takes the
# muted treatment when zero firing alarms exist for the site, and the
# critical-red treatment otherwise. The link always carries the site_id +
# status[]=firing query so the click lands on the pre-filtered view.
class SiteAlarmBadgeTest < ActionDispatch::IntegrationTest
  setup do
    build_tenant_tree
    @code = AlarmCode.create!(code: 100, label: "Inverter Offline", default_severity: "critical")
  end

  test "renders muted badge when the site has zero firing alarms" do
    sign_in_as(@northwind_user)
    get site_path(@site_a)
    assert_response :success
    assert_select '[data-testid="site-firing-alarms-badge"]' do |badge|
      assert_match(/0 firing alarms/, badge.text)
      assert_match(/alarm-badge--quiet/, badge.first["class"])
      assert_equal alarms_path(site_id: @site_a.id, status: ["firing"]), badge.first["href"]
    end
  end

  test "renders active badge when the site has firing alarms" do
    Alarm.create!(site: @site_a, organization: @northwind, code: @code)
    Alarm.create!(site: @site_a, organization: @northwind, code: @code)

    sign_in_as(@northwind_user)
    get site_path(@site_a)
    assert_response :success
    assert_select '[data-testid="site-firing-alarms-badge"]' do |badge|
      assert_match(/2 firing alarms/, badge.text)
      assert_match(/alarm-badge--active/, badge.first["class"])
    end
  end

  test "RLS-narrowed: another customer's firing alarm does not count toward this site's badge" do
    other_alarm = Alarm.create!(site: @site_b, organization: @contoso, code: @code)

    sign_in_as(@northwind_user)
    get site_path(@site_a)
    assert_response :success
    assert_select '[data-testid="site-firing-alarms-badge"]' do |badge|
      assert_match(/0 firing alarms/, badge.text)
    end
    assert other_alarm.persisted?
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
