class Site < ApplicationRecord
  # Plan A audits changes to gateway_ip, device_credentials_encrypted,
  # polling_interval_seconds. Audit rows are written by a model callback
  # and respect the same RLS predicate as the Site they describe.

  AUDITED_FIELDS = %w[gateway_ip device_credentials_encrypted polling_interval_seconds].freeze

  belongs_to :organization
  has_many :cases, dependent: :restrict_with_exception
  has_many :telemetry_records, class_name: "Telemetry", dependent: :restrict_with_exception

  validates :name, presence: true
  validates :polling_interval_seconds, numericality: { greater_than: 0 }
  validate :organization_must_be_customer

  after_update :record_audit_log_entries

  private

  def organization_must_be_customer
    return if organization&.customer?
    errors.add(:organization, "must be a Customer")
  end

  def record_audit_log_entries
    actor_id = Current.user&.id
    return unless actor_id

    AUDITED_FIELDS.each do |field|
      next unless saved_change_to_attribute?(field)
      old_v, new_v = saved_change_to_attribute(field)
      AuditLog.create!(
        organization_id: organization_id,
        actor_user_id:   actor_id,
        auditable_type:  self.class.name,
        auditable_id:    id,
        field_name:      field,
        old_value:       old_v.to_s,
        new_value:       new_v.to_s
      )
    end
  end
end
