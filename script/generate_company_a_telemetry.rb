#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Generates `config/data/company_a_telemetry.json`, the static demo dataset
# behind the AI Energy Analyst widget. The output is deterministic (seeded
# RNG + fixed reference date) so re-running this script produces the exact
# same file — keep it that way so the committed JSON is meaningful in diffs.
#
# Run:  ruby script/generate_company_a_telemetry.rb
#
# This script intentionally has zero Rails dependencies. It is *only* a
# build-time helper for the demo dataset; the runtime path reads the JSON
# directly via `EnergyAnalyst::TelemetryRepository`.

require "json"
require "date"
require "fileutils"
require "digest"

# Reference "today" used for the dataset. Pinned so the JSON is reproducible
# regardless of when the script is run, and so the analyst copy that talks
# about "the last 30 days" lines up with stable dates in the file.
REFERENCE_DATE = Date.new(2026, 5, 1)
DAYS = 90

OUT_PATH = File.expand_path("../config/data/company_a_telemetry.json", __dir__)

# Seeded PRNG — same seed in, same numbers out. Different for each panel so
# panels don't all fluctuate identically; the seed factors in the panel id.
def panel_rng(panel_id)
  Random.new(Digest::SHA256.hexdigest(panel_id).to_i(16) & 0xFFFFFFFF)
end

# Seasonal/weather/wear modulation. We model "expected" energy as a smooth
# curve and "actual" as expected * (weather_factor) * (panel_health_factor),
# minus offline windows. That gives the analyst real numbers to talk about.
def seasonal_irradiance(date)
  # Simple sinusoid centered on solar noon energy in kWh/m^2/day at mid-lat.
  doy = date.yday
  base = 5.0 + 1.6 * Math.sin(((doy - 80) / 365.0) * 2 * Math::PI)
  base.round(3)
end

WEATHER_PROFILES = [
  { code: "clear",         factor: 1.00, label: "Clear" },
  { code: "partly_cloudy", factor: 0.88, label: "Partly cloudy" },
  { code: "cloudy",        factor: 0.65, label: "Cloudy" },
  { code: "overcast",      factor: 0.45, label: "Overcast" },
  { code: "storm",         factor: 0.25, label: "Storm" },
  { code: "rain",          factor: 0.55, label: "Rain" }
].freeze

# Pre-compute weather per (site, date) so all panels in a site share weather.
def weather_for(site_id, date)
  rng = Random.new(Digest::SHA256.hexdigest("#{site_id}|#{date}").to_i(16) & 0xFFFFFFFF)
  roll = rng.rand
  case
  when roll < 0.55 then WEATHER_PROFILES[0]
  when roll < 0.78 then WEATHER_PROFILES[1]
  when roll < 0.90 then WEATHER_PROFILES[2]
  when roll < 0.96 then WEATHER_PROFILES[3]
  when roll < 0.99 then WEATHER_PROFILES[5]
  else WEATHER_PROFILES[4]
  end
end

# Anomaly windows — relative offsets from REFERENCE_DATE. The mock adapter
# leans on these dates verbatim ("beginning approximately 18 days ago…")
# so they should stay stable.
ANOMALY_PLAN = {
  thermal_degradation: {
    site_id: "site_alpha", array_id: "array_a", panel_label: "A3",
    starts_days_ago: 18, severity: 0.18,
    description: "Persistent thermal degradation on string A3."
  },
  inverter_offline: {
    site_id: "site_alpha", inverter_id: "INV-2",
    starts_days_ago: 25, duration_days: 2,
    affected_array_id: "array_b",
    description: "Inverter INV-2 offline; array B isolated."
  },
  storm_voltage_dip: {
    site_id: "site_alpha", array_id: "array_b",
    on_days_ago: 12, severity: 0.35,
    description: "Storm-related voltage dip on Site Alpha array B."
  },
  soiling_drift: {
    site_id: "site_bravo", array_id: nil,
    starts_days_ago: 45, severity_per_day: 0.0035, max_severity: 0.16,
    description: "Gradual soiling-style PR drift on Site Bravo."
  }
}.freeze

PANELS_PER_ARRAY = 6

