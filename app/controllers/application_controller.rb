class ApplicationController < ActionController::Base
  # Machine clients under /mcp/ (Bearer token) often send non-browser user agents.
  allow_browser versions: :modern, if: -> { !request.path.start_with?("/mcp/") }

  before_action :authenticate_user!
  before_action :set_current_attributes
  around_action :with_rls_context

  private

  def set_current_attributes
    Current.user          = current_user
    Current.session_state = session.to_h.symbolize_keys
  end

  # Open a transaction, drop into the constrained `app_user` role, and stamp
  # the request's identity into Postgres GUCs. Every query in the controller's
  # call stack — including writes — runs under RLS. SET LOCAL automatically
  # clears at transaction end, so connections returned to the pool carry no
  # caller state.
  def with_rls_context(&block)
    return yield unless current_user
    ActiveRecord::Base.transaction do
      apply_rls_session_vars!
      yield
    end
  end

  # Defense in depth (Architectural Invariant 3): refuse to set the
  # privilege-bearing GUCs (is_maverick='true', any impersonated_org_id)
  # for non-Maverick users, even if the session somehow contains stale state.
  def apply_rls_session_vars!
    is_maverick   = current_user.maverick_admin?
    impersonating = is_maverick && session[:view_as_org_id].present?

    binds = [
      current_user.id.to_s,
      current_user.organization_id.to_s,
      is_maverick   ? "true"    : "false",
      impersonating ? "view_as" : "normal",
      impersonating ? session[:view_as_org_id].to_s : ""
    ]
    sql = <<~SQL.squish
      SELECT
        set_config('app.user_id',             $1, true),
        set_config('app.org_id',              $2, true),
        set_config('app.is_maverick',         $3, true),
        set_config('app.mode',                $4, true),
        set_config('app.impersonated_org_id', $5, true)
    SQL

    ActiveRecord::Base.connection.execute("SET LOCAL ROLE app_user")
    ActiveRecord::Base.connection.exec_query(sql, "RLS", binds)
  end
end
