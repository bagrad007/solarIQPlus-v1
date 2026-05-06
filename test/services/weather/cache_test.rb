require "test_helper"

class Weather::CacheTest < ActiveSupport::TestCase
  # A test double standing in for the OpenMeteoAdapter so we can prove caching
  # without hitting any HTTP boundary. Records every call.
  class CountingAdapter
    attr_reader :calls

    def initialize(payload:)
      @payload = payload
      @calls   = []
    end

    def fetch(latitude:, longitude:)
      @calls << [ latitude, longitude ]
      @payload
    end
  end

  setup do
    @memory_store    = ActiveSupport::Cache::MemoryStore.new
    @original_cache  = Rails.cache
    Rails.cache      = @memory_store
    @payload = {
      today:    { date: Date.new(2026, 5, 5), peak_sun_hours: 8.0, cloud_cover_pct: 5,  temp_high_c: 38, condition: "sunny" },
      tomorrow: { date: Date.new(2026, 5, 6), peak_sun_hours: 6.0, cloud_cover_pct: 40, temp_high_c: 33, condition: "cloudy" }
    }
    @adapter = CountingAdapter.new(payload: @payload)
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "first call delegates to the adapter" do
    cache = Weather::Cache.new(adapter: @adapter)

    cache.fetch(latitude: 33.45, longitude: -112.07)

    assert_equal [ [ 33.45, -112.07 ] ], @adapter.calls
  end

  test "second call within the cache window is served from Rails.cache" do
    cache = Weather::Cache.new(adapter: @adapter)

    cache.fetch(latitude: 33.45, longitude: -112.07)
    cache.fetch(latitude: 33.45, longitude: -112.07)

    assert_equal 1, @adapter.calls.length, "expected the second call to be served from the cache"
  end

  test "different lat/lon use distinct cache keys" do
    cache = Weather::Cache.new(adapter: @adapter)

    cache.fetch(latitude: 33.45, longitude: -112.07)
    cache.fetch(latitude: 47.61, longitude: -122.33)

    assert_equal 2, @adapter.calls.length, "different coordinates must miss the cache"
  end

  test "cached payload preserves the adapter's nested hash shape" do
    cache = Weather::Cache.new(adapter: @adapter)

    first  = cache.fetch(latitude: 33.45, longitude: -112.07)
    second = cache.fetch(latitude: 33.45, longitude: -112.07)

    assert_equal @payload, first
    assert_equal first, second
  end

  test "cache key namespace is stable so other code can clear it deterministically" do
    cache = Weather::Cache.new(adapter: @adapter)
    cache.fetch(latitude: 33.45, longitude: -112.07)

    assert @memory_store.exist?("weather:33.45,-112.07"),
           "expected a cache entry under the documented 'weather:<lat>,<lon>' key"
  end
end
