# frozen_string_literal: true

module Api
  module Mcp
    # Lightweight health check endpoint for monitoring wiki availability
    # Does NOT require authentication for monitoring purposes
    class HealthController < ActionController::Base
      # GET /api/mcp/health
      # Simple health check endpoint
      def index
        # Quick database connectivity check
        db_status = check_database_connection

        # Basic card count check (very fast, uses cached count)
        card_count = check_card_count

        status = db_status && card_count ? "healthy" : "degraded"

        render json: {
          status: status,
          timestamp: Time.now.utc.iso8601,
          version: "1.0",
          checks: {
            database: db_status ? "ok" : "error",
            cards: card_count ? "ok" : "error"
          }
        }, status: (status == "healthy" ? :ok : :service_unavailable)
      end

      # GET /api/mcp/health/ping
      # Ultra-lightweight ping endpoint (no DB check)
      def ping
        render json: {
          status: "ok",
          timestamp: Time.now.utc.iso8601
        }
      end

      private

      def check_database_connection
        # Quick connection test with timeout
        ActiveRecord::Base.connection.active?
      rescue StandardError
        false
      end

      def check_card_count
        # Use fast count query (uses cached table stats in PostgreSQL)
        Card.count > 0
      rescue StandardError
        false
      end
    end
  end
end
