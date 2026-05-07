# frozen_string_literal: true

class ScheduledReport < ApplicationRecord
  FREQUENCIES = %w[daily weekly monthly].freeze

  # Stakeholder-demo copy: prefilled on the new-report form and reloadable via
  # "Use example brief" (see Stimulus `report-draft-from-prompt`).
  DEMO_EXAMPLE_REPORT_NAME = "Weekly production & revenue (sample)".freeze
  DEMO_EXAMPLE_AI_PROMPT = (<<~PROMPT).squish.freeze
    For the trailing 7 days vs the prior 7: site-level AC energy (kWh), estimated
    bill credit using our blended retail $/kWh, and any days where curtailment
    or clipping exceeded 2% of potential. Call out inverters that spent more than
    30 minutes near thermal warning thresholds and tie spikes to high ambient
    temperature when telemetry exists.
  PROMPT

  DEMO_EXAMPLE_RECIPIENTS_LINE = "energy.ops@yourcompany.com, cfo@yourcompany.com".freeze

  # Shared by server-side create seeding and `POST /reports/draft_body` (demo).
  def self.build_draft_preview_body(ai_prompt_text)
    p = ai_prompt_text.to_s.strip
    return "" if p.blank?

    <<~BODY.chomp
      [Draft — edit before recipients see this]

      What you asked for:
      #{p}

      ---
      Proposed sections (tighten or replace):
      • Executive summary
      • Energy & revenue highlights
      • Anomalies / actions

      Paste tables, bullets, or disclaimers here — this ships with the report.
    BODY
  end

  belongs_to :organization

  attr_accessor :recipients_line

  validates :name, presence: true
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :hour, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 }
  validates :ai_prompt, presence: true
  validate :organization_must_match_effective, on: %i[create update]
  validate :recipients_must_have_entries

  before_validation :apply_recipients_line
  before_validation :strip_name
  before_validation :strip_ai_prompt
  before_validation :seed_report_content_preview, on: :create
  before_validation :set_next_run_at_for_schedule

  def queue_scheduled_run!
    return if next_run_at.blank?

    ScheduledReports::DispatchJob.set(wait_until: next_run_at).perform_later(id)
  end

  def dispatch_now!
    ScheduledReports::DispatchJob.perform_later(id)
  end

  # UI + table: "Active" means enabled on schedule; "Paused" stops sends.
  def schedule_status_label
    enabled? ? "Active" : "Paused"
  end

  private

  def strip_name
    self.name = name.to_s.strip
  end

  def strip_ai_prompt
    self.ai_prompt = ai_prompt.to_s.strip
  end

  # Demo: if user leaves the body blank, seed an editable scaffold from the AI prompt.
  def seed_report_content_preview
    return unless new_record?
    return if report_content_preview.present?

    body = self.class.build_draft_preview_body(ai_prompt)
    self.report_content_preview = body if body.present?
  end

  def apply_recipients_line
    return if recipients_line.nil?

    parsed = recipients_line.to_s.split(/[,;\n]+/).map(&:strip).reject(&:blank?)
    self.recipients = parsed
  end

  def recipients_must_have_entries
    errors.add(:recipients_line, "add at least one email address") if recipients.blank?
  end

  def organization_must_match_effective
    eff = Current.effective_organization
    return if eff.blank?

    errors.add(:base, "organization scope mismatch") if organization_id != eff.id
  end

  # Demo-grade: next calendar day at `hour` in the chosen zone.
  def set_next_run_at_for_schedule
    return unless enabled?

    zone = time_zone.presence || "UTC"
    Time.use_zone(zone) do
      date = Time.zone.today + 1.day
      self.next_run_at = Time.zone.local(date.year, date.mon, date.day, hour, 0, 0)
    end
  end
end
