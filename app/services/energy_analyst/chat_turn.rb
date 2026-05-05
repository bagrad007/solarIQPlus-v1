# frozen_string_literal: true

module EnergyAnalyst
  # The single value object the controller serializes for every chat reply.
  # Shape is intentionally flat and JSON-friendly so the same contract works
  # for the mock adapter today and a real Claude adapter tomorrow.
  #
  #   reply_text     — String, markdown-light prose for the assistant bubble.
  #   visualizations — Array of chart specs (see EnergyAnalyst::ChartSpec
  #                    docs in mock_claude_adapter.rb). Empty array is fine.
  #   intent         — Symbol, the intent the adapter routed to. Useful for
  #                    debugging and for the controller test to assert on.
  ChatTurn = Struct.new(:reply_text, :visualizations, :intent, keyword_init: true) do
    def to_h
      {
        reply_text: reply_text,
        visualizations: visualizations || [],
        intent: intent
      }
    end
  end
end
