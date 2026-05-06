class SitesController < ApplicationController
  # CRUD on Sites. RLS filters every read; the ApplicationController stack
  # has already SET LOCAL ROLE app_user with the request's GUCs in place.

  # Class-level injection seam for the weather cache so integration tests can
  # swap in a stub instead of pummeling Open-Meteo. Production uses the real
  # Weather::Cache wrapping Weather::OpenMeteoAdapter.
  cattr_accessor :weather_cache, default: Weather::Cache.new

  before_action :load_site, only: [ :show, :edit, :update ]

  def index
    @sites = Site.order(:name)
  end

  def show
    weather     = fetch_weather
    @summary    = SiteOperationalSummary.new(@site).to_h(weather: weather)
    @forecast    = SiteForecast.new(@site, weather: weather).to_h
    @open_cases  = Case.where(site_id: @site.id).where.not(status: "closed").order(created_at: :desc).limit(5)
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

  # Returns the parsed Open-Meteo payload, or nil if the Site doesn't have a
  # location yet or the upstream call fails. SiteForecast handles a nil
  # weather hash by reporting "—" placeholders, so the page degrades cleanly
  # rather than 500ing when the network blips.
  def fetch_weather
    return nil if @site.latitude.blank? || @site.longitude.blank?

    self.class.weather_cache.fetch(
      latitude:  @site.latitude.to_f,
      longitude: @site.longitude.to_f
    )
  rescue Weather::OpenMeteoError => e
    Rails.logger.warn("[sites#show] weather upstream failed: #{e.message}")
    nil
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
