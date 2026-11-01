# frozen_string_literal: true

module PaySafe
  RateLimit = Struct.new(:limit, :remaining, :reset, keyword_init: true)

  # The raw outcome of a request. Every model carries the one it came from in last_response.
  class ApiResponse
    attr_reader :status, :headers, :body, :idempotency_key

    # headers: lower-cased names.
    def initialize(status, headers, body, idempotency_key)
      @status = status
      @headers = headers.freeze
      @body = body
      @idempotency_key = idempotency_key
    end

    def request_id
      headers["x-request-id"]
    end

    def rate_limit
      limit = headers["x-ratelimit-limit"]
      remaining = headers["x-ratelimit-remaining"]
      reset = headers["x-ratelimit-reset"]
      return nil if limit.nil? && remaining.nil? && reset.nil?

      to_i = ->(v) { v&.strip&.match?(/\A-?\d+\z/) ? v.to_i : nil }
      RateLimit.new(limit: to_i.call(limit), remaining: to_i.call(remaining), reset: to_i.call(reset))
    end

    def idempotent_replayed?
      headers["idempotent-replayed"] == "true"
    end

    # Seconds from Retry-After, or nil when absent.
    def retry_after
      value = headers["retry-after"]&.strip
      return nil if value.nil? || value.empty?
      return value.to_i if value.match?(/\A\d+\z/)

      [(Time.httpdate(value) - Time.now).ceil, 0].max
    rescue ArgumentError
      nil
    end

    def json
      return nil if body.empty?

      parsed = Util.parse_json(body)
      parsed.is_a?(Hash) ? parsed : nil
    end
  end
end
