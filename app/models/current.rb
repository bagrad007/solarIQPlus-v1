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

  def effective_logo_url
    effective_organization&.effective_logo_url
  end
end
