class CustomerManagerController < ApplicationController
  # Partner-only Customer Manager. The role gate is an early UX 403
  # (Architectural Invariant 4 — UI affordance, NOT authorization). RLS still
  # gates per-row writes; if a Customer somehow reaches this URL, the create
  # would fail at the DB layer because they cannot see the parent Partner.

  before_action :ensure_partner_user

  def index
    @customers = Organization.where(org_type: "customer", parent_id: Current.effective_organization.id).order(:name)
  end

  def create
    customer_attrs = params.require(:organization).permit(:name, :logo_url)
    user_attrs     = params.require(:user).permit(:email, :name, :password)

    Organization.transaction do
      branding = customer_attrs[:logo_url].present? ? { logo_url: customer_attrs[:logo_url] } : {}
      org = Organization.create!(
        name:           customer_attrs[:name],
        org_type:       "customer",
        parent_id:      Current.effective_organization.id,
        branding_config: branding
      )
      User.create!(
        organization_id:  org.id,
        role:             "customer_user",
        email:            user_attrs[:email],
        name:             user_attrs[:name].presence,
        password:         user_attrs[:password].presence || SecureRandom.hex(16)
      )
    end

    redirect_to customer_manager_path, notice: "Customer created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to customer_manager_path, alert: e.message
  end

  private

  def ensure_partner_user
    return if Current.effective_organization&.partner?
    redirect_to dashboard_path, alert: "Customer Manager is for Partner accounts."
  end
end
