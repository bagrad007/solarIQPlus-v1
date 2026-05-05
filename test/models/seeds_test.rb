require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "demo seeds do not wipe unrelated historical telemetry" do
    maverick = Organization.create!(org_type: "maverick", name: "Historical Maverick")
    partner = Organization.create!(parent: maverick, org_type: "partner", name: "Historical Partner")
    customer = Organization.create!(parent: partner, org_type: "customer", name: "Historical Customer")
    site = Site.create!(organization: customer, name: "Historical Site", polling_interval_seconds: 30)
    recorded_at = 2.years.ago
    historical = Telemetry.create!(
      site: site,
      organization: customer,
      recorded_at: recorded_at,
      metric_payload: { "power_kw" => 12.5 },
      alarm_state: "normal"
    )

    Telemetry.create!(
      site: site,
      organization: customer,
      recorded_at: 1.day.ago,
      metric_payload: { "power_kw" => 15.0 },
      alarm_state: "normal"
    )

    capture_io { load Rails.root.join("db/seeds.rb") }

    assert Telemetry.exists?(id: historical.id, recorded_at: recorded_at)
  end
end
