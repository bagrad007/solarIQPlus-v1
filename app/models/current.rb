class Current < ActiveSupport::CurrentAttributes
  # Per-request identity / scope cache. Populated by ApplicationController.
  # The session hash is stored verbatim so view-as state survives across
  # mixed reads in a single request.

  attribute :user, :session_state

  def organization
    user&.organization
  end

  def in_view_as?
    return false unless user&.maverick_admin?
    session_state.present? && session_state[:view_as_org_id].present?
  end

  def impersonated_organization
    return nil unless in_view_as?
    Organization.find_by(id: session_state[:view_as_org_id])
  end

  def effective_organization
    impersonated_organization || organization
  end

  # Effective Logo for the current request. Calls the SECURITY DEFINER
  # `app.effective_logo_url(uuid)` so the ancestry walk works for Customer
  # users (whose RLS scope hides parent Partner rows from a plain Active
  # Record `parent` association). The Ruby Organization#effective_logo_url
  # method is retained for non-RLS contexts (model tests, console).
  def effective_logo_url
    org_id = effective_organization&.id
    return nil unless org_id
    ActiveRecord::Base.connection.select_value(
      "SELECT app.effective_logo_url($1)",
      "EffectiveLogo",
      [ org_id ]
    )
  end
end
