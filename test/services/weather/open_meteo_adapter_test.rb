require "test_helper"

class Weather::OpenMeteoAdapterTest < ActiveSupport::TestCase
  # Open-Meteo's daily endpoint, trimmed to just the fields we ask for.
  # `time` is two ISO dates; every parallel array carries today + tomorrow.
  HAPPY_RESPONSE = {
    "daily" => {
      "time"                    => [ "2026-05-05", "2026-05-06" ],
      "shortwave_radiation_sum" => [ 28.5, 22.1 ],
      "cloud_cover_mean"        => [ 10, 40 ],
      "temperature_2m_max"      => [ 38.2, 32.7 ],
      "weather_code"            => [ 0, 3 ]
    }
  }.freeze

  test "fetch returns today and tomorrow with parsed numeric fields" do
    adapter = Weather::OpenMeteoAdapter.new(http_client: stub_http(HAPPY_RESPONSE))

    result = adapter.fetch(latitude: 33.45, longitude: -112.07)

    today = result.fetch(:today)
    assert_equal Date.new(2026, 5, 5), today[:date]
    # 28.5 MJ/m² ÷ 3.6 = 7.92 peak-sun-hours
    assert_in_delta 7.92, today[:peak_sun_hours], 0.01
    assert_equal 10, today[:cloud_cover_pct]
    assert_equal 38, today[:temp_high_c]
    assert_equal "sunny", today[:condition]

    tomorrow = result.fetch(:tomorrow)
    assert_equal Date.new(2026, 5, 6), tomorrow[:date]
    assert_in_delta 6.14, tomorrow[:peak_sun_hours], 0.01
    assert_equal 40, tomorrow[:cloud_cover_pct]
    assert_equal 33, tomorrow[:temp_high_c]
    assert_equal "cloudy", tomorrow[:condition]
  end

  test "peak_sun_hours converts MJ per square meter into kWh per square meter" do
    # 36 MJ/m² ÷ 3.6 = 10 kWh/m² = 10 peak-sun-hours.
    response = HAPPY_RESPONSE.deep_dup
    response["daily"]["shortwave_radiation_sum"] = [ 36.0, 36.0 ]
    adapter = Weather::OpenMeteoAdapter.new(http_client: stub_http(response))

    result = adapter.fetch(latitude: 0, longitude: 0)

    assert_in_delta 10.0, result[:today][:peak_sun_hours],    0.001
    assert_in_delta 10.0, result[:tomorrow][:peak_sun_hours], 0.001
  end

  test "WMO weather codes map to human-readable conditions" do
    response = HAPPY_RESPONSE.deep_dup
    response["daily"]["weather_code"] = [ 61, 71 ]
    adapter = Weather::OpenMeteoAdapter.new(http_client: stub_http(response))

    result = adapter.fetch(latitude: 0, longitude: 0)

    assert_equal "rain", result[:today][:condition]
    assert_equal "snow", result[:tomorrow][:condition]
  end

  test "unknown weather codes default to 'unknown' rather than crashing" do
    response = HAPPY_RESPONSE.deep_dup
    response["daily"]["weather_code"] = [ 9999, -1 ]
    adapter = Weather::OpenMeteoAdapter.new(http_client: stub_http(response))

    result = adapter.fetch(latitude: 0, longitude: 0)

    assert_equal "unknown", result[:today][:condition]
    assert_equal "unknown", result[:tomorrow][:condition]
  end

  test "fetch hits the documented Open-Meteo endpoint with our query params" do
    captured_uri = nil
    http = ->(uri) {
      captured_uri = uri
      ok_response(HAPPY_RESPONSE)
    }
    Weather::OpenMeteoAdapter.new(http_client: http).fetch(latitude: 33.45, longitude: -112.07)

    assert_equal "api.open-meteo.com", captured_uri.host
    assert_equal "/v1/forecast",       captured_uri.path
    params = URI.decode_www_form(captured_uri.query).to_h
    assert_equal "33.45",   params["latitude"]
    assert_equal "-112.07", params["longitude"]
    assert_equal "2",       params["forecast_days"]
    assert_includes params["daily"], "shortwave_radiation_sum"
    assert_includes params["daily"], "weather_code"
  end

  test "non-2xx response raises Weather::OpenMeteoError" do
    failing = ->(_uri) { FakeResponse.new("503", "Service Unavailable", "") }
    adapter = Weather::OpenMeteoAdapter.new(http_client: failing)

    error = assert_raises(Weather::OpenMeteoError) do
      adapter.fetch(latitude: 0, longitude: 0)
    end
    assert_match(/503/, error.message)
  end

  private

  # Duck-typed stand-in for Net::HTTPResponse — only `code`, `message`, and
  # `body` are read by the adapter, so we don't need the real class.
  FakeResponse = Struct.new(:code, :message, :body)

  def stub_http(response_hash)
    ->(_uri) { ok_response(response_hash) }
  end

  def ok_response(payload)
    FakeResponse.new("200", "OK", payload.to_json)
  end
end
