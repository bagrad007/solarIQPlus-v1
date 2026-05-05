class CasesController < ApplicationController
  # Minimal Plan A workflow: index, show, new (with site picker or pre-fill),
  # create, append-only add_note, one-way escalate. State machine and
  # escalation rules are enforced in the DB; here we surface the validation
  # errors back as flash[:alert].

  before_action :load_case, only: [:show, :add_note, :escalate]

  def index
    @cases = Case.order(created_at: :desc)
  end

  def show
    @site = @case.site
  end

  def new
    @site = params[:site_id].present? ? Site.find(params[:site_id]) : nil
    @sites = @site ? [@site] : Site.order(:name)
    @case = Case.new(site_id: @site&.id, organization_id: @site&.organization_id)
  end

  def create
    @case = Case.new(case_params)
    @case.opened_by_user_id = current_user.id
    @case.organization_id   = @case.site&.organization_id
    if @case.save
      redirect_to case_path(@case), notice: "Case opened."
    else
      @sites = Site.order(:name)
      @site  = @case.site
      render :new, status: :unprocessable_entity
    end
  end

  def add_note
    @case.append_note(author: current_user, body: params[:body])
    redirect_to case_path(@case), notice: "Note added."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to case_path(@case), alert: e.message
  end

  def escalate
    @case.escalate!
    redirect_to case_path(@case), notice: "Escalated to Maverick."
  rescue ActiveRecord::StatementInvalid => e
    redirect_to case_path(@case), alert: e.message
  end

  private

  def load_case
    @case = Case.find(params[:id])
  end

  def case_params
    params.require(:case).permit(:site_id, :subject)
  end
end
