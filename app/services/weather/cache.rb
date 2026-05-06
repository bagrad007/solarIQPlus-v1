# frozen_string_literal: true

module Weather
  # Thin caching wrapper around Weather::OpenMeteoAdapter so a Dashboard
  # refresh — or eight Customers all hitting their dashboards within an
  # hour — collapses to a single Open-Meteo call per unique location.
  #
  # The cache key is intentionally simple ("weather:<lat>,<lon>") so it can
  # be invalidated from a console one-liner if the upstream API changes
  # shape mid-day.
  class Cache
    EXPIRES_IN = 3.hours

    def initialize(adapter: OpenMeteoAdapter.new)
      @adapter = adapter
    end

    def fetch(latitude:, longitude:)
      Rails.cache.fetch(cache_key(latitude, longitude), expires_in: EXPIRES_IN) do
        @adapter.fetch(latitude: latitude, longitude: longitude)
      end
    end

    private

    def cache_key(latitude, longitude)
      "weather:#{latitude},#{longitude}"
    end
  end
end
