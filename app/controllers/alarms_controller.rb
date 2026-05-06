class AlarmsController < ApplicationController
  # Operational triage table. RLS narrows visibility (Architectural Invariant 1)
  # — there is no tenant `where(...)` here. Filtering, sorting, searching, and
  # pagination are all delegated to AlarmFilter; lifecycle transitions are
  # delegated to Alarm#acknowledge!/#clear!.
  #
  # The controller is intentionally thin: it carries no business logic and
  # therefore needs no unit tests of its own logic. Its tests live in the
  # integration layer (test/integration/alarms_controller_test.rb).

  before_action :load_alarm, only: [:acknowledge, :clear]

  def index
    @filter         = AlarmFilter.new(filter_params)
    @result         = @filter.results
    @alarm_codes    = AlarmCode.order(:code)
    @sites_in_scope = Site.order(:name)
  end

  def acknowledge
    @alarm.acknowledge!(actor: current_user)
    redirect_back fallback_location: alarms_path, notice: "Alarm acknowledged."
  rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: alarms_path, alert: e.message
  end

  def clear
    @alarm.clear!(actor: current_user)
    redirect_back fallback_location: alarms_path, notice: "Alarm cleared."
  rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: alarms_path, alert: e.message
  end

  private

  def load_alarm
    @alarm = Alarm.find(params[:id])
  end

  # Permit only the keys AlarmFilter knows about; anything else is dropped.
  # AlarmFilter additionally allow-lists severity / status values, but
  # filtering early keeps the params hash small.
  def filter_params
    params.permit(
      :site_id, :code_id, :customer_id, :partner_id,
      :q, :sort, :dir, :show_cleared, :page,
      severity: [], status: []
    ).to_h
  end
end
