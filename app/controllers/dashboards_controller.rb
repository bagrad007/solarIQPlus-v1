class DashboardsController < ApplicationController
  # Single entrypoint that dispatches the persona-appropriate template based
  # on the *Effective Tenant* (so Maverick in view-as sees the impersonated
  # org's dashboard, not their own). All queries are RLS-filtered — there is
  # no Rails-level scoping, only what the database lets through.

  def show
    @effective_org = Current.effective_organization

    case @effective_org.org_type
    when "maverick"
      render_maverick_dashboard
    when "partner"
      render_partner_dashboard
    when "customer"
      render_customer_dashboard
    end
  end

  private

  def render_maverick_dashboard
    @partners = Organization.where(org_type: "partner").order(:name)
    @partner_summaries = @partners.map { |p| partner_summary(p) }
    render :maverick
  end

  def render_partner_dashboard
    @customers = Organization.where(org_type: "customer", parent_id: @effective_org.id).order(:name)
    @customer_summaries = @customers.map { |c| customer_summary(c) }
    render :partner
  end

  def render_customer_dashboard
    @sites = Site.where(organization_id: @effective_org.id).order(:name)
    if @sites.size == 1 && !Current.in_view_as?
      redirect_to site_path(@sites.first)
    else
      @site_summaries = @sites.map { |s| site_summary(s) }
      render :customer
    end
  end

  def partner_summary(partner)
    customer_count = Organization.where(org_type: "customer", parent_id: partner.id).count
    critical = Telemetry.where("org_path <@ ?::ltree", partner.path.to_s)
                       .where(recorded_at: 24.hours.ago..)
                       .where(alarm_state: "critical").count
    warn = Telemetry.where("org_path <@ ?::ltree", partner.path.to_s)
                   .where(recorded_at: 24.hours.ago..)
                   .where(alarm_state: "warn").count
    open_cases = Case.where("org_path <@ ?::ltree", partner.path.to_s)
                    .where.not(status: "closed").count
    { org: partner, customer_count: customer_count, critical: critical, warn: warn, open_cases: open_cases }
  end

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
