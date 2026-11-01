# frozen_string_literal: true

RSpec.describe "API contract" do
  ID = "pay_01J7A9Q0K3M4N5P6R7S8T9V0W1"
  KEYED = { idempotency_key: "order-8812-attempt-1" }.freeze

  CALLS = {
    "createPayment" => ->(c, f) { c.payments.create(f["body"], KEYED) },
    "listPayments" => ->(c, f) { c.payments.list(f["query"]) },
    "getPayment" => ->(c, _) { c.payments.get(ID) },
    "cancelPayment" => ->(c, f) { c.payments.cancel(ID, f["body"]&.dig("reason"), KEYED) },
    "createPaymentLink" => ->(c, f) { c.payment_links.create(f["body"]) },
    "listPaymentLinks" => ->(c, f) { c.payment_links.list(f["query"]) },
    "getPaymentLink" => ->(c, _) { c.payment_links.get(ID) },
    "updatePaymentLink" => ->(c, f) { c.payment_links.update(ID, f["body"]) },
    "createControlNumber" => ->(c, f) { c.control_numbers.create(f["body"]) },
    "listControlNumbers" => ->(c, f) { c.control_numbers.list(f["query"]) },
    "getControlNumber" => ->(c, _) { c.control_numbers.get(ID) },
    "cancelControlNumber" => ->(c, f) { c.control_numbers.cancel(ID, f["body"]["reason"]) },
    "createRefund" => ->(c, f) { c.refunds.create(f["body"], KEYED) },
    "listRefunds" => ->(c, f) { c.refunds.list(f["query"]) },
    "getRefund" => ->(c, _) { c.refunds.get(ID) },
    "getBalance" => ->(c, _) { c.balance.get },
    "listTransactions" => ->(c, f) { c.balance.transactions(f["query"]) },
    "listCustomers" => ->(c, f) { c.customers.list(f["query"]) },
    "getCustomer" => ->(c, _) { c.customers.get(ID) },
    "createTransfer" => ->(c, f) { c.transfers.create(f["body"], KEYED) },
    "listTransfers" => ->(c, f) { c.transfers.list(f["query"]) },
    "getTransfer" => ->(c, _) { c.transfers.get(ID) },
    "listWebhookEndpoints" => ->(c, _) { c.webhook_endpoints.list },
    "createWebhookEndpoint" => ->(c, f) { c.webhook_endpoints.create(f["body"]) },
    "getWebhookEndpoint" => ->(c, _) { c.webhook_endpoints.get(ID) },
    "updateWebhookEndpoint" => ->(c, f) { c.webhook_endpoints.update(ID, f["body"]) },
    "deleteWebhookEndpoint" => ->(c, _) { c.webhook_endpoints.delete(ID) },
    "listEvents" => ->(c, f) { c.events.list(f["query"].transform_keys { |k| k == "resourceId" ? "resource_id" : k }) },
    "getEvent" => ->(c, _) { c.events.get(ID) }
  }.freeze

  OPERATIONS = Support.fixture("index")["operations"].map { |o| o["operationId"] }

  it "has a call for every served operation" do
    expect(CALLS.keys.sort).to eq(OPERATIONS.sort)
  end

  OPERATIONS.each do |op|
    it "#{op}: sends the documented request and parses the success response" do
      f = Support.fixture(op)
      code, body, headers = Support.success_of(f)
      h = Support::Harness.new.enqueue_json(code, body, headers)
      result = CALLS[op].call(h.client, f)
      req = h.requests.first
      expect(req.method.to_s.upcase).to eq(f["method"])
      expect(req.uri.path).to eq(f["resolvedPath"])
      want = f["query"].compact.transform_values(&:to_s)
      expect(req.uri.query_values || {}).to eq(want)
      expect(Support.header(req, "Authorization")).to eq("Bearer #{Support::TEST_KEY}")
      if f["headers"].key?("Idempotency-Key")
        expect(Support.header(req, "Idempotency-Key")).to eq("order-8812-attempt-1")
      else
        expect(Support.header(req, "Idempotency-Key")).to be_nil
      end
      if f["body"]
        expect(Support.header(req, "Content-Type")).to start_with("application/json")
        expect(JSON.parse(req.body)).to eq(f["body"])
      else
        expect(req.body.to_s).to eq("")
      end
      if body.nil?
        expect(result).to be_nil
      elsif body["object"] == "list" && op != "listWebhookEndpoints"
        expect(result).to be_a(PaySafe::Page)
        expect(result.size).to eq(body["data"].size)
        expect(result.has_more?).to eq(body["has_more"])
        expect(result.first.last_response.request_id).to eq(Support::REQUEST_ID) if result.size.positive?
      elsif op == "listWebhookEndpoints"
        expect(result.size).to eq(body["data"].size)
      else
        expect(result).to be_a(PaySafe::ApiObject)
        expect(result.last_response.request_id).to eq(Support::REQUEST_ID)
        expect(result.to_h).to eq(body)
      end
    end

    it "#{op}: raises the mapped error for every documented error response" do
      f = Support.fixture(op)
      f["responses"].each do |code, r|
        next if code.start_with?("2")

        status = code.split("_").first.to_i
        h = Support::Harness.new(max_retries: 0).enqueue_json(status, r["body"], r["headers"] || {})
        expect { CALLS[op].call(h.client, f) }.to raise_error(PaySafe::ApiError) do |e|
          expect(e.status).to eq(status)
          expect(e.code).to eq(r["code"])
          expect(e.request_id).to eq(r["body"]["error"]["request_id"])
          expect(e.retry_after).to eq(r["headers"]["Retry-After"].to_i) if r["headers"]&.key?("Retry-After")
          expect(e.headers).not_to be_empty
        end
      end
    end
  end
end
