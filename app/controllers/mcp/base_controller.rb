# frozen_string_literal: true

module Mcp
  # JSON API for the local TypeScript MCP server (`solar-iq-mcp-server/`).
  # Authenticates with a static Bearer token and signs in a configured User so
  # RLS and org scope match that account (same guarantees as the web app).
  class BaseController < ApplicationController
    skip_before_action :authenticate_user!
    prepend_before_action :authenticate_mcp_bearer!

    private

    def authenticate_mcp_bearer!
      expected = ENV["SOLAR_IQ_MCP_TOKEN"].presence
      email = ENV["SOLAR_IQ_MCP_ACTING_USER_EMAIL"].presence
      if expected.blank? || email.blank?
        render json: {
          error: "MCP API is not configured. Set SOLAR_IQ_MCP_TOKEN and SOLAR_IQ_MCP_ACTING_USER_EMAIL."
        }, status: :service_unavailable
        return
      end

      raw = request.headers["Authorization"].to_s
      token = raw.delete_prefix("Bearer ").strip
      same_len = token.present? && expected.bytesize == token.bytesize
      unless same_len && ActiveSupport::SecurityUtils.secure_compare(token, expected)
        head :unauthorized
        return
      end

      user = User.find_by(email: email)
      unless user
        render json: { error: "No user found for SOLAR_IQ_MCP_ACTING_USER_EMAIL=#{email}" }, status: :service_unavailable
        return
      end

      sign_in(user, store: false)
    end
  end
end
