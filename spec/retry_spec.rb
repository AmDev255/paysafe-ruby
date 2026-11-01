# frozen_string_literal: true

RSpec.describe "retry policy" do
  ERRORS = {
    "ApiError" => PaySafe::ApiError,
    "ApiConnectionError" => PaySafe::ApiConnectionError,
    "IdempotencyConflictError" => PaySafe::IdempotencyConflictError,
    "ValidationError" => PaySafe::ValidationError,
    "InternalError" => PaySafe::InternalError,
    "ProviderError" => PaySafe::ProviderError
  }.freeze

  def call(client, op, f)
    case op
    when "getBalance" then client.balance.get
    when "getPayment" then client.payments.get("pay_01J7A9Q0K3M4N5P6R7S8T9V0W1")
    when "listPayments" then client.payments.list
    when "createPayment" then client.payments.create(f["minimalBody"])
    when "createRefund" then client.refunds.create(f["minimalBody"])
    when "createWebhookEndpoint" then client.webhook_endpoints.create(f["minimalBody"])
    else raise "unsupported operation #{op}"
    end
  end

  Support.fixture("retry-scenarios")["scenarios"].each do |sc|
    it sc["name"] do
      f = Support.fixture(sc["request"])
      code, body, headers = Support.success_of(f)
      has_timeout = sc["sequence"].any? { |s| s["timeout"] }
      h = Support::Harness.new(timeout: has_timeout ? 0.3 : 30)
      sc["sequence"].each do |step|
        if step["networkError"] then h.enqueue_disconnect
        elsif step["timeout"] then h.enqueue_hang
        elsif step.key?("rawBody") then h.enqueue_raw(step["status"], step["rawBody"], "Content-Type" => "text/html")
        elsif step["status"] < 300 then h.enqueue_json(code, body, headers.merge(step["headers"] || {}))
        else
          ec = step["code"] || "internal_error"
          h.enqueue_json(step["status"], { error: { code: ec, message: ec, request_id: "req_x" } }, step["headers"] || {})
        end
      end
      expect = sc["expect"]
      result = nil
      raised = nil
      begin
        result = call(h.client, sc["request"], f)
      rescue PaySafe::Error => e
        raised = e
      end
      if expect["error"]
        expect(raised).to be_a(ERRORS[expect["error"]]), "expected #{expect["error"]}, got #{raised.inspect}"
        expect(raised.code).to eq(expect["code"]) if expect["code"]
      else
        expect(raised).to be_nil, raised.inspect
      end
      expect(h.request_count).to eq(expect["attempts"])
      if expect["sameIdempotencyKey"]
        keys = h.requests.map { |r| Support.header(r, "Idempotency-Key") }.uniq
        expect(keys.size).to eq(1)
        expect(keys.first).not_to be_empty
      end
      expect(h.total_sleep * 1000).to be >= expect["sleptAtLeastMs"] if expect["sleptAtLeastMs"]
      expect(result.last_response.idempotent_replayed?).to eq(expect["idempotentReplayed"]) unless expect["idempotentReplayed"].nil?
    end
  end

  it "distinguishes timeouts" do
    h = Support::Harness.new(max_retries: 0, timeout: 0.3).enqueue_hang
    expect { h.client.balance.get }.to raise_error(PaySafe::ApiTimeoutError)
  end

  it "honours per-request max_retries and reuses a generated key" do
    h = Support::Harness.new.enqueue_json(503, { error: { code: "service_unavailable", message: "x", request_id: "r" } })
    expect { h.client.payments.create({ amount: 10_000, customer: { phone: "+255712340000" } }, idempotency_key: "k-1", max_retries: 0) }
      .to raise_error(PaySafe::ServiceUnavailableError)
    expect(h.request_count).to eq(1)
    code, body, headers = Support.success_of(Support.fixture("createPayment"))
    h.enqueue_json(500, { error: { code: "internal_error", message: "x", request_id: "r" } }).enqueue_json(code, body, headers)
    p = h.client.payments.create(amount: 10_000, customer: { phone: "+255712340000" })
    key = p.last_response.idempotency_key
    expect(key.length).to eq(36)
    expect(Support.header(h.requests[1], "Idempotency-Key")).to eq(key)
    expect(Support.header(h.requests[2], "Idempotency-Key")).to eq(key)
  end
end
