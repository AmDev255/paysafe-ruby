# frozen_string_literal: true

RSpec.describe "security" do
  it "rejects ids that could change the path" do
    ["../balance", "pay_1/cancel", "pay_1?limit=1", "pay_1#x", "pay%2F1", "pay 1", "pay_1\n", "", "a" * 65, nil, 5].each do |id|
      h = Support::Harness.new
      expect { h.client.payments.get(id) }.to raise_error(PaySafe::InvalidRequestError)
      expect(h.request_count).to eq(0)
    end
  end

  it "encodes ids and query values" do
    h = Support::Harness.new.enqueue_json(200, Support.success_of(Support.fixture("getPayment"))[1])
                        .enqueue_json(200, Support.success_of(Support.fixture("listPayments"))[1])
    h.client.payments.get("pay_01J7A9Q0K3M4N5P6R7S8T9V0W1")
    expect(h.requests[0].uri.path).to eq("/v1/payments/pay_01J7A9Q0K3M4N5P6R7S8T9V0W1")
    h.client.payments.list(reference: "order&x=1 #2", limit: 5)
    expect(h.requests[1].uri.query_values).to eq("limit" => "5", "reference" => "order&x=1 #2")
  end

  it "rejects header injection and protected headers" do
    ["abc\r\nX-Injected: 1", "abc\nX", "abc\0"].each do |value|
      expect { PaySafe::RequestOptions.new(headers: { "X-Custom" => value }) }.to raise_error(PaySafe::InvalidRequestError)
    end
    expect { PaySafe::RequestOptions.new(idempotency_key: "key\r\nX: 1") }.to raise_error(PaySafe::InvalidRequestError)
    expect { PaySafe::RequestOptions.new(request_id: "bad id") }.to raise_error(PaySafe::InvalidRequestError)
    expect { PaySafe::RequestOptions.new(headers: { "authorization" => "Bearer other" }) }.to raise_error(PaySafe::InvalidRequestError)
    h = Support::Harness.new
    expect { h.client.balance.get(bogus: 1) }.to raise_error(PaySafe::InvalidRequestError)
    expect(h.request_count).to eq(0)
  end

  it "rejects unsafe base URLs" do
    ["http://api.paysafe.co.tz", "https://user:pass@api.paysafe.co.tz", "https://api.paysafe.co.tz/?x=1", "https://api.paysafe.co.tz/#x",
     "api.paysafe.co.tz", "https://api.paysafe.co.tz\n", "ftp://api.paysafe.co.tz"].each do |url|
      expect { PaySafe::Client.new(api_key: Support::TEST_KEY, base_url: url) }.to raise_error(PaySafe::ConfigurationError), url
    end
    PaySafe::Client.new(api_key: Support::TEST_KEY, base_url: "http://localhost:8088")
    PaySafe::Client.new(api_key: Support::TEST_KEY, base_url: "http://api.internal", allow_insecure_http: true)
    expect { PaySafe::Client.new(api_key: "#{Support::TEST_KEY}\n") }.to raise_error(PaySafe::ConfigurationError)
  end

  it "never follows redirects" do
    h = Support::Harness.new.enqueue_raw(302, "", "Location" => "https://evil.invalid/steal")
    expect { h.client.balance.get }.to raise_error(PaySafe::ApiError) { |e| expect(e.code).to eq("unexpected_redirect") }
    expect(h.request_count).to eq(1)
  end

  it "rejects oversized bodies and metadata before sending" do
    h = Support::Harness.new
    base = { amount: 10_000, customer: { phone: "+255712340000" } }
    expect { h.client.payments.create(base.merge(metadata: { big: "b" * 70_000 })) }.to raise_error(PaySafe::InvalidRequestError)
    expect { h.client.payments.create(base.merge(metadata: { x: "y" * 9000 })) }.to raise_error(PaySafe::InvalidRequestError)
    expect { h.client.payments.create(base.merge(metadata: "not a hash")) }.to raise_error(PaySafe::InvalidRequestError)
    expect(h.request_count).to eq(0)
  end

  it "validates amounts, phones and enums" do
    h = Support::Harness.new
    [0, 999, 10_000_001, -5, 10_000.0, "10000"].each do |amount|
      expect { h.client.payments.create(amount: amount, customer: { phone: "+255712340000" }) }
        .to raise_error(PaySafe::InvalidRequestError) { |e| expect(e.param).to eq("amount") }
    end
    ["0712340000", "+25571234000", "+255 712 340 000", "+1255712340000", "+255712340000\n", nil].each do |phone|
      expect { h.client.payments.create(amount: 10_000, customer: { phone: phone }) }
        .to raise_error(PaySafe::InvalidRequestError) { |e| expect(e.param).to eq("customer.phone") }
    end
    expect { h.client.payments.create(amount: 10_000, customer: { phone: "+255712340000" }, channel: "paypal") }.to raise_error(PaySafe::InvalidRequestError)
    expect { h.client.webhook_endpoints.create(url: "http://merchant.example/hook") }.to raise_error(PaySafe::InvalidRequestError)
    expect { h.client.payments.list(cursor: "c" * 201) }.to raise_error(PaySafe::InvalidRequestError)
    expect(h.request_count).to eq(0)
  end

  it "refuses oversized responses without retrying" do
    h = Support::Harness.new.enqueue_response(status: 200, body: "x", headers: { "Content-Length" => "16777217" })
    expect { h.client.balance.get }.to raise_error(PaySafe::ResponseTooLargeError)
    expect(h.request_count).to eq(1)
  end

  it "truncates non-JSON error bodies and never leaks the key" do
    h = Support::Harness.new(max_retries: 0).enqueue_raw(400, "<b>" * 5000, "Content-Type" => "text/html")
    expect { h.client.balance.get }.to raise_error(PaySafe::ApiError) do |e|
      expect(e.code).to eq("unknown")
      expect(e.details["raw"].length).to be <= 4096
      expect(e.to_s).not_to include(Support::TEST_KEY)
      expect(e.inspect).not_to include(Support::TEST_KEY)
    end
  end

  it "bounds webhook input sizes" do
    v = Support.fixture("webhook-vector")
    expect(PaySafe::Webhooks.verify_signature(v["secret"], "x" * 1_048_577, v["header"], now: v["nowValid"])).to be(false)
    expect(PaySafe::Webhooks.verify_signature(v["secret"], v["body"], "t" * 5000, now: v["nowValid"])).to be(false)
  end
end
