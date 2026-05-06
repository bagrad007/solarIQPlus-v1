# frozen_string_literal: true

module Mcp
  module V1
    class SitesController < Mcp::BaseController
      before_action :load_site, only: [:show, :diagnostics]

      def index
        sites = Site.order(:name).map { |s| { id: s.id, name: s.name } }
        render json: { sites: sites }
      end

      def show
        render json: {
          site: site_public_json(@site),
          operational_summary: SiteOperationalSummary.new(@site).to_h,
          forecast: SiteForecast.new(@site, weather: fetch_weather).to_h
        }
      end

      def diagnostics
        render json: SiteDiagnostics.new(@site).to_h
      end

      private

      def load_site
        @site = Site.find(params[:id])
      end

      def site_public_json(site)
        {
          id: site.id,
          name: site.name,
          latitude: site.latitude,
          longitude: site.longitude,
          nameplate_kw: site.nameplate_kw,
          polling_interval_seconds: site.polling_interval_seconds
        }
      end

      def fetch_weather
        return nil if @site.latitude.blank? || @site.longitude.blank?

        ::SitesController.weather_cache.fetch(
          latitude: @site.latitude.to_f,
          longitude: @site.longitude.to_f
        )
      rescue Weather::OpenMeteoError => e
        Rails.logger.warn("[mcp/v1/sites#show] weather upstream failed: #{e.message}")
        nil
      end
    end
  end
end
