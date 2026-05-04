class Case < ApplicationRecord
  # Status state machine and escalation lifecycle are enforced in the DB
  # (see migration 7). Application code may attempt any transition; invalid
  # ones raise ActiveRecord::StatementInvalid (PG: raise_exception). Notes
  # are append-only in the DB; use `append_note` rather than assigning notes
  # directly so the timestamp prefix stays consistent.

  enum :status, { open: "open", in_progress: "in_progress", resolved: "resolved", closed: "closed" }

  belongs_to :organization
  belongs_to :site
  # `opened_by` is `optional: true` from AR's perspective because a Maverick
  # acting in view-as creates cases as themselves, and their User row lives
  # in the Maverick org — outside the impersonated scope, so RLS hides it
  # during the AR association load. The DB enforces NOT NULL + FK so the
  # row stays referentially intact.
  belongs_to :opened_by, class_name: "User", foreign_key: :opened_by_user_id, optional: true

  validates :subject, presence: true
  validates :opened_by_user_id, presence: true

  def append_note(author:, body:)
    stamp  = "#{Time.current.utc.iso8601} — #{author.display_name}\n"
    entry  = "#{stamp}#{body.to_s.strip}\n\n"
    update!(notes: "#{notes}#{entry}")
  end

  def escalate!
    update!(escalated_to_maverick: true)
  end
end
