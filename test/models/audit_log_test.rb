require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  setup do
    build_tenant_tree
    Current.user = @acme_user
  end

  teardown { Current.reset }

  test "updating an audited Site field creates an audit_log row" do
    assert_difference -> { AuditLog.count }, 1 do
      @site_a.update!(polling_interval_seconds: 45)
    end
    log = AuditLog.order(created_at: :desc).first
    assert_equal "Site",                    log.auditable_type
    assert_equal @site_a.id,                log.auditable_id
    assert_equal "polling_interval_seconds", log.field_name
    assert_equal "30",                      log.old_value
    assert_equal "45",                      log.new_value
    assert_equal @acme_user.id,             log.actor_user_id
  end

  test "updating a non-audited field does not write an audit_log" do
    assert_no_difference -> { AuditLog.count } do
      @site_a.update!(name: "Renamed")
    end
  end

  test "audit_logs cannot be modified once written" do
    @site_a.update!(gateway_ip: "10.99.0.1")
    log = AuditLog.last
    assert_raises(ActiveRecord::StatementInvalid) { log.update!(field_name: "x") }
    assert_raises(ActiveRecord::StatementInvalid) { log.destroy }
  end
end
