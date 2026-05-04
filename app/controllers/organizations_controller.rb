class OrganizationsController < ApplicationController
  # Drill-down navigation between tiers (Maverick → Partner → Customer).
  # Clicking a Partner card as Maverick navigates here; clicking a Customer
  # card as Partner navigates here. RLS handles the access decision; if the
  # current user can't see the org, the find raises ActiveRecord::RecordNotFound.

  def show
    @target = Organization.find(params[:id])

    case @target.org_type
    when "partner"
      @customers = Organization.where(org_type: "customer", parent_id: @target.id).order(:name)
      @customer_summaries = @customers.map { |c| customer_summary(c) }
      render :show_partner
    when "customer"
      @sites = Site.where(organization_id: @target.id).order(:name)
      if @sites.size == 1
        redirect_to site_path(@sites.first)
      else
        @site_summaries = @sites.map { |s| site_summary(s) }
        render :show_customer
      end
    else
      redirect_to dashboard_path, alert: "Cannot drill into a Maverick organization."
    end
  end

  private

  def customer_summary(customer)
    site_count = Site.where(organization_id: customer.id).count
    open_cases = Case.where(organization_id: customer.id).where.not(status: "closed").count
    critical = Telemetry.where(organization_id: customer.id)
                       .where(recorded_at: 24.hours.ago..)
                       .where(alarm_state: "critical").count
    { org: customer, site_count: site_count, open_cases: open_cases, critical: critical }
  end

  def site_summary(site)
    latest = Telemetry.where(site_id: site.id).order(recorded_at: :desc).first
    { site: site, latest: latest }
  end
end
