# frozen_string_literal: true

module EnergyAnalyst
  # Abstract interface every chat backend must satisfy.
  #
  # Today's only implementation is `MockClaudeAdapter`, which responds with
  # rule-based templating over `TelemetryInsights`. The same interface is
  # what a real Anthropic-backed adapter will implement tomorrow:
  #
  #   class AnthropicAdapter
  #     include EnergyAnalyst::LlmClient
  #     def complete(user_message:, insights:)
  #       # 1. Build a context bundle from `insights` (+ optional RAG).
  #       # 2. Call Anthropic Messages API (streaming via SSE if desired).
  #       # 3. Return an EnergyAnalyst::ChatTurn.
  #     end
  #   end
  #
  # Keeping `complete` as the single seam means the controller, view, and
  # JS contract never change when the backend swaps.
  module LlmClient
    # @param user_message [String] raw user input from the chat widget.
    # @param insights     [EnergyAnalyst::TelemetryInsights] the read-only
    #   knowledge layer the adapter may query for grounding.
    # @return [EnergyAnalyst::ChatTurn]
    def complete(user_message:, insights:)
      raise NotImplementedError, "#{self.class} must implement #complete"
    end
  end
end
