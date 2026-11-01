# frozen_string_literal: true

module PaySafe
  # Webhook signature verification: HMAC-SHA256 over "timestamp.rawBody", constant-time comparison.
  module Webhooks
    SIGNATURE_HEADER = "PaySafe-Signature"
    DEFAULT_TOLERANCE_SECONDS = 300
    MAX_HEADER_BYTES = 4096
    MAX_PAYLOAD_BYTES = 1024 * 1024

    module_function

    # Builds a PaySafe-Signature value. Intended for tests.
    def sign(secret, payload, timestamp)
      "t=#{timestamp},v1=#{hmac_hex(secret, timestamp, payload)}"
    end

    # True when the raw payload was signed by the secret (or one of the secrets) within the tolerance window. Never raises.
    def verify_signature(secret, payload, header, tolerance: DEFAULT_TOLERANCE_SECONDS, now: nil)
      check(Array(secret), payload, header, tolerance, now)
      true
    rescue SignatureVerificationError
      false
    end

    # Verifies the delivery and returns the typed Event. Raises SignatureVerificationError with a reason.
    def construct_event(secret, payload, header, tolerance: DEFAULT_TOLERANCE_SECONDS, now: nil)
      check(Array(secret), payload, header, tolerance, now)
      parsed = Util.parse_json(payload.to_s)
      unless parsed.is_a?(Hash) && parsed["id"].is_a?(String) && parsed["type"].is_a?(String)
        raise SignatureVerificationError.new(SignatureVerificationError::INVALID_PAYLOAD, "Webhook payload is not an event object")
      end

      Event.from(parsed)
    end

    def check(secrets, payload, header, tolerance, now)
      payload = payload.to_s
      if header.nil? || header.strip.empty?
        raise SignatureVerificationError.new(SignatureVerificationError::MISSING_HEADER,
                                             "PaySafe-Signature header is missing")
      end
      if header.bytesize > MAX_HEADER_BYTES || payload.bytesize > MAX_PAYLOAD_BYTES
        raise SignatureVerificationError.new(SignatureVerificationError::MALFORMED_HEADER, "Webhook header or payload is too large")
      end

      timestamp = nil
      signatures = []
      header.split(",").each do |part|
        key, value = part.split("=", 2)
        next if value.nil?

        key = key.strip
        value = value.strip
        timestamp = value if key == "t"
        signatures << value.downcase if key == "v1"
      end
      if timestamp.nil? || !timestamp.match?(/\A\d+\z/) || signatures.empty?
        raise SignatureVerificationError.new(SignatureVerificationError::MALFORMED_HEADER, "PaySafe-Signature header is malformed")
      end

      t = timestamp.to_i
      current = now || Time.now.to_i
      if (current - t).abs > tolerance
        raise SignatureVerificationError.new(SignatureVerificationError::TIMESTAMP_OUTSIDE_TOLERANCE,
                                             "Webhook timestamp is outside the tolerance window")
      end

      secrets.each do |s|
        expected = hmac_hex(s, t, payload)
        signatures.each do |sig|
          return true if sig.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(expected, sig)
        end
      end
      raise SignatureVerificationError.new(SignatureVerificationError::SIGNATURE_MISMATCH, "Webhook signature does not match")
    end
    private_class_method :check

    def hmac_hex(secret, timestamp, payload)
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, "#{timestamp}.#{payload}")
    end
    private_class_method :hmac_hex
  end
end
