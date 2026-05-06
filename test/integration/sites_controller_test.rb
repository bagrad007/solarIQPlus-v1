require "test_helper"

class SitesControllerTest < ActionDispatch::IntegrationTest
  # Stub Weather::Cache so the controller spec doesn't pummel Open-Meteo and
  # doesn't depend on real network at all. SitesController exposes a
  # `weather_cache` class attr the test can swap in/out.
  STUBBED_WEATHER = {
    today: {
      date: Date.new(2026, 5, 5), peak_sun_hours: 7.0, cloud_cover_pct: 5,
      temp_high_c: 38, condition: "sunny"
    },
    tomorrow: {
      date: Date.new(2026, 5, 6), peak_sun_hours: 6.0, cloud_cover_pct: 30,
      temp_high_c: 34, condition: "partly_cloudy"
    }
  }.freeze

  class StubCache
    def fetch(latitude:, longitude:); STUBBED_WEATHER; end
  end

  setup do
    build_tenant_tree
    @site_a.update!(latitude: 33.45, longitude: -112.07, nameplate_kw: 10.0)
    @original_cache = SitesController.weather_cache
    SitesController.weather_cache = StubCache.new
  end

  teardown do
    SitesController.weather_cache = @original_cache
  end

  test "show renders the dashboard mount with the operational summary payload" do
    sign_in_as(@northwind_user)

    get site_path(@site_a)

    assert_response :success
    assert_select "[data-dashboard-mount][data-payload]"

    raw = css_select("[data-dashboard-mount]").first["data-payload"]
    payload = JSON.parse(raw)
    assert payload.key?("chart"),  "expected chart slice for the React island"
    assert payload.key?("gauges"), "expected gauges slice for the React island"
    assert payload.key?("environment"), "expected environment slice for ambient strip"
    assert payload.key?("forecast"), "forecast merged for React ambient context"
    assert payload["chart"].key?("solar_today_series")
    assert payload["chart"].key?("solar_series_by_range")
    # The import/export pie lives on the Diagnostics page now.
    assert_not payload["chart"].key?("pie"),
               "Dashboard payload must not carry the import/export pie"
  end

  test "show payload carries the SiteOperationalSummary shape" do
    sign_in_as(@northwind_user)

    get site_path(@site_a)

    payload = dashboard_payload
    %w[totals today latest chart gauges].each do |slice|
      assert payload.key?(slice), "expected payload to include #{slice} slice"
    end
    %w[lifetime_kwh ytd_kwh mtd_kwh today_kwh].each do |k|
      assert payload["totals"].key?(k), "expected totals.#{k}"
    end
    assert payload["gauges"]["dc"].key?("max_kw"), "gauges must declare a max scale"
  end

  test "show renders the forecast tiles in ERB so they display without JS" do
    sign_in_as(@northwind_user)

    get site_path(@site_a)

    assert_select "[data-forecast-tile]", minimum: 2
    assert_match(/Forecast Solar Production Today/i,    response.body)
    assert_match(/Forecast Solar Production Tomorrow/i, response.body)
    # 10 kW × 7 PSH × 0.80 PR × (1 - 0.05 × 0.6) ≈ 54.32 kWh — printed in the
    # tile so we can verify the projection ran with our stubbed weather.
    assert_match(/54\.\d+/, response.body)
    assert_match(/Daily high/i, response.body)
    assert_match(/100\.4/, response.body)
  end

  test "show degrades gracefully when the weather upstream fails" do
    failing_cache = Object.new
    def failing_cache.fetch(latitude:, longitude:); raise Weather::OpenMeteoError, "boom"; end
    SitesController.weather_cache = failing_cache

    sign_in_as(@northwind_user)

    get site_path(@site_a)

    assert_response :success
    # When weather is unavailable, the ERB falls back to an em-dash placeholder
    # in the forecast tiles rather than a number.
    assert_select "[data-forecast-tile]" do
      assert_select "[data-projected-kwh='—']", minimum: 2
    end
  end

  test "show returns 404 when the Site is hidden by RLS" do
    sign_in_as(@northwind_user)

    get site_path(@site_b)

    assert_response :not_found
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end

  def dashboard_payload
    raw = css_select("[data-dashboard-mount]").first["data-payload"]
    JSON.parse(raw)
  end
end
