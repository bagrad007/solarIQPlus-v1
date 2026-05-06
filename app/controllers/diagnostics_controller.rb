class DiagnosticsController < ApplicationController
  # Per-Site Diagnostics page: React island (SiteDiagnostics) plus the same
  # forecast + open-case context as the operational dashboard (ERB), so the
  # layout can mirror the Stitch diagnostics mock without inventing data.

  before_action :load_site, only: [:show]

  def index
    @sites = Site.order(:name)

    if @sites.size == 1 && !Current.in_view_as?
      redirect_to site_diagnostics_path(@sites.first)
    end
  end

  def show
    weather = fetch_weather
    @forecast    = SiteForecast.new(@site, weather: weather).to_h
    @open_cases  = Case.where(site_id: @site.id).where.not(status: "closed").order(created_at: :desc).limit(5)
    @diagnostics_payload = SiteDiagnostics.new(@site).to_h.merge(forecast: @forecast)
  end

  private

  def load_site
    @site = Site.find(params[:site_id])
  end

  # Reuses SitesController’s cache seam so integration tests that stub
  # SitesController.weather_cache also cover diagnostics.
  def fetch_weather
    return nil if @site.latitude.blank? || @site.longitude.blank?

    SitesController.weather_cache.fetch(
      latitude:  @site.latitude.to_f,
      longitude: @site.longitude.to_f
    )
  rescue Weather::OpenMeteoError => e
    Rails.logger.warn("[diagnostics#show] weather upstream failed: #{e.message}")
    nil
  end
end
