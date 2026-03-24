# frozen_string_literal: true

module RateLimitable
  extend ActiveSupport::Concern

  included do
    before_action :check_rate_limit!
  end

  private

  def check_rate_limit!
    return unless rate_limiting_enabled?

    api_key = extract_api_key
    return unless api_key

    key = "mcp_api:rate_limit:#{api_key}"
    limit = rate_limit_per_hour
    window = 3600 # 1 hour in seconds

    count = increment_request_count(key, window)

    if count > limit
      render json: {
        error: {
          code: "rate_limited",
          message: "Rate limit exceeded",
          details: {
            limit: limit,
            window: "1 hour",
            retry_after: time_until_reset(key)
          }
        }
      }, status: 429
    end
  end

  def extract_api_key
    # Extract from auth token payload or X-API-Key header
    if @current_mcp_payload
      @current_mcp_payload["api_key"]
    else
      request.headers["X-API-Key"]
    end
  end

  def increment_request_count(key, window)
    current_count = Rails.cache.read(key) || 0
    new_count = current_count + 1

    Rails.cache.write(key, new_count, expires_in: window)
    new_count
  end

  def time_until_reset(key)
    # Get the actual TTL of the cache key from Redis/store
    # Rails.cache doesn't expose TTL directly, so we access the underlying store
    if Rails.cache.respond_to?(:redis)
      # Redis cache store
      Rails.cache.redis.ttl(key) || 3600
    elsif defined?(Dalli) && Rails.cache.is_a?(ActiveSupport::Cache::MemCacheStore)
      # Memcached doesn't support TTL lookup, return default window
      3600
    else
      # For other stores or if key doesn't exist, return default window
      3600
    end
  rescue StandardError
    # Fallback to default if anything goes wrong
    3600
  end

  def rate_limit_per_hour
    # Configurable via ENV; default 1000 requests/hour
    (ENV["MCP_RATE_LIMIT_PER_HOUR"] || 1000).to_i
  end

  def rate_limiting_enabled?
    ENV["MCP_RATE_LIMITING"] != "false"
  end
end
