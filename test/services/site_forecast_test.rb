require "test_helper"

class SiteForecastTest < ActiveSupport::TestCase
  setup do
    build_tenant_tree
    @site = @site_a
    @site.update!(latitude: 33.45, longitude: -112.07, nameplate_kw: 10.0)
  end

  test "today_kwh applies the PV-yield formula at clear-sky conditions" do
    weather = weather_payload(today_psh: 7.0, today_cloud: 0)

    forecast = SiteForecast.new(@site, weather: weather).to_h

    # 10 kW × 7 PSH × 0.80 PR × (1 - 0/100 × 0.6) = 56.0 kWh
    assert_in_delta 56.0, forecast[:today_kwh], 0.01
  end

  test "cloud_cover_pct discounts the projection by up to 60%" do
    weather = weather_payload(today_psh: 5.0, today_cloud: 100)

    forecast = SiteForecast.new(@site, weather: weather).to_h

    # 10 × 5 × 0.80 × (1 - 1.0 × 0.6) = 16.0 kWh
    assert_in_delta 16.0, forecast[:today_kwh], 0.01
  end

  test "tomorrow_kwh uses the tomorrow weather slice" do
    weather = weather_payload(
      today_psh: 0.0, today_cloud: 0,
      tomorrow_psh: 6.0, tomorrow_cloud: 50
    )

    forecast = SiteForecast.new(@site, weather: weather).to_h

    # 10 × 6 × 0.80 × (1 - 0.50 × 0.6) = 33.6 kWh
    assert_in_delta 33.6, forecast[:tomorrow_kwh], 0.01
  end

  test "weather conditions are passed through unchanged for the UI" do
    weather = weather_payload(today_condition: "rain", tomorrow_condition: "sunny")

    forecast = SiteForecast.new(@site, weather: weather).to_h

    assert_equal "rain",  forecast[:today_condition]
    assert_equal "sunny", forecast[:tomorrow_condition]
    assert_in_delta 100.4, forecast[:today_temp_high_f], 0.01
    assert_in_delta 93.2, forecast[:tomorrow_temp_high_f], 0.01
  end

  test "missing latitude/longitude returns nil kWh and unknown conditions" do
    @site.update!(latitude: nil, longitude: nil)

    forecast = SiteForecast.new(@site, weather: nil).to_h

    assert_nil forecast[:today_kwh]
    assert_nil forecast[:tomorrow_kwh]
    assert_equal "unknown", forecast[:today_condition]
    assert_equal "unknown", forecast[:tomorrow_condition]
    assert_nil forecast[:today_temp_high_f]
    assert_nil forecast[:tomorrow_temp_high_f]
  end

  test "missing nameplate_kw returns nil kWh but still passes weather conditions" do
    @site.update!(nameplate_kw: nil)
    weather = weather_payload(today_condition: "cloudy")

    forecast = SiteForecast.new(@site, weather: weather).to_h

    assert_nil forecast[:today_kwh]
    assert_nil forecast[:tomorrow_kwh]
    assert_equal "cloudy", forecast[:today_condition]
  end

  private

  def weather_payload(
    today_psh: 6.0, today_cloud: 20, today_condition: "sunny",
    tomorrow_psh: 5.5, tomorrow_cloud: 30, tomorrow_condition: "partly_cloudy"
  )
    {
      today: {
        date:            Date.current,
        peak_sun_hours:  today_psh,
        cloud_cover_pct: today_cloud,
        temp_high_c:     38,
        condition:       today_condition
      },
      tomorrow: {
        date:            Date.current + 1,
        peak_sun_hours:  tomorrow_psh,
        cloud_cover_pct: tomorrow_cloud,
        temp_high_c:     34,
        condition:       tomorrow_condition
      }
    }
  end
end