# Static fleet definition. Names deliberately read like an industrial site,
# but the customer-facing string lives in `company_name`.
FLEET = {
  company_id: "company_a",
  company_name: "Company A — Industrial Solar",
  region: "Southwest US",
  fleet_capacity_kw: 1_140,
  sites: [
    {
      id: "site_alpha", name: "Site Alpha", location: "Phoenix, AZ",
      capacity_kw: 540, commissioned_on: "2022-04-12",
      arrays: [
        { id: "array_a", name: "Array A", inverter_id: "INV-1", azimuth_deg: 180, tilt_deg: 25 },
        { id: "array_b", name: "Array B", inverter_id: "INV-2", azimuth_deg: 195, tilt_deg: 25 }
      ]
    },
    {
      id: "site_bravo", name: "Site Bravo", location: "Las Vegas, NV",
      capacity_kw: 360, commissioned_on: "2023-09-02",
      arrays: [
        { id: "array_a", name: "Array A", inverter_id: "INV-3", azimuth_deg: 175, tilt_deg: 22 },
        { id: "array_b", name: "Array B", inverter_id: "INV-4", azimuth_deg: 185, tilt_deg: 22 }
      ]
    },
    {
      id: "site_charlie", name: "Site Charlie", location: "Albuquerque, NM",
      capacity_kw: 240, commissioned_on: "2024-02-18",
      arrays: [
        { id: "array_a", name: "Array A", inverter_id: "INV-5", azimuth_deg: 180, tilt_deg: 28 },
        { id: "array_b", name: "Array B", inverter_id: "INV-6", azimuth_deg: 180, tilt_deg: 28 }
      ]
    }
  ]
}.freeze

def panel_label(array_letter, idx)
  "#{array_letter.upcase}#{idx + 1}"
end

def panel_id(site_id, array_id, idx)
  "#{site_id}_#{array_id}_p#{idx + 1}"
end

# Per-panel nameplate kW (very small — represents one string segment, not
# the whole array). Panel-level energy * panels_per_array * 2 arrays
# approximates the array-level capacity.
def panel_capacity_kw(site_capacity_kw)
  (site_capacity_kw.to_f / (2 * PANELS_PER_ARRAY)).round(2)
end

def site_anomalies_for(site)
  ANOMALY_PLAN.select { |_, plan| plan[:site_id] == site[:id] }
end

# Returns a multiplier in [0, 1] for any (panel, date) combination,
# accounting for the planned anomalies that target this panel/array.
def health_factor(site, array, panel_idx, date, days_ago)
  factor = 1.0
  panel_label_str = panel_label(array[:id].split("_").last, panel_idx)

  # Thermal degradation on string A3 of site_alpha.
  td = ANOMALY_PLAN[:thermal_degradation]
  if site[:id] == td[:site_id] && array[:id] == td[:array_id] && panel_label_str == td[:panel_label]
    days_active = td[:starts_days_ago] - days_ago
    if days_active.positive?
      ramp = [days_active / 14.0, 1.0].min
      factor *= (1.0 - td[:severity] * ramp)
    end
  end

  # Inverter outage isolates an entire array for a duration window.
  io = ANOMALY_PLAN[:inverter_offline]
  if site[:id] == io[:site_id] && array[:id] == io[:affected_array_id]
    if days_ago <= io[:starts_days_ago] && days_ago > (io[:starts_days_ago] - io[:duration_days])
      factor = 0.0
    end
  end

  # Storm voltage dip — single-day partial loss on Site Alpha array B.
  sv = ANOMALY_PLAN[:storm_voltage_dip]
  if site[:id] == sv[:site_id] && array[:id] == sv[:array_id] && days_ago == sv[:on_days_ago]
    factor *= (1.0 - sv[:severity])
  end

  # Soiling drift — fleet-wide on Site Bravo, ramps with days active.
  sd = ANOMALY_PLAN[:soiling_drift]
  if site[:id] == sd[:site_id]
    days_active = sd[:starts_days_ago] - days_ago
    if days_active.positive?
      drift = [days_active * sd[:severity_per_day], sd[:max_severity]].min
      factor *= (1.0 - drift)
    end
  end

  factor
end

