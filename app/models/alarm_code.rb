class AlarmCode < ApplicationRecord
  # Global lookup catalog (no RLS). Read-only at runtime in Plan A; rows
  # arrive via seeds. The Alarm row carries its own severity (denormalized
  # at insert) so editorial overrides don't have to mutate the catalog.
  #
  # See docs/UBIQUITOUS-LANGUAGE.md → "Alarm Code".

  enum :default_severity, {
    critical: "critical",
    warning:  "warning",
    cleared:  "cleared"
  }

  has_many :alarms, foreign_key: :code_id, inverse_of: :code, dependent: :restrict_with_exception

  validates :code,             presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :label,            presence: true
  validates :default_severity, presence: true
end
