# frozen_string_literal: true

require "test_helper"

# Architectural Invariant 1: RLS is the only authorization layer for
# alarms. Persona scope is enforced by app.can_see(org_path); the
# AlarmsController does no tenant filtering of its own. View-as on a
# Maverick narrows the scope to the impersonated subtree exactly the way
# it does for sites/cases — no special path.
class AlarmsRlsTest < ActiveSupport::TestCase
  setup do
    build_tenant_tree
    @code = AlarmCode.create!(code: 100, label: "Inverter Offline", default_severity: "critical")

    @northwind_alarm = Alarm.create!(site: @site_a, organization: @northwind, code: @code)
    @contoso_alarm   = Alarm.create!(site: @site_b, organization: @contoso,   code: @code)
  end

  test "Maverick sees every alarm in the tree" do
    with_rls(user: @maverick_admin) do
      assert_equal 2, Alarm.count
    end
  end

  test "Partner sees only the alarms inside their subtree" do
    with_rls(user: @acme_user) do
      assert_equal [@northwind_alarm.id], Alarm.pluck(:id)
    end

    with_rls(user: @beta_user) do
      assert_equal [@contoso_alarm.id], Alarm.pluck(:id)
    end
  end

  test "Customer sees only their own organization's alarms" do
    with_rls(user: @northwind_user) do
      assert_equal [@northwind_alarm.id], Alarm.pluck(:id)
    end
  end

  test "Customer cannot find a sibling Customer's alarm even with the id" do
    with_rls(user: @northwind_user) do
      assert_raises(ActiveRecord::RecordNotFound) { Alarm.find(@contoso_alarm.id) }
    end
  end

  test "Maverick in view-as on Beta only sees Beta's subtree" do
    with_rls(user: @maverick_admin, view_as_org_id: @beta.id) do
      assert_equal [@contoso_alarm.id], Alarm.pluck(:id)
    end
  end

  test "Customer attempting to write outside their subtree is blocked by RLS" do
    with_rls(user: @northwind_user) do
      # The contoso alarm is invisible to this Customer; AR's relation never
      # surfaces the row, so the update reaches zero rows. RLS WITH CHECK
      # would also reject a bypass attempt.
      assert_equal 0, Alarm.where(id: @contoso_alarm.id).update_all(status: "acknowledged")
    end
  end
end
