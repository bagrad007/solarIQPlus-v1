# frozen_string_literal: true

class ReportsController < ApplicationController
  # RLS is the authorization layer; we only stamp organization_id to the
  # caller's effective org so rows stay under the right org_path subtree.
  #
  # POST /reports/:id/dispatch — member command (not CRUD): enqueue a demo
  # dispatch job immediately so stakeholders see Solid Queue activity.
  # (Action name is `enqueue_delivery` because `dispatch` clashes with Rails.)

  before_action :set_scheduled_report, only: %i[edit update enqueue_delivery]

  # Demo: build report body from the current AI brief (no external LLM).
  def draft_body
    body = ScheduledReport.build_draft_preview_body(params[:ai_prompt].to_s)
    if body.blank?
      render json: { error: "Add an AI brief first." }, status: :unprocessable_entity
      return
    end

    render json: { report_content_preview: body }
  end

  def index
    @scheduled_reports = ScheduledReport.order(created_at: :desc).limit(50)
    @scheduled_report = ScheduledReport.new(
      name:               ScheduledReport::DEMO_EXAMPLE_REPORT_NAME,
      ai_prompt:          ScheduledReport::DEMO_EXAMPLE_AI_PROMPT,
      frequency:          "weekly",
      hour:               8,
      time_zone:          "UTC"
    )
    @scheduled_report.recipients_line = ScheduledReport::DEMO_EXAMPLE_RECIPIENTS_LINE
  end

  def create
    @scheduled_report = ScheduledReport.new(scheduled_report_attributes)
    @scheduled_report.organization_id = Current.effective_organization.id

    if @scheduled_report.save
      @scheduled_report.queue_scheduled_run!
      redirect_to reports_path, notice: "Report scheduled."
    else
      @scheduled_reports = ScheduledReport.order(created_at: :desc).limit(50)
      flash.now[:alert] = "Could not save report."
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @scheduled_report.recipients_line = @scheduled_report.recipients.join(", ")
  end

  def update
    @scheduled_report.assign_attributes(scheduled_report_attributes)
    @scheduled_report.organization_id = Current.effective_organization.id

    if @scheduled_report.save
      @scheduled_report.queue_scheduled_run!
      redirect_to reports_path, notice: "Report updated."
    else
      flash.now[:alert] = "Could not update report."
      render :edit, status: :unprocessable_entity
    end
  end

  def enqueue_delivery
    @scheduled_report.dispatch_now!
    redirect_to reports_path, notice: "Report queued for delivery."
  end

  private

  def set_scheduled_report
    @scheduled_report = ScheduledReport.find(params[:id])
  end

  def scheduled_report_attributes
    params.require(:scheduled_report).permit(
      :name,
      :recipients_line,
      :ai_prompt,
      :report_content_preview,
      :frequency,
      :hour,
      :time_zone,
      :enabled
    )
  end
end
