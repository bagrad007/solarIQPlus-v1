require "test_helper"

class AlarmLifecycleTest < ActiveSupport::TestCase
  # Drives Alarm#acknowledge!, #clear!, and the underlying state-machine
  # trigger. Every assertion goes through the public AR / model interface
  # — never inspects the trigger source or the audit-log fan-out internals
  # (delegate-implementation: gray-box).

  setup do
    build_tenant_tree
    @code = AlarmCode.create!(
      code:             404,
      label:            "Gateway No Response",
      default_severity: "critical",
      description:      "Test alarm code"
    )
    @alarm = Alarm.create!(
      site:         @site_a,
      organization: @northwind,
      code:         @code
    )
  end

  test "newly opened alarm starts as firing with severity copied from the code" do
    assert_equal "firing",   @alarm.status
    assert_equal "critical", @alarm.severity
    assert_equal "Gateway No Response", @alarm.title
    assert_nil   @alarm.acknowledged_at
    assert_nil   @alarm.cleared_at
  end

  test "acknowledges a firing alarm and stamps the actor" do
    @alarm.acknowledge!(actor: @northwind_user)
    @alarm.reload
    assert_equal "acknowledged",    @alarm.status
    assert_equal @northwind_user.id, @alarm.acknowledged_by_user_id
    assert_not_nil @alarm.acknowledged_at
  end

  test "acknowledging emits an audit_log row tagged with the actor and the transition" do
    assert_difference -> { AuditLog.where(auditable_type: "Alarm", auditable_id: @alarm.id).count }, +1 do
      @alarm.acknowledge!(actor: @northwind_user)
    end
    log = AuditLog.where(auditable_type: "Alarm", auditable_id: @alarm.id).last
    assert_equal "status",       log.field_name
    assert_equal "firing",       log.old_value
    assert_equal "acknowledged", log.new_value
    assert_equal @northwind_user.id, log.actor_user_id
  end

  test "clears a firing alarm directly and stamps clear metadata" do
    @alarm.clear!(actor: @northwind_user)
    @alarm.reload
    assert_equal "cleared",         @alarm.status
    assert_equal @northwind_user.id, @alarm.cleared_by_user_id
    assert_not_nil @alarm.cleared_at
  end

  test "clears an acknowledged alarm and preserves ack metadata" do
    @alarm.acknowledge!(actor: @northwind_user)
    @alarm.reload
    @alarm.clear!(actor: @maverick_admin)
    @alarm.reload

    assert_equal "cleared",          @alarm.status
    assert_equal @maverick_admin.id, @alarm.cleared_by_user_id
    assert_equal @northwind_user.id, @alarm.acknowledged_by_user_id
    assert_not_nil @alarm.acknowledged_at
    assert_not_nil @alarm.cleared_at
  end

  test "clearing emits an audit_log row" do
    assert_difference -> { AuditLog.where(auditable_type: "Alarm", auditable_id: @alarm.id).count }, +1 do
      @alarm.clear!(actor: @northwind_user)
    end
    log = AuditLog.where(auditable_type: "Alarm", auditable_id: @alarm.id).last
    assert_equal "status",  log.field_name
    assert_equal "firing",  log.old_value
    assert_equal "cleared", log.new_value
  end

  test "cleared is terminal — cannot transition to firing or acknowledged" do
    @alarm.clear!(actor: @northwind_user)
    @alarm.reload
    assert_raises(ActiveRecord::StatementInvalid) do
      @alarm.update!(status: "firing")
    end
    @alarm.reload
    assert_raises(ActiveRecord::StatementInvalid) do
      @alarm.update!(status: "acknowledged")
    end
  end

  test "acknowledged cannot move back to firing" do
    @alarm.acknowledge!(actor: @northwind_user)
    @alarm.reload
    assert_raises(ActiveRecord::StatementInvalid) do
      @alarm.update!(status: "firing")
    end
  end

  test "display_code formats the integer code as E-NNN" do
    assert_equal "E-404", @alarm.display_code
  end
end
