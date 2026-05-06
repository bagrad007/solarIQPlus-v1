# frozen_string_literal: true

require "test_helper"

# The forecast tile is the most "solar-domain" surface in the app — its icon
# IS a sun (or weather variant deciding how much sun). Painting that icon in
# the brand-orange accent ties it to the logo without changing chrome.
#
# We test all weather conditions (including "unknown") to guarantee the
# accent is consistently applied — not just when the sun is shining.
class ForecastTilePartialTest < ActionView::TestCase
  CONDITIONS = %w[sunny partly_cloudy cloudy foggy rain snow thunderstorm unknown].freeze

  CONDITIONS.each do |condition|
    test "weather icon for `#{condition}` is painted with text-solar-accent (brand orange)" do
      render partial: "sites/forecast_tile",
             locals: {
               label: "Forecast Solar Production Today",
               projected_kwh: 42.0,
               condition: condition
             }

      assert_select "span.material-symbols-outlined.text-solar-accent", count: 1 do
        assert_select "*", text: /\S+/ # icon name (`wb_sunny`, `cloud`, etc.)
      end
    end
  end

  test "the kWh display value stays text-primary (navy) — only the icon is orange" do
    render partial: "sites/forecast_tile",
           locals: {
             label: "Forecast Solar Production Tomorrow",
             projected_kwh: 17.5,
             condition: "sunny"
           }

    assert_select "div.text-primary", text: /17\.5/
  end
end
