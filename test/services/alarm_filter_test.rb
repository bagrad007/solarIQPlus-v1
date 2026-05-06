require "test_helper"

class AlarmFilterTest < ActiveSupport::TestCase
  # Drives AlarmFilter through its single public surface (#results). Tests
  # never inspect internal scopes or query construction (delegate-implementation:
  # gray-box). Each test exercises one filter, sort, or search behavior.

  setup do
    build_tenant_tree

    @site_b_2 = Site.create!(organization: @contoso, name: "Contoso Annex", polling_interval_seconds: 30)

    @code_inverter = AlarmCode.create!(code: 100, label: "Inverter Offline",     default_severity: "critical")
    @code_voltage  = AlarmCode.create!(code: 200, label: "Low String Voltage",   default_severity: "warning")
    @code_gateway  = AlarmCode.create!(code: 404, label: "Gateway No Response",  default_severity: "critical")
    @code_recovery = AlarmCode.create!(code: 900, label: "Inverter Recovered",   default_severity: "cleared")

    base = 5.days.ago

    @firing_critical = Alarm.create!(
      site: @site_a, organization: @northwind, code: @code_inverter,
      opened_at: base + 1.hour
    )
    @firing_warning = Alarm.create!(
      site: @site_a, organization: @northwind, code: @code_voltage,
      opened_at: base + 2.hours
    )
    @ack_critical = Alarm.create!(
      site: @site_a, organization: @northwind, code: @code_gateway,
      opened_at: base + 3.hours
    )
    @ack_critical.update!(status: "acknowledged", acknowledged_at: base + 4.hours, acknowledged_by_user_id: @northwind_user.id)

    @cleared = Alarm.create!(
      site: @site_a, organization: @northwind, code: @code_recovery, severity: "cleared",
      opened_at: base + 5.hours
    )
    @cleared.update!(status: "cleared", cleared_at: base + 6.hours, cleared_by_user_id: @northwind_user.id)

    # Different site under same Customer
    @firing_other_site = Alarm.create!(
      site: @site_b_2, organization: @contoso, code: @code_voltage,
      opened_at: base + 7.hours
    )
  end

  def filter(params = {})
    AlarmFilter.new(params).results
  end

  test "default scope hides cleared alarms and sorts by opened_at desc" do
    res = filter
    assert_equal [@firing_other_site, @ack_critical, @firing_warning, @firing_critical].map(&:id),
                 res.relation.map(&:id)
    assert_equal 4, res.total_count
  end

  test "show_cleared exposes cleared rows" do
    res = filter(show_cleared: "1")
    assert_includes res.relation.map(&:id), @cleared.id
    assert_equal 5, res.total_count
  end

  test "filters by severity" do
    res = filter(severity: ["critical"])
    assert_equal [@ack_critical, @firing_critical].map(&:id).sort,
                 res.relation.map(&:id).sort
  end

  test "filters by status" do
    res = filter(status: ["firing"])
    assert_equal [@firing_other_site, @firing_warning, @firing_critical].map(&:id).sort,
                 res.relation.map(&:id).sort
  end

  test "filters by site_id" do
    res = filter(site_id: @site_b_2.id)
    assert_equal [@firing_other_site.id], res.relation.map(&:id)
  end

  test "filters by code_id" do
    res = filter(code_id: @code_voltage.id)
    assert_equal [@firing_other_site, @firing_warning].map(&:id).sort,
                 res.relation.map(&:id).sort
  end

  test "filters by customer_id (organization)" do
    res = filter(customer_id: @contoso.id)
    assert_equal [@firing_other_site.id], res.relation.map(&:id)
  end

  test "search matches the alarm title case-insensitively" do
    res = filter(q: "gateway")
    assert_equal [@ack_critical.id], res.relation.map(&:id)
  end

  test "search matches the alarm code label" do
    res = filter(q: "low string")
    assert_equal [@firing_other_site, @firing_warning].map(&:id).sort,
                 res.relation.map(&:id).sort
  end

  test "search matches the site name" do
    res = filter(q: "annex")
    assert_equal [@firing_other_site.id], res.relation.map(&:id)
  end

  test "sorts by opened_at ascending when dir=asc" do
    res = filter(sort: "opened_at", dir: "asc")
    assert_equal [@firing_critical, @firing_warning, @ack_critical, @firing_other_site].map(&:id),
                 res.relation.map(&:id)
  end

  test "sorts by severity (critical first when desc)" do
    res = filter(sort: "severity", dir: "desc")
    severities_in_order = res.relation.map(&:severity)
    assert_equal severities_in_order.sort_by { |s| { "critical" => 0, "warning" => 1, "cleared" => 2 }.fetch(s) },
                 severities_in_order
  end

  test "unknown sort key falls back to opened_at desc" do
    res = filter(sort: "totally_made_up", dir: "asc")
    assert_equal [@firing_other_site, @ack_critical, @firing_warning, @firing_critical].map(&:id),
                 res.relation.map(&:id)
  end

  test "applied summary lists every active filter for UI surfacing" do
    res = filter(severity: ["critical"], status: ["firing"], q: "gateway", site_id: @site_a.id)
    keys = res.applied.keys.map(&:to_sym)
    assert_includes keys, :severity
    assert_includes keys, :status
    assert_includes keys, :q
    assert_includes keys, :site_id
  end

  test "ignores unknown params" do
    res = filter(rogue_param: "boom", drop_table: "users")
    assert_equal 4, res.total_count
  end

  test "page and per_page are reported on the result" do
    res = filter
    assert_equal 1,  res.page
    assert_equal 50, res.per_page
  end
end