def fault_codes_for(site, array, panel_label_str, days_ago)
  codes = []
  td = ANOMALY_PLAN[:thermal_degradation]
  if site[:id] == td[:site_id] && array[:id] == td[:array_id] && panel_label_str == td[:panel_label]
    days_active = td[:starts_days_ago] - days_ago
    if days_active.positive? && days_active >= 7
      codes << "THERMAL_HOTSPOT"
    end
  end

  io = ANOMALY_PLAN[:inverter_offline]
  if site[:id] == io[:site_id] && array[:id] == io[:affected_array_id]
    if days_ago <= io[:starts_days_ago] && days_ago > (io[:starts_days_ago] - io[:duration_days])
      codes << "INVERTER_OFFLINE"
    end
  end

  sv = ANOMALY_PLAN[:storm_voltage_dip]
  if site[:id] == sv[:site_id] && array[:id] == sv[:array_id] && days_ago == sv[:on_days_ago]
    codes << "VOLTAGE_DIP"
  end

  codes
end

def maintenance_events_for(site, array, panel_label_str, days_ago)
  events = []
  td = ANOMALY_PLAN[:thermal_degradation]
  if site[:id] == td[:site_id] && array[:id] == td[:array_id] && panel_label_str == td[:panel_label] && days_ago == 6
    events << { type: "inspection", note: "Field tech logged elevated cell temperature on string A3." }
  end

  io = ANOMALY_PLAN[:inverter_offline]
  if site[:id] == io[:site_id] && days_ago == (io[:starts_days_ago] - io[:duration_days])
    events << { type: "repair", note: "Inverter INV-2 firmware reset; array B brought back online." }
  end

  sd = ANOMALY_PLAN[:soiling_drift]
  if site[:id] == sd[:site_id] && days_ago == 30
    events << { type: "scheduled", note: "Quarterly cleaning skipped due to access constraints." }
  end

  events
end

def inverter_status_for(site, array, days_ago)
  io = ANOMALY_PLAN[:inverter_offline]
  if site[:id] == io[:site_id] && array[:inverter_id] == io[:inverter_id]
    if days_ago <= io[:starts_days_ago] && days_ago > (io[:starts_days_ago] - io[:duration_days])
      return "offline"
    end
  end
  "online"
end

def round2(value)
  value.to_f.round(2)
end

panels_payload = FLEET[:sites].map do |site|
  capacity_per_panel = panel_capacity_kw(site[:capacity_kw])

  arrays_payload = site[:arrays].map do |array|
    panels_payload = (0...PANELS_PER_ARRAY).map do |panel_idx|
      pid = panel_id(site[:id], array[:id], panel_idx)
      label = panel_label(array[:id].split("_").last, panel_idx)
      rng = panel_rng(pid)

      readings = (0...DAYS).map do |i|
        days_ago = (DAYS - 1) - i
        date = REFERENCE_DATE - days_ago
        weather = weather_for(site[:id], date)
        irradiance = (seasonal_irradiance(date) * weather[:factor]).round(3)
        health = health_factor(site, array, panel_idx, date, days_ago)
        jitter = 1.0 + ((rng.rand - 0.5) * 0.04)

        # "Expected" is the seasonal/weather curve only.
        expected_kwh = round2(capacity_per_panel * 4.5 * (weather[:factor] / 1.0))
        # "Daily" is expected * health * tiny jitter; floor near zero.
        daily_kwh = round2([expected_kwh * health * jitter, 0].max)
        pr = expected_kwh.zero? ? 0.0 : (daily_kwh / expected_kwh).round(3)

        # Synthesize point-in-time readings at solar noon (so timestamps look
        # like a snapshot from the device at peak production).
        noon = Time.utc(date.year, date.month, date.day, 12, 0, 0).iso8601
        # Voltage/current scale with health and weather; temp rises with poor
        # cooling and thermal hotspots.
        v = (38.0 + (rng.rand - 0.5) * 1.5) * (health > 0 ? 1.0 : 0.0)
        i_amp = (capacity_per_panel * 0.55) * (weather[:factor] * health) + (rng.rand - 0.5) * 0.2
        power_kw = round2(v * i_amp / 1000.0)
        ambient = (22 + (irradiance - 4) * 6 + (rng.rand - 0.5) * 3).round(1)
        temp_bonus =
          if site[:id] == ANOMALY_PLAN[:thermal_degradation][:site_id] &&
             array[:id] == ANOMALY_PLAN[:thermal_degradation][:array_id] &&
             label == ANOMALY_PLAN[:thermal_degradation][:panel_label] &&
             (ANOMALY_PLAN[:thermal_degradation][:starts_days_ago] - days_ago).positive?
            12.0
          else
            0.0
          end
        cell_temp = (ambient + 18 + temp_bonus + (rng.rand - 0.5) * 2).round(1)
        anomaly_score = (1.0 - pr).clamp(0.0, 1.0).round(3)

        {
          date: date.iso8601,
          timestamp: noon,
          voltage: round2(v),
          current: round2(i_amp),
          power_output: power_kw,
          temperature: cell_temp,
          irradiance: irradiance,
          efficiency: pr,
          inverter_status: inverter_status_for(site, array, days_ago),
          fault_codes: fault_codes_for(site, array, label, days_ago),
          maintenance_events: maintenance_events_for(site, array, label, days_ago),
          weather_conditions: { code: weather[:code], label: weather[:label], factor: weather[:factor] },
          daily_energy_kwh: daily_kwh,
          expected_energy_kwh: expected_kwh,
          performance_ratio: pr,
          anomaly_score: anomaly_score
        }
      end

      {
        id: pid,
        label: label,
        nameplate_kw: capacity_per_panel,
        daily_readings: readings
      }
    end

    {
      id: array[:id],
      name: array[:name],
      inverter_id: array[:inverter_id],
      azimuth_deg: array[:azimuth_deg],
      tilt_deg: array[:tilt_deg],
      panels: panels_payload
    }
  end

  {
    id: site[:id],
    name: site[:name],
    location: site[:location],
    capacity_kw: site[:capacity_kw],
    commissioned_on: site[:commissioned_on],
    arrays: arrays_payload
  }
