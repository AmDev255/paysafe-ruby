# frozen_string_literal: true

RSpec.describe "pagination and polling" do
  let(:payment) { Support.success_of(Support.fixture("getPayment"))[1] }

  def list(items, has_more, cursor)
    { "object" => "list", "data" => items, "has_more" => has_more, "next_cursor" => cursor }
  end

  it "auto-pages while keeping filters" do
    h = Support::Harness.new
                        .enqueue_json(200, list([payment.merge("id" => "pay_1"), payment.merge("id" => "pay_2")], true, "c2"))
                        .enqueue_json(200, list([payment.merge("id" => "pay_3")], false, nil))
    page = h.client.payments.list(status: "succeeded", limit: 2)
    expect(page.size).to eq(2)
    expect(page.has_more?).to be(true)
    expect(page.auto_paging_each.map(&:id)).to eq(%w[pay_1 pay_2 pay_3])
    expect(h.request_count).to eq(2)
    expect(h.requests[1].uri.query_values).to eq("limit" => "2", "cursor" => "c2", "status" => "succeeded")
  end

  it "has no next page at the end" do
    h = Support::Harness.new.enqueue_json(200, list([], false, nil))
    page = h.client.customers.list
    expect(page.next_page).to be_nil
    expect(page.size).to eq(0)
    expect(page.to_a).to eq([])
  end

  it "reports status updates while waiting" do
    h = Support::Harness.new
    %w[pending processing processing succeeded].each { |s| h.enqueue_json(200, payment.merge("status" => s)) }
    seen = []
    p = h.client.payments.wait_for_terminal("pay_01J7A9Q0K3M4N5P6R7S8T9V0W1", on_update: ->(s) { seen << s })
    expect(p.status).to eq("succeeded")
    expect(p.successful?).to be(true)
    expect(seen).to eq(%w[pending processing succeeded])
    expect(h.sleeps).to eq([2.0, 2.0, 2.0])
  end

  it "times out with the last object" do
    h = Support::Harness.new
    4.times { h.enqueue_json(200, payment.merge("status" => "processing")) }
    expect { h.client.payments.wait_for_terminal("pay_01J7A9Q0K3M4N5P6R7S8T9V0W1", interval: 2, timeout: 6) }
      .to raise_error(PaySafe::PollingTimeoutError) { |e| expect(e.last_seen.status).to eq("processing") }
    expect(h.request_count).to eq(4)
  end

  it "can be cancelled" do
    h = Support::Harness.new.enqueue_json(200, Support.success_of(Support.fixture("getRefund"))[1].merge("status" => "pending"))
    expect { h.client.refunds.wait_for_terminal("rfd_01J7A9Q0K3M4N5P6R7S8T9V0W1", should_stop: -> { true }) }.to raise_error(PaySafe::PollingTimeoutError)
  end

  it "slows down after thirty seconds" do
    h = Support::Harness.new
    transfer = Support.success_of(Support.fixture("getTransfer"))[1]
    20.times { h.enqueue_json(200, transfer.merge("status" => "in_review")) }
    h.enqueue_json(200, transfer.merge("status" => "completed"))
    h.client.transfers.wait_for_terminal("trf_01J7A9Q0K3M4N5P6R7S8T9V0W1")
    expect(h.sleeps.first).to eq(2.0)
    expect(h.sleeps.last).to eq(5.0)
  end
end
