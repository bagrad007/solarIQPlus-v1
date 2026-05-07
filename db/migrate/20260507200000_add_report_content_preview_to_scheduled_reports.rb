# frozen_string_literal: true

class AddReportContentPreviewToScheduledReports < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE scheduled_reports
        ADD COLUMN report_content_preview text NOT NULL DEFAULT '';
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE scheduled_reports
        DROP COLUMN IF EXISTS report_content_preview;
    SQL
  end
end
