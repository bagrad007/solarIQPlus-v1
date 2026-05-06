# frozen_string_literal: true

# Celsius values from telemetry and weather APIs are the canonical storage;
# convert at presentation boundaries for Fahrenheit-first UI.
module TemperatureConversion
  module_function

  def fahrenheit_from_celsius(degrees_c)
    return nil if degrees_c.nil?

    c = degrees_c.to_f
    return nil if c.nan?

    (c * 9.0 / 5.0 + 32).round(1)
  end
end
