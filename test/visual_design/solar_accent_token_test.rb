# frozen_string_literal: true

require "test_helper"

# Visual-system contract: the Maverick brand orange must be defined as a
# first-class design token in the Tailwind v4 @theme block, not sprinkled
# inline. This test pins both the token name and the exact hex so a future
# rebrand or tweak goes through the @theme rather than ad-hoc edits.
class SolarAccentTokenTest < ActiveSupport::TestCase
  CSS_PATH = Rails.root.join("app/assets/stylesheets/application.tailwind.css")

  test "Tailwind @theme defines --color-solar-accent at the Maverick logo orange (#F08529)" do
    css = File.read(CSS_PATH)
    assert_match(
      /--color-solar-accent:\s*#F08529\s*;/i,
      css,
      "Expected `--color-solar-accent: #F08529;` in #{CSS_PATH.relative_path_from(Rails.root)}"
    )
  end
end
