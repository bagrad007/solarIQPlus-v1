# SolarIQ+ demo tree.
#
# 1 Maverick / 2 Partners (Paradise + Carports with distinct logos) / 4 Customers /
# 8 Sites + 30 days of synthetic telemetry. Seeds at least one site whose
# last 24h of readings produce 1 critical and 2 warn rows so dashboard alarm
# rollups demo correctly. Seeds 2 sample cases (one open, one escalated).
#
# Idempotent: re-runs upsert by deterministic id.

require "securerandom"

PASSWORD = "password"

def make_id(seed)
  base = Digest::SHA256.hexdigest(seed)
  "#{base[0,8]}-#{base[8,4]}-4#{base[12,3]}-8#{base[15,3]}-#{base[18,12]}"
end

ActiveRecord::Base.transaction do
  # Effective Logo URLs are tenant content; we ship Partner logos as static
  # assets under public/branding/. Maverick keeps a placehold.co URL until a
  # real platform mark is supplied. The `find_or_create_by!` block runs only
  # on insert, so we follow each org with an explicit branding_config update
  # to keep re-seeds (`bin/rails db:seed` against an existing dev DB) honest.
  maverick = Organization.find_or_create_by!(id: make_id("maverick")) do |o|
    o.org_type = "maverick"
    o.name     = "Maverick Dynamics"
    o.parent_id = nil
    o.branding_config = { "logo_url" => "https://placehold.co/180x40/001F51/ffffff?text=Maverick" }
  end
  maverick.update!(branding_config: { "logo_url" => "https://placehold.co/180x40/001F51/ffffff?text=Maverick" })

  paradise = Organization.find_or_create_by!(id: make_id("paradise")) do |o|
    o.org_type  = "partner"
    o.name      = "Paradise Energy Solutions"
    o.parent_id = maverick.id
    o.branding_config = { "logo_url" => "/branding/paradise.png" }
  end
  paradise.update!(branding_config: { "logo_url" => "/branding/paradise.png" })

  carports = Organization.find_or_create_by!(id: make_id("carports")) do |o|
    o.org_type  = "partner"
    o.name      = "Solar Carports"
    o.parent_id = maverick.id
    o.branding_config = { "logo_url" => "/branding/carports.png" }
  end
  carports.update!(branding_config: { "logo_url" => "/branding/carports.png" })

  customers = {}
  [
    { key: "goose",       name: "Goose Manufacturing",     parent: paradise },
    { key: "kiwi",        name: "Kiwi Co",                 parent: paradise },
    { key: "murtle",      name: "Murtle Beach Co",         parent: carports },
    { key: "crow",        name: "Crow Kay LLC",            parent: carports }
  ].each do |attrs|
    customers[attrs[:key]] = Organization.find_or_create_by!(id: make_id("cust-#{attrs[:key]}")) do |o|
      o.org_type  = "customer"
      o.name      = attrs[:name]
      o.parent_id = attrs[:parent].id
    end
  end

  user_specs = [
    { key: "maverick-admin", org: maverick,             role: "maverick_admin", email: "admin@maverick.example",  name: "Maverick Admin" },
    { key: "paradise-user",  org: paradise,             role: "partner_user",   email: "ops@paradise.example",    name: "Alex (Paradise Ops)" },
    { key: "carports-user",  org: carports,             role: "partner_user",   email: "ops@carports.example",    name: "Beck (Carports Ops)" },
    { key: "goose-user",     org: customers["goose"],     role: "customer_user", email: "site@goose.example",     name: "Nora (Goose)" },
    { key: "kiwi-user",      org: customers["kiwi"],      role: "customer_user", email: "site@kiwi.example",      name: "Finn (Kiwi)" },
    { key: "murtle-user",    org: customers["murtle"],    role: "customer_user", email: "site@murtle.example",    name: "Casey (Murtle)" },
    { key: "crow-user",      org: customers["crow"],      role: "customer_user", email: "site@crow.example",      name: "Tara (Crow)" }
  ]

  users = {}
  user_specs.each do |spec|
    user = User.find_or_create_by!(id: make_id("user-#{spec[:key]}")) do |u|
      u.organization_id = spec[:org].id
      u.role            = spec[:role]
      u.email           = spec[:email]
      u.name            = spec[:name]
      u.password        = PASSWORD
    end
    user.update!(password: PASSWORD, password_confirmation: PASSWORD)
    users[spec[:key]] = user
  end

  # All demo sites geo-coded to Phoenix, AZ for the Open-Meteo PV-yield
  # forecast. nameplate_kw bounds the Dashboard generation gauges and the
  # forecast formula. Sized roughly by site type:
  #   rooftop      ≈ 8 kW
  #   solar array  ≈ 50 kW
  #   warehouse    ≈ 100 kW
  #   pilot        ≈ 25 kW
  #   plant / logistics / mfg / cold storage ≈ 250 kW
  PHOENIX_LAT = 33.45
  PHOENIX_LON = -112.07

  site_specs = [
    { key: "goose-roof-1",    org: customers["goose"],    name: "Goose HQ Rooftop", polling: 30,
      gateway: "10.0.10.5", critical_count: 1, warn_count: 2, nameplate_kw: 8 },
    { key: "goose-roof-2",    org: customers["goose"],    name: "Goose Plant B", polling: 30,
      gateway: "10.0.10.6", critical_count: 0, warn_count: 0, nameplate_kw: 250 },
    { key: "kiwi-array-1",    org: customers["kiwi"],     name: "Kiwi Solar Array", polling: 60,
      gateway: "10.0.20.5", critical_count: 0, warn_count: 1, nameplate_kw: 50 },
    { key: "kiwi-array-2",    org: customers["kiwi"],     name: "Kiwi Logistics Park", polling: 60,
      gateway: "10.0.20.6", critical_count: 0, warn_count: 0, nameplate_kw: 250 },
    { key: "murtle-warehouse", org: customers["murtle"],  name: "Murtle Warehouse", polling: 30,
      gateway: "10.0.30.5", critical_count: 0, warn_count: 0, nameplate_kw: 100 },
    { key: "murtle-cold-store", org: customers["murtle"], name: "Murtle Cold Storage", polling: 30,
      gateway: "10.0.30.6", critical_count: 0, warn_count: 0, nameplate_kw: 250 },
    { key: "crow-mfg-1",      org: customers["crow"],     name: "Crow Mfg Line 1", polling: 30,
      gateway: "10.0.40.5", critical_count: 0, warn_count: 0, nameplate_kw: 250 },
    { key: "crow-rdp",        org: customers["crow"],     name: "Crow R&D Pilot", polling: 60,
      gateway: "10.0.40.6", critical_count: 0, warn_count: 0, nameplate_kw: 25 }
  ]

  sites = {}
  site_specs.each do |spec|
    sites[spec[:key]] = Site.find_or_create_by!(id: make_id("site-#{spec[:key]}")) do |s|
      s.organization_id = spec[:org].id
      s.name = spec[:name]
      s.gateway_ip = spec[:gateway]
      s.polling_interval_seconds = spec[:polling]
      s.latitude     = PHOENIX_LAT
      s.longitude    = PHOENIX_LON
      s.nameplate_kw = spec[:nameplate_kw]
    end
    sites[spec[:key]].update!(
      latitude:     PHOENIX_LAT,
      longitude:    PHOENIX_LON,
      nameplate_kw: spec[:nameplate_kw]
    )
  end

  cutoff = 30.days.ago
  now    = Time.current
  demo_site_ids = sites.values.map(&:id)
  Telemetry.where(site_id: demo_site_ids).where(recorded_at: cutoff..).delete_all

  # AC mains voltage by site scale: residential split-phase ~240V,
  # commercial / industrial three-phase ~415V.
  ac_voltage_for = ->(nameplate_kw) { nameplate_kw < 25 ? 240 : 415 }

  site_specs.each do |spec|
    site = sites[spec[:key]]
    interval = spec[:polling] >= 60 ? 1.hour : 15.minutes
    scale = spec[:nameplate_kw] / 100.0   # base curve was sized for ~100 kW
    ac_voltage = ac_voltage_for.call(spec[:nameplate_kw])

    cursor = cutoff
    rows   = []
    while cursor < now - 24.hours
      # Solar can't be negative; the diurnal sine curve dips below zero at
      # night, so clamp at 0 to honor the Telemetry contract (power_kw >= 0).
      power = [ (50 + 100 * Math.sin((cursor.to_i / 86_400.0) * 2 * Math::PI) + rand(-10..10)) * scale, 0 ].max
      load_kw = (30 + 40 * Math.sin(((cursor.to_i / 86_400.0) * 2 * Math::PI) + (Math::PI / 4)).abs + rand(-8..8)) * scale
      ambient = rand(15..38)
      string_voltage = rand(380..420)
      dc_power_kw = power * 1.05
      rows << {
        site_id: site.id,
        organization_id: site.organization_id,
        org_path: site.org_path,
        recorded_at: cursor,
        metric_payload: {
          "power_kw" => power.round(2),
          "capacity_factor" => ((power.abs / spec[:nameplate_kw]).clamp(0, 1)).round(3),
          "string_voltage" => string_voltage,
          "ambient_temp_c" => ambient,
          "grid_flow_kw" => (power - load_kw).round(2),
          "inverter_temp_c" => (ambient + rand(10..25)).clamp(15, 75),
          "inverter_status" => "online",
          "dc_power_kw" => dc_power_kw.round(2),
          "dc_amps" => (dc_power_kw * 1000 / string_voltage).round(2),
          "ac_voltage" => ac_voltage,
          "ac_amps" => (power.abs * 1000 / ac_voltage).round(2)
        },
        alarm_state: "normal"
      }
      cursor += interval
    end

    last_24h = []
    cursor   = now - 24.hours
    while cursor < now
      last_24h << cursor
      cursor += interval
    end

    critical_indexes = last_24h.last(spec[:critical_count]).map.with_index { |t, _| last_24h.index(t) }
    warn_indexes     = last_24h.first(spec[:warn_count]).map.with_index { |t, _| last_24h.index(t) }

    last_24h.each_with_index do |t, i|
      state =
        if critical_indexes.include?(i)
          "critical"
        elsif warn_indexes.include?(i)
          "warn"
        else
          "normal"
        end

      power = [ (50 + 100 * Math.sin((t.to_i / 86_400.0) * 2 * Math::PI) + rand(-10..10)) * scale, 0 ].max
      load_kw = (30 + 40 * Math.sin(((t.to_i / 86_400.0) * 2 * Math::PI) + (Math::PI / 4)).abs + rand(-8..8)) * scale
      ambient = rand(15..38)
      inverter_bump = state == "critical" ? rand(30..40) : rand(10..25)
      string_voltage = rand(380..420)
      dc_power_kw = power * 1.05
      rows << {
        site_id: site.id,
        organization_id: site.organization_id,
        org_path: site.org_path,
        recorded_at: t,
        metric_payload: {
          "power_kw" => power.round(2),
          "capacity_factor" => ((power.abs / spec[:nameplate_kw]).clamp(0, 1)).round(3),
          "string_voltage" => string_voltage,
          "ambient_temp_c" => ambient,
          "grid_flow_kw" => (power - load_kw).round(2),
          "inverter_temp_c" => (ambient + inverter_bump).clamp(15, 90),
          "inverter_status" => state == "critical" ? "fault" : "online",
          "dc_power_kw" => dc_power_kw.round(2),
          "dc_amps" => (dc_power_kw * 1000 / string_voltage).round(2),
          "ac_voltage" => ac_voltage,
          "ac_amps" => (power.abs * 1000 / ac_voltage).round(2)
        },
        alarm_state: state
      }
    end

    Telemetry.insert_all!(rows) if rows.any?
  end

  hq = sites["goose-roof-1"]
  Case.find_or_create_by!(id: make_id("case-goose-open")) do |c|
    c.site_id          = hq.id
    c.organization_id  = hq.organization_id
    c.opened_by_user_id = users["paradise-user"].id
    c.subject          = "Inverter intermittent fault on String 3"
    c.notes            = "#{Time.current.utc.iso8601} — Alex (Paradise Ops)\nCustomer reports flickering production curve; opening case to investigate.\n\n"
    c.status           = "open"
  end

  kiwi_site = sites["kiwi-array-1"]
  Case.find_or_create_by!(id: make_id("case-kiwi-escalated")) do |c|
    c.site_id          = kiwi_site.id
    c.organization_id  = kiwi_site.organization_id
    c.opened_by_user_id = users["paradise-user"].id
    c.subject          = "Persistent under-production after firmware update"
    c.notes            = "#{Time.current.utc.iso8601} — Alex (Paradise Ops)\nFirmware push appears to have degraded MPPT tracking; escalating to Maverick.\n\n"
    c.status           = "in_progress"
    c.escalated_to_maverick = true
    c.escalated_at         = 2.hours.ago
  end
end

puts "Seeded:"
puts "  Organizations: #{Organization.count}"
puts "  Users:         #{User.count}"
puts "  Sites:         #{Site.count}"
puts "  Telemetry:     #{Telemetry.count}"
puts "  Cases:         #{Case.count}"
puts ""
puts "All users use password: #{PASSWORD}"
