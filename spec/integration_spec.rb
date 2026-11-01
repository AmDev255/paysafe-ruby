# frozen_string_literal: true

# Runs against the real sandbox when PAYSAFE_SECRET_KEY holds a paysafe_test_ key. Never uses a live key.
RSpec.describe "sandbox integration", :live do
  before(:all) { skip "PAYSAFE_SECRET_KEY with a paysafe_test_ key is not set" unless ENV["PAYSAFE_SECRET_KEY"].to_s.start_with?("paysafe_test_") }

  let(:client) { PaySafe::Client.new.tap { |c| expect(c.environment).to eq(:test) } }

  def token
    SecureRandom.hex(4)
  end

  it "reads the balance and transactions" do
    b = client.balance.get
    expect(b.livemode).to be(false)
    expect(b.last_response.request_id).not_to be_nil
    expect(client.balance.transactions(limit: 5).size).to be <= 5
  end

  it "runs a payment through its lifecycle" do
    p = client.payments.create(amount: 10_000, customer: { phone: "+255712340000" }, reference: "sdk-ruby-#{token}")
    expect(p.last_response.status).to eq(202)
    done = client.payments.wait_for_terminal(p.id, timeout: 60)
    expect(done.status).to eq("succeeded")
    declined = client.payments.create(amount: 10_000, customer: { phone: "+255712341111" })
    failed = client.payments.wait_for_terminal(declined.id, timeout: 60)
    expect(failed.status).to eq("failed")
    expect(failed.failure["code"]).to eq("customer_declined")
    expect(client.payments.list(limit: 3).size).to be > 0
    expect(client.payments.get(p.id).id).to eq(p.id)
    expect { client.payments.cancel(p.id) }.to raise_error(PaySafe::InvalidStateError)
  end

  it "maps validation and not-found errors" do
    expect { client.request(:post, "/v1/payments", body: '{"amount":5}', idempotency_key: "sdk-ruby-bad-#{token}") }.to raise_error(PaySafe::ValidationError)
    expect { client.payments.get("pay_00000000000000000000000000") }.to raise_error(PaySafe::NotFoundError)
  end

  it "round-trips a webhook endpoint" do
    created = client.webhook_endpoints.create(url: "https://example.com/paysafe/#{token}", events: ["payment.succeeded"])
    expect(created.secret).to start_with("paysafe_webhook_")
    expect(client.webhook_endpoints.update(created.id, status: "DISABLED").status).to eq("DISABLED")
    expect(client.webhook_endpoints.list.map(&:id)).to include(created.id)
    client.webhook_endpoints.delete(created.id)
    expect { client.webhook_endpoints.get(created.id) }.to raise_error(PaySafe::NotFoundError)
  end

  it "reads events and customers" do
    client.events.list(limit: 2).each { |e| expect(client.events.get(e.id).id).to eq(e.id) }
    client.customers.list(limit: 2).each { |c| expect(client.customers.get(c.id).id).to eq(c.id) }
  end
end
