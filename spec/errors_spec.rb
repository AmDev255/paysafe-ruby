# frozen_string_literal: true

RSpec.describe PaySafe::ApiError do
  CASES = [
    [400, "validation_error", PaySafe::ValidationError, false],
    [401, "authentication_error", PaySafe::AuthenticationError, false],
    [403, "permission_error", PaySafe::PermissionError, false],
    [403, "feature_disabled", PaySafe::FeatureDisabledError, false],
    [404, "not_found", PaySafe::NotFoundError, false],
    [402, "insufficient_funds", PaySafe::InsufficientFundsError, false],
    [409, "conflict", PaySafe::ConflictError, false],
    [409, "idempotency_conflict", PaySafe::IdempotencyConflictError, false],
    [409, "idempotency_in_progress", PaySafe::IdempotencyInProgressError, true],
    [409, "invalid_state", PaySafe::InvalidStateError, false],
    [429, "rate_limited", PaySafe::RateLimitError, true],
    [502, "provider_error", PaySafe::ProviderError, false],
    [503, "provider_unavailable", PaySafe::ProviderUnavailableError, true],
    [503, "service_unavailable", PaySafe::ServiceUnavailableError, true],
    [500, "internal_error", PaySafe::InternalError, true]
  ].freeze

  it "maps every documented code to its class" do
    CASES.each do |status, code, klass, retryable|
      body = { error: { code: code, message: "m", request_id: "req_1", param: "amount", details: { scope: "api:key" },
                        doc_url: "https://paysafe.co.tz/docs/errors##{code}" } }
      h = Support::Harness.new(max_retries: 0).enqueue_json(status, body, "Retry-After" => "3")
      expect { h.client.balance.get }.to raise_error(klass) do |e|
        expect(e.class).to eq(klass)
        expect(e.status).to eq(status)
        expect(e.code).to eq(code)
        expect(e.message).to eq("m")
        expect(e.request_id).to eq("req_1")
        expect(e.param).to eq("amount")
        expect(e.details["scope"]).to eq("api:key")
        expect(e.retry_after).to eq(3)
        expect(e.retryable?).to be(retryable)
        expect(e.to_s).to include(code)
      end
    end
  end

  it "falls back to the HTTP status for unknown codes" do
    h = Support::Harness.new(max_retries: 0)
                        .enqueue_json(404, { error: { code: "brand_new", message: "x", request_id: "r" } })
                        .enqueue_json(418, { error: { code: "teapot", message: "x", request_id: "r" } })
                        .enqueue_raw(500, "oops", "X-Request-ID" => "req_h")
    expect { h.client.balance.get }.to raise_error(PaySafe::NotFoundError) { |e| expect(e.code).to eq("brand_new") }
    expect { h.client.balance.get }.to raise_error(PaySafe::ApiError) { |e| expect(e.class).to eq(PaySafe::ApiError) }
    expect { h.client.balance.get }.to raise_error(PaySafe::InternalError) do |e|
      expect(e.request_id).to eq("req_h")
      expect(e.code).to eq("unknown")
    end
  end

  it "offers helpers on specific errors" do
    h = Support::Harness.new(max_retries: 0)
                        .enqueue_json(403, { error: { code: "permission_error", message: "x", request_id: "r",
                                                      details: { code: "ip_not_allowed", ip: "2a02::1" } } })
                        .enqueue_json(402, { error: { code: "insufficient_funds", message: "x", request_id: "r",
                                                      details: { available: 10, requested: 20 } } })
    expect { h.client.balance.get }.to raise_error(PaySafe::PermissionError) do |e|
      expect(e.ip_not_allowed?).to be(true)
      expect(e.observed_ip).to eq("2a02::1")
    end
    expect { h.client.balance.get }.to raise_error(PaySafe::InsufficientFundsError) do |e|
      expect(e.available).to eq(10)
      expect(e.requested).to eq(20)
    end
  end
end
