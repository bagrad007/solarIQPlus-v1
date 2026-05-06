# frozen_string_literal: true

require "net/http"
require "json"

module Weather
  # Raised on any non-2xx response from Open-Meteo or unparseable payload.
  # The caller (Weather::Cache, ultimately the Dashboard) decides whether to
  # surface "—" placeholders or retry — this adapter is just the boundary.
  class OpenMeteoError < StandardError; end

  # Pure HTTP boundary for the Open-Meteo daily-forecast endpoint.
  # Returns parsed weather for *today* and *tomorrow* in the shape the rest of
  # the system expects (peak-sun-hours, cloud cover, high temp, condition).
  #
  #   Weather::OpenMeteoAdapter.new.fetch(latitude:, longitude:)
  #   # => { today: { date:, peak_sun_hours:, cloud_cover_pct:,
  #   #               temp_high_c:, condition: }, tomorrow: { ... } }
  #
  # Tests can swap the http_client to avoid real network calls.
  class OpenMeteoAdapter
    ENDPOINT = "https://api.open-meteo.com/v1/forecast"

    DAILY_FIELDS = %w[
      shortwave_radiation_sum
      cloud_cover_mean
      temperature_2m_max
      weather_code
    ].freeze

    # Default HTTP client = a lambda over Net::HTTP. Tests pass their own
    # callable returning a Net::HTTPResponse-like object.
    DEFAULT_HTTP_CLIENT = ->(uri) { Net::HTTP.get_response(uri) }

    def initialize(http_client: DEFAULT_HTTP_CLIENT)
      @http_client = http_client
    end

    def fetch(latitude:, longitude:)
      uri = build_uri(latitude: latitude, longitude: longitude)
      response = @http_client.call(uri)

      code = response.code.to_i
      unless (200..299).cover?(code)
        raise OpenMeteoError, "Open-Meteo returned #{response.code} #{response.message}".strip
      end

      parse_daily(JSON.parse(response.body))
    rescue JSON::ParserError => e
      raise OpenMeteoError, "Open-Meteo returned malformed JSON: #{e.message}"
    end

    private

    def build_uri(latitude:, longitude:)
      uri = URI.parse(ENDPOINT)
      uri.query = URI.encode_www_form(
        latitude:      latitude,
        longitude:     longitude,
        daily:         DAILY_FIELDS.join(","),
        forecast_days: 2,
        timezone:      "auto"
      )
      uri
    end

    def parse_daily(payload)
      daily = payload.fetch("daily", {})
      {
        today:    day_at(daily, 0),
        tomorrow: day_at(daily, 1)
      }
    end

    def day_at(daily, index)
      {
        date:             Date.parse(daily.fetch("time", [])[index].to_s),
        peak_sun_hours:   to_psh(daily.fetch("shortwave_radiation_sum", [])[index]),
        cloud_cover_pct:  daily.fetch("cloud_cover_mean", [])[index].to_i,
        temp_high_c:      daily.fetch("temperature_2m_max", [])[index].to_f.round,
        condition:        condition_for(daily.fetch("weather_code", [])[index])
      }
    end

    # shortwave_radiation_sum is reported in MJ/m². Dividing by 3.6 converts
    # to kWh/m², which equals "peak sun hours" by definition.
    def to_psh(mj_per_m2)
      return 0.0 if mj_per_m2.nil?

      (mj_per_m2.to_f / 3.6).round(2)
    end

    # WMO weather codes → six display buckets the Dashboard knows how to draw.
    # https://open-meteo.com/en/docs (Weather variable documentation).
    WMO_CODE_TO_CONDITION = {
      0  => "sunny",
      1  => "partly_cloudy",
      2  => "partly_cloudy",
      3  => "cloudy",
      45 => "foggy",
      48 => "foggy",
      51 => "rain", 53 => "rain", 55 => "rain", 56 => "rain", 57 => "rain",
      61 => "rain", 63 => "rain", 65 => "rain", 66 => "rain", 67 => "rain",
      71 => "snow", 73 => "snow", 75 => "snow", 77 => "snow",
      80 => "rain", 81 => "rain", 82 => "rain",
      85 => "snow", 86 => "snow",
      95 => "thunderstorm", 96 => "thunderstorm", 99 => "thunderstorm"
    }.freeze

    def condition_for(code)
      WMO_CODE_TO_CONDITION[code.to_i] || "unknown"
    end
  end
end
