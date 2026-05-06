# frozen_string_literal: true

require "test_helper"

class TemperatureConversionTest < ActiveSupport::TestCase
  test "fahrenheit_from_celsius converts water freeze and boil" do
    assert_in_delta 32.0, TemperatureConversion.fahrenheit_from_celsius(0), 0.01
    assert_in_delta 212.0, TemperatureConversion.fahrenheit_from_celsius(100), 0.01
  end

  test "fahrenheit_from_celsius rounds to one decimal" do
    assert_in_delta 100.4, TemperatureConversion.fahrenheit_from_celsius(38), 0.01
  end

  test "fahrenheit_from_celsius returns nil for nil input" do
    assert_nil TemperatureConversion.fahrenheit_from_celsius(nil)
  end
end
