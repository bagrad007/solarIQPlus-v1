# frozen_string_literal: true

# Pure derivation: given a Site (for nameplate_kw) and a weather hash from
# Weather::Cache / Weather::OpenMeteoAdapter, project the kWh the array is
# expected to produce today and tomorrow.
#
# PV-yield formula:
#   expected_kwh = nameplate_kw × peak_sun_hours × PERFORMANCE_RATIO × cloud_factor
#   PERFORMANCE_RATIO = 0.80
#   cloud_factor      = 1.0 - (cloud_cover_pct / 100.0) × 0.6
#
# 0.80 is the industry-typical performance ratio (DC-to-AC losses, soiling,
# wiring, temperature derate). The 0.6 cloud coefficient says full overcast
# discounts production by 60% — gentler than treating cloud cover as a hard
# multiplier so partly-cloudy days still register meaningful generation.
class SiteForecast
  PERFORMANCE_RATIO   = 0.80
  CLOUD_DISCOUNT_FACTOR = 0.6
  UNKNOWN_CONDITION   = "unknown"

  def initialize(site, weather:)
    @site    = site
    @weather = weather
  end

  def to_h
    {
      today_kwh:            project_kwh(:today),
      tomorrow_kwh:         project_kwh(:tomorrow),
      today_condition:    condition_for(:today),
      tomorrow_condition: condition_for(:tomorrow),
      today_temp_high_f:    temp_high_f(:today),
      tomorrow_temp_high_f: temp_high_f(:tomorrow)
    }
  end

  private

  def project_kwh(day)
    return nil if @site.nameplate_kw.blank?
    return nil if @site.latitude.blank? || @site.longitude.blank?
    return nil if @weather.blank?

    slice = @weather[day]
    return nil if slice.blank?

    psh         = slice[:peak_sun_hours].to_f
    cloud_pct   = slice[:cloud_cover_pct].to_f
    cloud_factor = 1.0 - (cloud_pct / 100.0) * CLOUD_DISCOUNT_FACTOR

    (@site.nameplate_kw.to_f * psh * PERFORMANCE_RATIO * cloud_factor).round(2)
  end

  def condition_for(day)
    @weather&.dig(day, :condition) || UNKNOWN_CONDITION
  end

  def temp_high_f(day)
    c = @weather&.dig(day, :temp_high_c)
    TemperatureConversion.fahrenheit_from_celsius(c)
  end
end
