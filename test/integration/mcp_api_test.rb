# frozen_string_literal: true

require "test_helper"

class McpApiTest < ActionDispatch::IntegrationTest
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
    @token = "test-mcp-token-exactly-32chars!"
    @original_cache = SitesController.weather_cache
    SitesController.weather_cache = StubCache.new
    @prev_token = ENV["SOLAR_IQ_MCP_TOKEN"]
    @prev_email = ENV["SOLAR_IQ_MCP_ACTING_USER_EMAIL"]
    ENV["SOLAR_IQ_MCP_TOKEN"] = @token
    ENV["SOLAR_IQ_MCP_ACTING_USER_EMAIL"] = @northwind_user.email
  end

  teardown do
    SitesController.weather_cache = @original_cache
    ENV["SOLAR_IQ_MCP_TOKEN"] = @prev_token
    ENV["SOLAR_IQ_MCP_ACTING_USER_EMAIL"] = @prev_email
  end

  test "rejects missing bearer token" do
    get "/mcp/v1/sites"
    assert_response :unauthorized
  end

  test "rejects wrong bearer token" do
    get "/mcp/v1/sites", headers: { "Authorization" => "Bearer wrong-token" }
    assert_response :unauthorized
  end

  test "returns 503 when MCP env is unset" do
    ENV.delete("SOLAR_IQ_MCP_TOKEN")
    get "/mcp/v1/sites", headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :service_unavailable
  ensure
    ENV["SOLAR_IQ_MCP_TOKEN"] = @token
  end

  test "lists sites visible to the acting user" do
    get "/mcp/v1/sites", headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["sites"].size
    assert_equal @site_a.id, body["sites"].first["id"]
    assert_equal "Northwind Roof", body["sites"].first["name"]
  end

  test "show returns operational summary and forecast" do
    get "/mcp/v1/sites/#{@site_a.id}", headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Northwind Roof", body.dig("site", "name")
    assert body["operational_summary"].key?("totals")
    assert body["forecast"].is_a?(Hash)
    assert_in_delta 100.4, body["forecast"]["today_temp_high_f"], 0.01
    assert_in_delta 93.2, body["forecast"]["tomorrow_temp_high_f"], 0.01
  end

  test "diagnostics returns SiteDiagnostics payload" do
    get "/mcp/v1/sites/#{@site_a.id}/diagnostics", headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @site_a.id, body.dig("site", "id")
    assert body.key?("today")
    assert body.key?("import_export_series")
  end
end
