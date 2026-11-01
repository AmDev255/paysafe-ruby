# frozen_string_literal: true

module PaySafe
  # Base class for every error raised by this SDK.
  class Error < StandardError; end

  class ConfigurationError < Error; end

  # Raised before any network call when the request fails local validation.
  class InvalidRequestError < Error
    attr_reader :param

    def initialize(message, param = nil)
      super(message)
      @param = param
    end
  end

  # No HTTP response was received (DNS, TLS, socket errors).
  class ApiConnectionError < Error; end

  class ApiTimeoutError < ApiConnectionError; end

  # The response body exceeded the SDK's size limit. Never retried.
  class ResponseTooLargeError < ApiConnectionError
    def initialize(message = "Response body exceeds the 16 MB limit")
      super
    end
  end

  class PollingTimeoutError < Error
    attr_reader :last_seen

    def initialize(message, last_seen)
      super(message)
      @last_seen = last_seen
    end
  end

  class SignatureVerificationError < Error
    MISSING_HEADER = "missing_header"
    MALFORMED_HEADER = "malformed_header"
    TIMESTAMP_OUTSIDE_TOLERANCE = "timestamp_outside_tolerance"
    SIGNATURE_MISMATCH = "signature_mismatch"
    INVALID_PAYLOAD = "invalid_payload"

    attr_reader :reason

    def initialize(reason, message)
      super(message)
      @reason = reason
    end
  end

  # Any non-2xx response from the API. Subclasses exist for every documented error code.
  class ApiError < Error
    attr_reader :status, :code, :request_id, :param, :details, :doc_url, :headers, :retry_after, :rate_limit

    def initialize(status:, code:, message:, request_id: nil, param: nil, details: nil, doc_url: nil, headers: {}, retry_after: nil,
                   rate_limit: nil)
      super(message)
      @raw_message = message
      @status = status
      @code = code
      @request_id = request_id
      @param = param
      @details = details
      @doc_url = doc_url
      @headers = headers
      @retry_after = retry_after
      @rate_limit = rate_limit
    end

    # Whether the documented retry policy allows retrying with the same idempotency key.
    def retryable?
      status == 429 || status == 503 || code == "idempotency_in_progress" || (status >= 500 && code != "provider_error")
    end

    def message
      @raw_message
    end

    def to_s
      "#{code} (#{status}) #{@raw_message} [#{request_id || "no request id"}]"
    end

    def inspect
      "#<#{self.class.name} #{self}>"
    end
  end

  class ValidationError < ApiError; end
  class AuthenticationError < ApiError; end

  class PermissionError < ApiError
    def ip_not_allowed?
      %w[ip_not_allowed ip_allowlist_empty].include?(details&.dig("code"))
    end

    def observed_ip
      details&.dig("ip")
    end
  end

  class FeatureDisabledError < ApiError; end
  class NotFoundError < ApiError; end

  class InsufficientFundsError < ApiError
    def available
      details&.dig("available")
    end

    def requested
      details&.dig("requested")
    end
  end

  class ConflictError < ApiError; end
  class IdempotencyConflictError < ConflictError; end
  class IdempotencyInProgressError < ConflictError; end
  class InvalidStateError < ConflictError; end

  class RateLimitError < ApiError
    def scope
      details&.dig("scope")
    end
  end

  class ProviderError < ApiError; end
  class ProviderUnavailableError < ApiError; end
  class ServiceUnavailableError < ApiError; end
  class InternalError < ApiError; end

  module ErrorMapper
    BY_CODE = {
      "validation_error" => ValidationError,
      "authentication_error" => AuthenticationError,
      "permission_error" => PermissionError,
      "feature_disabled" => FeatureDisabledError,
      "not_found" => NotFoundError,
      "insufficient_funds" => InsufficientFundsError,
      "conflict" => ConflictError,
      "idempotency_conflict" => IdempotencyConflictError,
      "idempotency_in_progress" => IdempotencyInProgressError,
      "invalid_state" => InvalidStateError,
      "rate_limited" => RateLimitError,
      "provider_error" => ProviderError,
      "provider_unavailable" => ProviderUnavailableError,
      "service_unavailable" => ServiceUnavailableError
    }.freeze

    BY_STATUS = {
      400 => ValidationError, 401 => AuthenticationError, 402 => InsufficientFundsError, 403 => PermissionError,
      404 => NotFoundError, 409 => ConflictError, 429 => RateLimitError, 503 => ServiceUnavailableError
    }.freeze

    def self.from_response(response)
      envelope = response.json&.dig("error")
      envelope = nil unless envelope.is_a?(Hash)
      code = "unknown"
      message = "HTTP #{response.status} from the PaySafe API"
      request_id = response.request_id
      param = details = doc_url = nil
      if envelope
        code = envelope["code"] if envelope["code"].is_a?(String)
        message = envelope["message"] if envelope["message"].is_a?(String)
        request_id = envelope["request_id"] if envelope["request_id"].is_a?(String)
        param = envelope["param"] if envelope["param"].is_a?(String)
        details = envelope["details"] if envelope["details"].is_a?(Hash)
        doc_url = envelope["doc_url"] if envelope["doc_url"].is_a?(String)
      elsif !response.body.empty?
        details = { "raw" => response.body[0, 4096] }
      end
      klass = BY_CODE[code] || BY_STATUS[response.status] || (response.status >= 500 ? InternalError : ApiError)
      klass.new(status: response.status, code: code, message: message, request_id: request_id, param: param, details: details,
                doc_url: doc_url, headers: response.headers, retry_after: response.retry_after, rate_limit: response.rate_limit)
    end
  end
end
