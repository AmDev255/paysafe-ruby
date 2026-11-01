# frozen_string_literal: true

RSpec.describe PaySafe::Client do
  let(:balance) { Support.success_of(Support.fixture("getBalance"))[1] }

  it "derives the environment from the key prefix" do
    expect(described_class.new(api_key: Support::TEST_KEY).environment).to eq(:test)
    expect(described_class.new(api_key: "paysafe_live_9f2Kx7Qm3Rt8Vw2Yz5Ab1Cd4Ef6Gh9Jk").environment).to eq(:live)
    expect { described_class.new(api_key: "sk_test_abc") }.to raise_error(PaySafe::ConfigurationError)
    expect(PaySafe.new(api_key: Support::TEST_KEY)).to be_a(described_class)
  end

  it "sends the standard headers" do
    h = Support::Harness.new.enqueue_json(200, balance)
    h.client.balance.get
    req = h.requests.first
    expect(Support.header(req, "Authorization")).to eq("Bearer #{Support::TEST_KEY}")
    expect(Support.header(req, "Accept")).to eq("application/json")
    expect(Support.header(req, "User-Agent")).to start_with("paysafe-ruby/#{PaySafe::VERSION}")
    expect(Support.header(req, "Content-Type")).to be_nil
    expect(req.uri.path).to eq("/v1/balance")
  end

  it "sends the PaySafe-Version header when configured" do
    h = Support::Harness.new(api_version: "2026-09-07").enqueue_json(200, balance)
    h.client.balance.get
    expect(Support.header(h.requests.first, "PaySafe-Version")).to eq("2026-09-07")
  end

  it "exposes response metadata on models" do
    h = Support::Harness.new.enqueue_json(200, balance, "X-RateLimit-Limit" => "50", "X-RateLimit-Remaining" => "49",
                                                        "X-RateLimit-Reset" => "1788775205")
    b = h.client.balance.get
    expect(b.last_response.status).to eq(200)
    expect(b.last_response.request_id).to eq(Support::REQUEST_ID)
    expect(b.last_response.rate_limit.remaining).to eq(49)
    expect(b.last_response.idempotent_replayed?).to be(false)
    expect(b.to_json).not_to include("last_response")
    expect(b.livemode).to be(false)
    expect(b[:object]).to eq("balance")
  end

  it "offers a low-level request method" do
    h = Support::Harness.new.enqueue_json(200, balance)
    r = h.client.request(:get, "v1/balance")
    expect(r.status).to eq(200)
    expect(h.requests.first.uri.path).to eq("/v1/balance")
  end

  it "logs attempts without secrets" do
    records = []
    h = Support::Harness.new(logger: ->(r) { records << r }).enqueue_json(200, balance)
    h.client.balance.get
    expect(records.size).to eq(1)
    expect(records.first.http_method).to eq("GET")
    expect(records.first.path).to eq("/v1/balance")
    expect(records.first.status).to eq(200)
    expect(records.first.to_s).not_to include(Support::TEST_KEY)
    expect(h.client.inspect).not_to include(Support::TEST_KEY)
  end
end
