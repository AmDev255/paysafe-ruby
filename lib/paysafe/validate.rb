# frozen_string_literal: true

module PaySafe
  module Validate
    MAX_BODY_BYTES = 65_536
    MAX_METADATA_BYTES = 8192
    ID = /\A[A-Za-z0-9_-]{1,64}\z/
    HEADER_NAME = /\A[A-Za-z0-9-]{1,100}\z/
    REQUEST_ID = /\A[A-Za-z0-9._-]{8,64}\z/
    PHONE = /\A\+255[0-9]{9}\z/
    QUERY_KEY = /\A[A-Za-z0-9_]{1,40}\z/
    DATE_TIME = /\A\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2}))?\z/
    API_KEY = /\A[A-Za-z0-9_]+\z/
    PROTECTED_HEADERS = %w[authorization host content-length transfer-encoding connection].freeze
    LOOPBACK = %w[localhost 127.0.0.1 ::1 [::1] host.docker.internal].freeze

    module_function

    def control?(value, allow_tab)
      value.each_char.any? { |c| c == "\u007F" || (c.ord < 32 && !(allow_tab && c == "\t")) }
    end

    def idempotency_key(key)
      return if key.is_a?(String) && key.length.between?(1, 255) && key.each_char.all? { |c| c.ord.between?(32, 126) }

      raise InvalidRequestError, "Idempotency-Key must be 1 to 255 printable ASCII characters"
    end

    def request_id(value)
      raise InvalidRequestError, "X-Request-ID must be 8 to 64 characters of A-Z a-z 0-9 . _ -" unless value.is_a?(String) && REQUEST_ID.match?(value)
    end

    # Identifiers go into URL paths; anything outside the id alphabet is rejected.
    def id(value, name = "id")
      raise InvalidRequestError.new("#{name} must be 1 to 64 characters of A-Z a-z 0-9 _ -", name) unless value.is_a?(String) && ID.match?(value)

      value
    end

    def headers(headers)
      raise InvalidRequestError, "headers must be a Hash" unless headers.is_a?(Hash)

      headers.each do |name, value|
        name = name.to_s
        raise InvalidRequestError, "Header names may only contain letters, digits and dashes" unless HEADER_NAME.match?(name)
        raise InvalidRequestError, "The #{name} header cannot be overridden" if PROTECTED_HEADERS.include?(name.downcase)
        raise InvalidRequestError, "Header #{name} has an invalid value" unless value.is_a?(String) && value.length <= 4096 && !control?(value, true)
      end
    end

    def required(value, field)
      raise InvalidRequestError.new("#{field} is required", field) if value.nil? || (value.is_a?(String) && value.empty?)
    end

    def phone(value, field)
      return if value.is_a?(String) && PHONE.match?(value)

      raise InvalidRequestError.new("#{field} must be an E.164 Tanzanian number (+255 followed by nine digits)",
                                    field)
    end

    def amount(value, min, max, field)
      return if value.is_a?(Integer) && value.between?(min, max)

      raise InvalidRequestError.new("#{field} must be an integer between #{min} and #{max}", field)
    end

    def optional_amount(value, min, max, field)
      amount(value, min, max, field) unless value.nil?
    end

    def enum(value, field, allowed)
      return if value.nil? || allowed.include?(value)

      raise InvalidRequestError.new("#{field} must be one of #{allowed.join(", ")}", field)
    end

    def string(value, field, min, max)
      return if value.nil?
      return if value.is_a?(String) && value.length.between?(min, max) && !control?(value, true) && value.valid_encoding?

      raise InvalidRequestError.new("#{field} must be a string of #{min} to #{max} characters", field)
    end

    def metadata(value, field = "metadata")
      return if value.nil?
      raise InvalidRequestError.new("#{field} must be a Hash", field) unless value.is_a?(Hash)
      return unless JSON.generate(value).bytesize > MAX_METADATA_BYTES

      raise InvalidRequestError.new("#{field} must encode to at most #{MAX_METADATA_BYTES} bytes of JSON",
                                    field)
    end

    def loopback?(host)
      !host.nil? && LOOPBACK.include?(host.downcase)
    end

    def url(value, field, max_length)
      return if value.nil?
      if !value.is_a?(String) || value.length > max_length || value.match?(/\s/) || control?(value, false)
        raise InvalidRequestError.new("#{field} must be a URL of at most #{max_length} characters", field)
      end

      uri = begin
        URI.parse(value)
      rescue URI::InvalidURIError
        raise InvalidRequestError.new("#{field} must be an absolute URL", field)
      end
      raise InvalidRequestError.new("#{field} must be an absolute URL", field) unless uri.is_a?(URI::HTTP) && uri.host
      raise InvalidRequestError.new("#{field} must use https", field) unless uri.scheme == "https" || (uri.scheme == "http" && loopback?(uri.host))
    end

    def limit(limit)
      return if limit.nil? || (limit.is_a?(Integer) && limit.between?(1, 100))

      raise InvalidRequestError.new("limit must be an integer between 1 and 100", "limit")
    end

    def cursor(cursor)
      return if cursor.nil?
      return if cursor.is_a?(String) && cursor.length.between?(1, 200) && cursor.each_char.all? { |c| c.ord.between?(33, 126) }

      raise InvalidRequestError.new("cursor must be an opaque value returned by a previous list call", "cursor")
    end

    def query_value(key, value)
      raise InvalidRequestError, "Query parameter names must be alphanumeric" unless QUERY_KEY.match?(key)
      raise InvalidRequestError.new("#{key} has an invalid value", key) if value.length > 500 || control?(value, false)
    end

    def body_size(body)
      raise InvalidRequestError, "Request body exceeds the #{MAX_BODY_BYTES} byte limit" if body.bytesize > MAX_BODY_BYTES
    end

    def date_string(value, field)
      return if value.nil? || (value.is_a?(String) && DATE_TIME.match?(value))

      raise InvalidRequestError.new("#{field} must be an RFC 3339 timestamp or a YYYY-MM-DD date", field)
    end
  end
end
