require "test_helper"

class DiagnosticsControllerTest < ActionDispatch::IntegrationTest
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

  class StubWeatherCache
    def fetch(latitude:, longitude:); STUBBED_WEATHER; end
  end

  setup { build_tenant_tree }

  test "single-site Customer lands directly on their Site's diagnostics" do
    sign_in_as(@northwind_user)

    get diagnostics_path

    assert_redirected_to site_diagnostics_path(@site_a)
  end

  test "multi-site Customer sees the Site picker" do
    Site.create!(organization: @northwind, name: "Northwind Plant B", polling_interval_seconds: 30)
    sign_in_as(@northwind_user)

    get diagnostics_path

    assert_response :success
    assert_select "h1", text: "Diagnostics"
    assert_select "a[href=?]", site_diagnostics_path(@site_a)
  end

  test "Customer can see diagnostics for their own Site" do
    sign_in_as(@northwind_user)

    get site_diagnostics_path(@site_a)

    assert_response :success
    assert_select "[data-diagnostics-mount][data-payload]"
  end

  test "Customer cannot see another tenant's Site (RLS hides the row, 404)" do
    sign_in_as(@northwind_user)

    get site_diagnostics_path(@site_b)

    assert_response :not_found
  end

  test "Partner can see diagnostics for one of their Customer's Sites" do
    sign_in_as(@acme_user)

    get site_diagnostics_path(@site_a)

    assert_response :success
    assert_select "[data-diagnostics-mount][data-payload]"
  end

  test "Partner /diagnostics shows a Site picker across their Customers' Sites" do
    fabrikam_site = Site.create!(organization: @fabrikam, name: "Fabrikam Array", polling_interval_seconds: 30)
    sign_in_as(@acme_user)

    get diagnostics_path

    assert_response :success
    assert_select "h1", text: "Diagnostics"
    assert_select "a[href=?]", site_diagnostics_path(@site_a)
    assert_select "a[href=?]", site_diagnostics_path(fabrikam_site)
    assert_select "a[href=?]", site_diagnostics_path(@site_b), count: 0
  end

  test "Maverick can see diagnostics for any Site" do
    sign_in_as(@maverick_admin)

    get site_diagnostics_path(@site_b)

    assert_response :success
    assert_select "[data-diagnostics-mount][data-payload]"
  end

  test "Maverick /diagnostics shows a Site picker across every Site" do
    sign_in_as(@maverick_admin)

    get diagnostics_path

    assert_response :success
    assert_select "h1", text: "Diagnostics"
    assert_select "a[href=?]", site_diagnostics_path(@site_a)
    assert_select "a[href=?]", site_diagnostics_path(@site_b)
  end

  test "show payload carries the SiteDiagnostics shape" do
    sign_in_as(@northwind_user)

    get site_diagnostics_path(@site_a)

    raw = css_select("[data-diagnostics-mount]").first["data-payload"]
    payload = JSON.parse(raw)

    assert_equal @site_a.id, payload["site"]["id"]
    assert payload.key?("today")
    assert payload.key?("last_7_days")
    assert payload.key?("import_export_series")
    assert payload.key?("solar_7d_series")
    assert_equal 7, payload["solar_7d_series"].length
  end

  test "show renders forecast tiles and open cases strip when weather is available" do
    orig_cache = SitesController.weather_cache
    SitesController.weather_cache = StubWeatherCache.new
    @site_a.update!(latitude: 33.45, longitude: -112.07, nameplate_kw: 10.0)
    sign_in_as(@northwind_user)

    get site_diagnostics_path(@site_a)

    assert_response :success
    assert_select "[data-forecast-tile]", count: 2
    assert_match(/Open cases on this site/i, response.body)
  ensure
    SitesController.weather_cache = orig_cache
    @site_a.update_columns(latitude: nil, longitude: nil, nameplate_kw: nil)
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
