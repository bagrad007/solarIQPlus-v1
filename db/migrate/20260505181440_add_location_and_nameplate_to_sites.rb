class AddLocationAndNameplateToSites < ActiveRecord::Migration[8.1]
  # Physical-installation attributes (not security config). Latitude/longitude
  # feed the Open-Meteo weather forecast for the site's PV-yield projection;
  # nameplate_kw bounds the Dashboard generation gauges and the projection
  # formula (expected_kwh = nameplate_kw * peak_sun_hours * PR * cloud_factor).
  #
  # Not added to Site::AUDITED_FIELDS — these aren't security-relevant the way
  # gateway_ip / device_credentials_encrypted / polling_interval_seconds are.

  def change
    add_column :sites, :latitude,     :decimal, precision: 9, scale: 6
    add_column :sites, :longitude,    :decimal, precision: 9, scale: 6
    add_column :sites, :nameplate_kw, :decimal, precision: 6, scale: 2
  end
end