end

# Pre-rolled "narrative" event log — pulled from ANOMALY_PLAN so the analyst
# can quote concrete dates without having to scan the daily readings on every
# request.
event_log = [
  {
    id: "evt_thermal_a3",
    site_id: "site_alpha", array_id: "array_a", panel_label: "A3",
    kind: "degradation",
    started_on: (REFERENCE_DATE - ANOMALY_PLAN[:thermal_degradation][:starts_days_ago]).iso8601,
    severity: "moderate",
    description: ANOMALY_PLAN[:thermal_degradation][:description]
  },
  {
    id: "evt_inverter_offline",
    site_id: "site_alpha", array_id: "array_b", inverter_id: "INV-2",
    kind: "outage",
    started_on: (REFERENCE_DATE - ANOMALY_PLAN[:inverter_offline][:starts_days_ago]).iso8601,
    ended_on: (REFERENCE_DATE - (ANOMALY_PLAN[:inverter_offline][:starts_days_ago] -
                                  ANOMALY_PLAN[:inverter_offline][:duration_days])).iso8601,
    severity: "critical",
    description: ANOMALY_PLAN[:inverter_offline][:description]
  },
  {
    id: "evt_storm_voltage",
    site_id: "site_alpha", array_id: "array_b",
    kind: "weather",
    started_on: (REFERENCE_DATE - ANOMALY_PLAN[:storm_voltage_dip][:on_days_ago]).iso8601,
    severity: "minor",
    description: ANOMALY_PLAN[:storm_voltage_dip][:description]
  },
  {
    id: "evt_soiling_drift",
    site_id: "site_bravo",
    kind: "soiling",
    started_on: (REFERENCE_DATE - ANOMALY_PLAN[:soiling_drift][:starts_days_ago]).iso8601,
    severity: "moderate",
    description: ANOMALY_PLAN[:soiling_drift][:description]
  }
]

payload = {
  generated_at: REFERENCE_DATE.iso8601,
  reference_date: REFERENCE_DATE.iso8601,
  days_covered: DAYS,
  company_id: FLEET[:company_id],
  company_name: FLEET[:company_name],
  region: FLEET[:region],
  fleet_capacity_kw: FLEET[:fleet_capacity_kw],
  sites: panels_payload,
  events: event_log
}

FileUtils.mkdir_p(File.dirname(OUT_PATH))
# Compact JSON: this file is ~2-3x smaller than pretty-printed and still
# valid for `JSON.parse`. The script is the human-readable source of truth;
# inspect generated values via `bin/rails runner 'pp JSON.parse(...)'`.
File.write(OUT_PATH, JSON.generate(payload))
puts "Wrote #{OUT_PATH} (#{File.size(OUT_PATH)} bytes)"
