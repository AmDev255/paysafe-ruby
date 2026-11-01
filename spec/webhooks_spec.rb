# frozen_string_literal: true

RSpec.describe PaySafe::Webhooks do
  let(:v) { Support.fixture("webhook-vector") }
  let(:secret) { v["secret"] }
  let(:body) { v["body"] }
  let(:header) { v["header"] }
  let(:now) { v["nowValid"] }
  let(:ts) { v["timestamp"] }

  it "verifies the documented vector" do
    expect(described_class.verify_signature(secret, body, header, now: now)).to be(true)
    legacy = "t=#{ts},v1=#{v["legacy"]["signature"]}"
    expect(described_class.verify_signature(v["legacy"]["secret"], body, legacy, now: now)).to be(true)
    expect(described_class.verify_signature(secret, body, legacy, now: now)).to be(false)
  end

  it "rejects bad inputs" do
    sig = v["signature"]
    expect(described_class.verify_signature("paysafe_webhook_test_wrong", body, header, now: now)).to be(false)
    expect(described_class.verify_signature(secret, v["tamperedBody"], header, now: now)).to be(false)
    expect(described_class.verify_signature(secret, body, nil, now: now)).to be(false)
    expect(described_class.verify_signature(secret, body, "", now: now)).to be(false)
    expect(described_class.verify_signature(secret, body, "v1=#{sig}", now: now)).to be(false)
    expect(described_class.verify_signature(secret, body, "t=abc,v1=#{sig}", now: now)).to be(false)
    expect(described_class.verify_signature(secret, body, "t=#{ts}", now: now)).to be(false)
    expect(described_class.verify_signature(secret, body, header, now: v["nowExpired"])).to be(false)
    expect(described_class.verify_signature(secret, body, header, now: v["nowFuture"])).to be(false)
    expect(described_class.verify_signature(secret, body, header, tolerance: 1000, now: v["nowExpired"])).to be(true)
  end

  it "supports rotation headers and secret lists" do
    expect(described_class.verify_signature(secret, body, v["rotation"]["header"], now: now)).to be(true)
    second = "t=#{ts},v1=#{v["secondSecret"]["signature"]}"
    expect(described_class.verify_signature([secret, v["secondSecret"]["secret"]], body, second, now: now)).to be(true)
    expect(described_class.verify_signature(secret, body, second, now: now)).to be(false)
  end

  it "constructs a typed event" do
    e = described_class.construct_event(secret, body, header, now: now)
    expect(e).to be_a(PaySafe::Event)
    expect(e.id).to eq("evt_01J7A9R5VKM4N5P6R7S8T9V0B6")
    expect(e.type).to eq("payment.succeeded")
    expect(e.livemode).to be(false)
    expect(e.payment).to be_a(PaySafe::Payment)
    expect(e.payment.id).to eq("pay_01J7A9Q0K3M4N5P6R7S8T9V0W1")
    expect(e.payment.status).to eq("succeeded")
    expect(e.refund).to be_nil
  end

  it "raises with a reason and without the secret" do
    expect { described_class.construct_event(secret, v["tamperedBody"], header, now: now) }.to raise_error(PaySafe::SignatureVerificationError) do |e|
      expect(e.reason).to eq(PaySafe::SignatureVerificationError::SIGNATURE_MISMATCH)
      expect(e.message).not_to include(secret)
      expect(e.message).not_to include(v["signature"])
    end
    expect { described_class.construct_event(secret, body, header, now: v["nowExpired"]) }.to raise_error(PaySafe::SignatureVerificationError) do |e|
      expect(e.reason).to eq(PaySafe::SignatureVerificationError::TIMESTAMP_OUTSIDE_TOLERANCE)
    end
    list = "[1,2,3]"
    expect { described_class.construct_event(secret, list, described_class.sign(secret, list, ts), now: now) }
      .to raise_error(PaySafe::SignatureVerificationError) { |e| expect(e.reason).to eq(PaySafe::SignatureVerificationError::INVALID_PAYLOAD) }
    expect(described_class.sign(secret, body, ts)).to eq(header)
  end
end
