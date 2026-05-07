# frozen_string_literal: true

module ScheduledReports
  class DispatchJob < ApplicationJob
    queue_as :default

    # Demo: real implementation would render PDFs / send ActionMailer. RLS
    # context in the job is whatever the worker uses — this only logs.
    def perform(scheduled_report_id)
      report = ScheduledReport.find_by(id: scheduled_report_id)
      return unless report

      preview = report.report_content_preview.to_s.truncate(400)
      Rails.logger.info(
        "[ScheduledReports::DispatchJob] id=#{report.id} name=#{report.name.inspect} " \
        "recipients=#{report.recipients.inspect} frequency=#{report.frequency} " \
        "preview=#{preview.inspect}"
      )
    end
  end
end
