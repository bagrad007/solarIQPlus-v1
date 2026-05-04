class AuditLog < ApplicationRecord
  # Insert-only at the DB layer. AR may not call save on a persisted instance;
  # the trigger will raise. Always create new rows.

  belongs_to :organization
  # See note on Case#opened_by: a Maverick acting in view-as may write audit
  # rows whose actor record is outside the current RLS scope.
  belongs_to :actor, class_name: "User", foreign_key: :actor_user_id, optional: true

  validates :auditable_type, :auditable_id, :field_name, :actor_user_id, presence: true
end
