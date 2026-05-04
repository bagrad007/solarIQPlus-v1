class SitesController < ApplicationController
  # CRUD on Sites. RLS filters every read; the ApplicationController stack
  # has already SET LOCAL ROLE app_user with the request's GUCs in place.

  before_action :load_site, only: [:show, :edit, :update]

  def index
    @sites = Site.order(:name)
  end

  def show
    @latest = Telemetry.where(site_id: @site.id).order(recorded_at: :desc).first
    @recent = Telemetry.where(site_id: @site.id).order(recorded_at: :desc).limit(48)
    @open_cases = Case.where(site_id: @site.id).where.not(status: "closed").order(created_at: :desc).limit(5)
  end

  def new
    @site = Site.new(organization_id: customer_org_for_form&.id, polling_interval_seconds: 30)
  end

  def create
    @site = Site.new(site_params)
    @site.organization_id ||= customer_org_for_form&.id
    if @site.save
      redirect_to site_path(@site), notice: "Site created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @site.update(site_params)
      redirect_to site_path(@site), notice: "Site updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def load_site
    @site = Site.find(params[:id])
  end

  def customer_org_for_form
    org = Current.effective_organization
    return org if org&.customer?
    nil
  end

  def site_params
    params.require(:site).permit(
      :name,
      :gateway_ip,
      :device_credentials_encrypted,
      :polling_interval_seconds,
      :organization_id
    )
  end
end
