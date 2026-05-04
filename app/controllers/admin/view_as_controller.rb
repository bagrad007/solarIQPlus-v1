class Admin::ViewAsController < ApplicationController
  # View-as is Maverick-only. The maverick_admin? gate on POST is an early
  # UX 403 (Architectural Invariant 4 — UI affordance, NOT authorization).
  # The actual privilege containment is in apply_rls_session_vars!, which
  # refuses to write is_maverick='true' or impersonated_org_id for non-Maverick
  # users regardless of session contents.

  before_action :ensure_maverick_admin

  def create
    target = Organization.find(params[:org_id])
    session[:view_as_org_id] = target.id
    redirect_to dashboard_path, notice: "Now viewing as #{target.name}"
  end

  def destroy
    session.delete(:view_as_org_id)
    redirect_to dashboard_path, notice: "Exited view-as"
  end

  private

  def ensure_maverick_admin
    return if current_user&.maverick_admin?
    redirect_to dashboard_path, alert: "Forbidden"
  end
end
