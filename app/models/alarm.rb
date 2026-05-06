class Alarm < ApplicationRecord
  # Operational fault row tied to a Site. Tenant-bearing (carries
  # organization_id + denormalized org_path); RLS narrows visibility
  # uniformly with every other tenant table. The DB state-machine trigger
  # owns the legality of every status transition; this class exposes only
  # the two operator verbs (Acknowledge, Clear) plus a display helper.
  #
  # Public surface:
  #   #acknowledge!(actor:)  — firing → acknowledged
  #   #clear!(actor:)        — firing | acknowledged → cleared
  #   #display_code          — "E-{code}" for the table row
  #
  # Hidden behind that surface: state-guard checks (delegated to the
  # trigger), audit_log row emission, actor stamping, and code formatting.
  #
  # See docs/UBIQUITOUS-LANGUAGE.md → "Alarm" / "Severity" / "Alarm Lifecycle".

  enum :severity, {
    critical: "critical",
    warning:  "warning",
    cleared:  "cleared"
  }, prefix: :severity

  enum :status, {
    firing:       "firing",
    acknowledged: "acknowledged",
    cleared:      "cleared"
  }, prefix: :status

  belongs_to :organization
  belongs_to :site
  belongs_to :code, class_name: "AlarmCode", foreign_key: :code_id, inverse_of: :alarms
  # See note on Case#opened_by — a Maverick acting in view-as may stamp
  # acknowledgement / clearance with a User row outside the impersonated
  # scope. The DB enforces NOT NULL via the paired CHECK; AR's belongs_to
  # is `optional: true` so AR does not block the load when RLS hides the
  # actor row.
  belongs_to :acknowledged_by,
             class_name:  "User",
             foreign_key: :acknowledged_by_user_id,
             inverse_of:  false,
             optional:    true
  belongs_to :cleared_by,
             class_name:  "User",
             foreign_key: :cleared_by_user_id,
             inverse_of:  false,
             optional:    true

  validates :title, presence: true

  # Mirror the DB BEFORE INSERT trigger so AR validations have something to
  # check before the row reaches Postgres. Both the trigger and this hook
  # are idempotent: if the caller supplied a value, neither overwrites it.
  before_validation :inherit_defaults_from_code, on: :create

  def acknowledge!(actor:)
    transition_status!(to: "acknowledged", actor: actor) do
      self.acknowledged_by_user_id = actor&.id
      self.acknowledged_at         = Time.current
    end
  end

  def clear!(actor:)
    transition_status!(to: "cleared", actor: actor) do
      self.cleared_by_user_id = actor&.id
      self.cleared_at         = Time.current
    end
  end

  def display_code
    "E-#{code&.code}"
  end

  private

  def inherit_defaults_from_code
    return unless code
    self.title    = code.label             if title.blank?
    self.severity = code.default_severity  if severity.blank?
  end

  # Wrap the lifecycle update in its own savepoint so a trigger-rejected
  # transition (illegal state-machine move) rolls back cleanly without
  # poisoning the surrounding request-level transaction. The controller
  # rescues StatementInvalid / RecordInvalid and renders a flash from
  # outside this savepoint.
  def transition_status!(to:, actor:)
    previous = status
    self.class.transaction(requires_new: true) do
      yield
      self.status = to
      save!
      record_status_audit!(actor: actor, from: previous, to: to)
    end
  end

  def record_status_audit!(actor:, from:, to:)
    AuditLog.create!(
      organization_id: organization_id,
      actor_user_id:   actor&.id,
      auditable_type:  self.class.name,
      auditable_id:    id,
      field_name:      "status",
      old_value:       from,
      new_value:       to
    )
  end
end
