module Demo
  # JSON endpoint behind the floating "AI Energy Analyst" widget.
  #
  # Demo path only: serves the same Company A mock dataset to every signed-in
  # user, regardless of their tenant. The future production swap (kept as a
  # comment to avoid bit-rot in code) will:
  #   1. Resolve the *current* customer from the page context (params or
  #      `Current.effective_organization`).
  #   2. Replace `TelemetryRepository.data` with a tenant-scoped query that
  #      runs under `with_rls_context` (already wrapped by the
  #      ApplicationController stack).
  #   3. Swap `MockClaudeAdapter` for an `AnthropicAdapter` that streams
  #      tokens via SSE / Turbo Streams.
  class EnergyAnalystController < ApplicationController
    MESSAGE_MAX_LENGTH = 2_000

    def message
      user_message = params.require(:message).to_s
      if user_message.length > MESSAGE_MAX_LENGTH
        return render(json: { error: "Message too long." }, status: :unprocessable_entity)
      end

      insights = ::EnergyAnalyst::TelemetryInsights.new
      turn = adapter.complete(user_message: user_message, insights: insights)

      render json: turn.to_h
    rescue ActionController::ParameterMissing
      render json: { error: "Missing message." }, status: :bad_request
    rescue Errno::ENOENT, JSON::ParserError => e
      Rails.logger.error("[EnergyAnalyst] dataset unavailable: #{e.message}")
      render json: { error: "Demo data unavailable." }, status: :service_unavailable
    end

    private

    # Dependency injection point — tests replace this to assert routing.
    # Top-level `::` prevents Zeitwerk from looking for `Demo::EnergyAnalyst`
    # (it would look in lexical scope first and fail to autoload).
    def adapter
      ::EnergyAnalyst::MockClaudeAdapter.new
    end
  end
end
