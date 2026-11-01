# frozen_string_literal: true

module PaySafe
  # Per-call options, given as keyword arguments or a Hash:
  # idempotency_key, request_id, timeout (seconds), max_retries, headers.
  class RequestOptions
    KEYS = %i[idempotency_key request_id timeout max_retries headers].freeze

    attr_reader :idempotency_key, :request_id, :timeout, :max_retries, :headers

    def initialize(idempotency_key: nil, request_id: nil, timeout: nil, max_retries: nil, headers: {})
      Validate.idempotency_key(idempotency_key) unless idempotency_key.nil?
      Validate.request_id(request_id) unless request_id.nil?
      raise InvalidRequestError, "max_retries must be zero or more" if !max_retries.nil? && (!max_retries.is_a?(Integer) || max_retries.negative?)
      raise InvalidRequestError, "timeout must be positive" if !timeout.nil? && (!timeout.is_a?(Numeric) || timeout <= 0)

      Validate.headers(headers)
      @idempotency_key = idempotency_key
      @request_id = request_id
      @timeout = timeout
      @max_retries = max_retries
      @headers = headers.to_h { |k, v| [k.to_s, v] }.freeze
    end

    def self.from(opts)
      return opts if opts.is_a?(RequestOptions)
      raise InvalidRequestError, "options must be a Hash" unless opts.is_a?(Hash)

      unknown = opts.keys.map(&:to_sym) - KEYS
      raise InvalidRequestError, "Unknown request option #{unknown.first}" unless unknown.empty?

      new(**opts.transform_keys(&:to_sym))
    end

    def self.with_key(opts)
      options = from(opts)
      options.idempotency_key ? options : options.with_generated_key
    end

    def with_generated_key
      RequestOptions.new(idempotency_key: SecureRandom.uuid, request_id: request_id, timeout: timeout, max_retries: max_retries, headers: headers)
    end
  end

  # One HTTP attempt. Never contains the key or any body. status is nil when no response arrived.
  LogRecord = Struct.new(:http_method, :path, :status, :attempt, :duration, :request_id, :error, keyword_init: true)
end
