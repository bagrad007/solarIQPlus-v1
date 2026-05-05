# SolarIQ+ demo tree.
#
# 1 Maverick / 2 Partners (Acme + Beta with distinct logos) / 4 Customers /
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
  maverick = Organization.find_or_create_by!(id: make_id("maverick")) do |o|
    o.org_type = "maverick"
    o.name     = "Maverick Dynamics"
    o.parent_id = nil
    o.branding_config = { "logo_url" => "https://placehold.co/180x40/001F51/ffffff?text=Maverick" }
  end

  acme = Organization.find_or_create_by!(id: make_id("acme")) do |o|
    o.org_type  = "partner"
    o.name      = "Acme Solar Partners"
    o.parent_id = maverick.id
    o.branding_config = { "logo_url" => "https://placehold.co/180x40/00337c/ffffff?text=Acme" }
  end

  beta = Organization.find_or_create_by!(id: make_id("beta")) do |o|
    o.org_type  = "partner"
    o.name      = "Beta Energy Group"
    o.parent_id = maverick.id
    o.branding_config = { "logo_url" => "https://placehold.co/180x40/964900/ffffff?text=Beta" }
  end

  customers = {}
  [
    { key: "northwind",   name: "Northwind Manufacturing", parent: acme },
    { key: "fabrikam",    name: "Fabrikam Industries",     parent: acme },
    { key: "contoso",     name: "Contoso Logistics",       parent: beta },
    { key: "tailspin",    name: "Tailspin Aerospace",      parent: beta }
  ].each do |attrs|
    customers[attrs[:key]] = Organization.find_or_create_by!(id: make_id("cust-#{attrs[:key]}")) do |o|
      o.org_type  = "customer"
      o.name      = attrs[:name]
      o.parent_id = attrs[:parent].id
    end
  end

  user_specs = [
    { key: "maverick-admin", org: maverick,             role: "maverick_admin", email: "admin@maverick.example",  name: "Maverick Admin" },
    { key: "acme-user",      org: acme,                 role: "partner_user",   email: "ops@acme.example",        name: "Alex (Acme Ops)" },
    { key: "beta-user",      org: beta,                 role: "partner_user",   email: "ops@beta.example",        name: "Beck (Beta Ops)" },
    { key: "northwind-user", org: customers["northwind"], role: "customer_user", email: "site@northwind.example",  name: "Nora (Northwind)" },
    { key: "fabrikam-user",  org: customers["fabrikam"],  role: "customer_user", email: "site@fabrikam.example",  name: "Finn (Fabrikam)" },
    { key: "contoso-user",   org: customers["contoso"],   role: "customer_user", email: "site@contoso.example",   name: "Casey (Contoso)" },
    { key: "tailspin-user",  org: customers["tailspin"],  role: "customer_user", email: "site@tailspin.example",  name: "Tara (Tailspin)" }
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

  site_specs = [
    { key: "northwind-roof-1", org: customers["northwind"], name: "Northwind HQ Rooftop", polling: 30,
      gateway: "10.0.10.5", critical_count: 1, warn_count: 2 },
    { key: "northwind-roof-2", org: customers["northwind"], name: "Northwind Plant B", polling: 30,
      gateway: "10.0.10.6", critical_count: 0, warn_count: 0 },
    { key: "fabrikam-array-1", org: customers["fabrikam"],  name: "Fabrikam Solar Array", polling: 60,
      gateway: "10.0.20.5", critical_count: 0, warn_count: 1 },
    { key: "fabrikam-array-2", org: customers["fabrikam"],  name: "Fabrikam Logistics Park", polling: 60,
      gateway: "10.0.20.6", critical_count: 0, warn_count: 0 },
    { key: "contoso-warehouse", org: customers["contoso"],  name: "Contoso Warehouse", polling: 30,
      gateway: "10.0.30.5", critical_count: 0, warn_count: 0 },
    { key: "contoso-cold-store", org: customers["contoso"], name: "Contoso Cold Storage", polling: 30,
      gateway: "10.0.30.6", critical_count: 0, warn_count: 0 },
    { key: "tailspin-mfg-1",   org: customers["tailspin"],  name: "Tailspin Mfg Line 1", polling: 30,
      gateway: "10.0.40.5", critical_count: 0, warn_count: 0 },
    { key: "tailspin-rdp",     org: customers["tailspin"],  name: "Tailspin R&D Pilot", polling: 60,
      gateway: "10.0.40.6", critical_count: 0, warn_count: 0 }
  ]

  sites = {}
  site_specs.each do |spec|
    sites[spec[:key]] = Site.find_or_create_by!(id: make_id("site-#{spec[:key]}")) do |s|
      s.organization_id = spec[:org].id
      s.name = spec[:name]
      s.gateway_ip = spec[:gateway]
      s.polling_interval_seconds = spec[:polling]
    end
  end

  cutoff = 30.days.ago
  now    = Time.current
  demo_site_ids = sites.values.map(&:id)
  Telemetry.where(site_id: demo_site_ids).where(recorded_at: cutoff..).delete_all

  site_specs.each do |spec|
    site = sites[spec[:key]]
    interval = spec[:polling] >= 60 ? 1.hour : 15.minutes

    cursor = cutoff
    rows   = []
    while cursor < now - 24.hours
      power = 50 + 100 * Math.sin((cursor.to_i / 86_400.0) * 2 * Math::PI) + rand(-10..10)
      rows << {
        site_id: site.id,
        organization_id: site.organization_id,
        org_path: site.org_path,
        recorded_at: cursor,
        metric_payload: {
          "power_kw" => power.round(2),
          "capacity_factor" => ((power.abs / 200.0).clamp(0, 1)).round(3),
          "string_voltage" => rand(380..420),
          "ambient_temp_c" => rand(15..38),
          "inverter_status" => "online"
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

      power = 50 + 100 * Math.sin((t.to_i / 86_400.0) * 2 * Math::PI) + rand(-10..10)
      rows << {
        site_id: site.id,
        organization_id: site.organization_id,
        org_path: site.org_path,
        recorded_at: t,
        metric_payload: {
          "power_kw" => power.round(2),
          "capacity_factor" => ((power.abs / 200.0).clamp(0, 1)).round(3),
          "string_voltage" => rand(380..420),
          "ambient_temp_c" => rand(15..38),
          "inverter_status" => state == "critical" ? "fault" : "online"
        },
        alarm_state: state
      }
    end

    Telemetry.insert_all!(rows) if rows.any?
  end

  hq = sites["northwind-roof-1"]
  Case.find_or_create_by!(id: make_id("case-northwind-open")) do |c|
    c.site_id          = hq.id
    c.organization_id  = hq.organization_id
    c.opened_by_user_id = users["acme-user"].id
    c.subject          = "Inverter intermittent fault on String 3"
    c.notes            = "#{Time.current.utc.iso8601} — Alex (Acme Ops)\nCustomer reports flickering production curve; opening case to investigate.\n\n"
    c.status           = "open"
  end

  fab = sites["fabrikam-array-1"]
  Case.find_or_create_by!(id: make_id("case-fabrikam-escalated")) do |c|
    c.site_id          = fab.id
    c.organization_id  = fab.organization_id
    c.opened_by_user_id = users["acme-user"].id
    c.subject          = "Persistent under-production after firmware update"
    c.notes            = "#{Time.current.utc.iso8601} — Alex (Acme Ops)\nFirmware push appears to have degraded MPPT tracking; escalating to Maverick.\n\n"
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
