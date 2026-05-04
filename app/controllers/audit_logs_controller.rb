class AuditLogsController < ApplicationController
  # Maverick-only audit feed. The role gate is an early UX 403; RLS naturally
  # scopes audit_logs to the caller's effective_org_path, so for a Maverick
  # not in view-as this is the entire system.

  before_action :ensure_maverick_admin

  def index
    @logs = AuditLog.order(created_at: :desc).limit(500)
  end

  private

  def ensure_maverick_admin
    return if current_user&.maverick_admin?
    redirect_to dashboard_path, alert: "Audit Logs are Maverick-only."
  end
end
