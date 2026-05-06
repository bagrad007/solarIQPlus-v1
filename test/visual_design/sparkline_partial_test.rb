# frozen_string_literal: true

require "test_helper"

# The sparkline is the only place we paint orange under a curve. Stroke stays
# navy (legibility on light surfaces); the area-fill carries the brand accent.
# These two assertions together pin the contract: orange in, primary-blue
# area-fill out.
class SparklinePartialTest < ActionView::TestCase
  test "area-fill polygon uses --color-solar-accent (brand orange)" do
    render partial: "shared/sparkline", locals: { values: [1, 3, 2, 5, 4] }

    assert_match(
      %r{<polygon[^>]*\bfill="var\(--color-solar-accent\)"},
      rendered,
      "Sparkline area-fill must use var(--color-solar-accent), not the old primary-blue token"
    )
    refute_match(
      %r{<polygon[^>]*\bfill="var\(--color-primary-fixed\)"},
      rendered,
      "Sparkline area-fill should no longer use --color-primary-fixed (light blue)"
    )
  end

  test "stroke (curve line) stays on --color-primary navy" do
    render partial: "shared/sparkline", locals: { values: [1, 3, 2, 5, 4] }

    assert_match(
      %r{<polyline[^>]*\bstroke="var\(--color-primary\)"},
      rendered,
      "Sparkline stroke must remain navy (--color-primary); only the under-curve fill is orange"
    )
  end
end
