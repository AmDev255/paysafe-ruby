# frozen_string_literal: true

# Runnable examples: `PAYSAFE_SECRET_KEY=paysafe_test_... ruby examples/examples.rb <name> [args]`.
require "json"
require "securerandom"
require "tmpdir"
require_relative "../lib/paysafe"

module Examples
  module_function

  # Proves the key works with a read-only call and prints the rate-limit budget.
  def auth
    client = PaySafe::Client.new
    balance = client.balance.get
    puts "Environment : #{client.environment}"
    puts "Available   : TZS #{balance.available_amount}"
    puts "Pending     : TZS #{balance.pending_amount}"
    puts "Rate limit  : #{balance.last_response.rate_limit&.remaining || "?"} remaining of #{balance.last_response.rate_limit&.limit || "?"}"
    puts "Request id  : #{balance.last_response.request_id}"
  rescue PaySafe::ApiError => e
    warn "API error #{e}"
  end

  # Creates a TZS 10,000 payment with a persisted idempotency key, then polls until it is terminal.
  def create_payment(phone)
    order_id = "order-#{SecureRandom.hex(4)}"
    # Store the key with the order before sending, so a crash and restart reuses it instead of charging twice.
    key_file = File.join(Dir.tmpdir, "paysafe-#{order_id}.key")
    key = File.exist?(key_file) ? File.read(key_file) : "#{order_id}-attempt-1"
    File.write(key_file, key)
    client = PaySafe::Client.new
    payment = client.payments.create(
      { amount: 10_000, currency: "TZS", customer: { phone: phone, name: "Amina Juma" }, reference: order_id,
        description: "Order #{order_id}", metadata: { order_id: order_id } },
      idempotency_key: key
    )
    replayed = payment.last_response.idempotent_replayed? ? ", replayed" : ""
    puts "Created #{payment.id} status=#{payment.status} (HTTP #{payment.last_response.status}#{replayed})"
    done = client.payments.wait_for_terminal(payment.id, on_update: ->(s) { puts "  #{s}" })
    puts(done.successful? ? "Paid: amount #{done.amount} fee #{done.fee} net #{done.net}" : "Not paid: #{done.status} #{done.failure&.dig("code")}")
  rescue PaySafe::PollingTimeoutError
    puts "Still pending after the timeout; rely on the webhook"
  rescue PaySafe::ApiError => e
    warn "API error #{e}"
  ensure
    File.delete(key_file) if key_file && File.exist?(key_file)
  end

  # Retrieves a payment by id and waits for a terminal state.
  def get_payment(id)
    client = PaySafe::Client.new
    payment = client.payments.get(id)
    puts "#{payment.id} #{payment.status} TZS #{payment.amount} for #{payment.customer&.dig("phone")}"
    return if payment.terminal?

    puts "Final status: #{client.payments.wait_for_terminal(payment.id).status}"
  rescue PaySafe::NotFoundError
    warn "No such payment in this project and environment"
  end

  # Lists succeeded payments from the last 7 days, walking every page.
  def list_payments
    client = PaySafe::Client.new
    page = client.payments.list(status: "succeeded", created_gte: (Time.now.utc - (7 * 86_400)).strftime("%Y-%m-%dT%H:%M:%SZ"), limit: 50)
    total = 0
    page.auto_paging_each do |p|
      puts "#{p.created_at} #{p.id} TZS #{p.amount} #{p.reference}"
      total += p.amount
    end
    puts "Total: TZS #{total}"
  end

  # Refunds part of a succeeded payment and waits for the result.
  def refund(payment_id, amount)
    client = PaySafe::Client.new
    refund = client.refunds.create({ payment: payment_id, amount: amount, reason: "requested_by_customer" },
                                   idempotency_key: "refund-#{payment_id}-1")
    puts "Refund #{refund.id} #{refund.status}"
    done = client.refunds.wait_for_terminal(refund.id)
    puts "Final: #{done.status} #{done.failure_reason}"
  rescue PaySafe::InsufficientFundsError => e
    puts "Not enough available balance: have #{e.available}, need #{e.requested}"
  rescue PaySafe::InvalidStateError => e
    puts "Cannot refund: #{e.message}"
  end

  # Creates a hosted payment link, lists links, then pauses and archives the new one.
  def payment_link
    client = PaySafe::Client.new
    link = client.payment_links.create(title: "Workshop ticket", description: "One seat, Saturday session", amount: 25_000, collect_name: true,
                                       collect_email: true, max_payments: 50,
                                       expires_at: (Time.now.utc + (14 * 86_400)).strftime("%Y-%m-%dT%H:%M:%SZ"))
    puts "Share this: #{link.url} (#{link.id})"
    client.payment_links.list(status: "active", limit: 10).each { |l| puts "#{l.id} #{l.title} paid #{l.paid_count}/#{l.max_payments || "∞"}" }
    paused = client.payment_links.pause(link.id)
    puts "Paused: #{paused.status} state=#{paused.state}"
    puts "Archived: #{client.payment_links.archive(link.id).status}"
  end

  # Issues a control number for an invoice, reads it back with its payment entries, then cancels it.
  def control_number
    client = PaySafe::Client.new
    number = client.control_numbers.create(
      payer_name: "Amina Juma", payer_phone: "+255712340000", payer_reference: "STU-2024-0091", title: "Term 2 school fees",
      reference: "INV-2026-0042", payment_type: "fees", mode: "instalment", amount: 450_000, expires_at: "2026-12-31",
      instalments: [{ amount: 225_000, due_at: "2026-11-30T00:00:00Z" }, { amount: 225_000, due_at: "2026-12-31T00:00:00Z" }]
    )
    puts "Control number #{number.formatted} (#{number.id}) pay at #{number.pay_url}"
    detail = client.control_numbers.get(number.id)
    puts "Balance TZS #{detail.balance}, #{detail.entries.size} entries, #{detail.payment_status}"
    detail.entries.each { |e| puts "  #{e["paid_at"]} #{e["status"]} #{e["amount"]} via #{e["method"]}" }
    client.control_numbers.list(state: "unpaid", limit: 5).each { |n| puts "#{n.formatted} #{n.payer["name"]} owes #{n.balance}" }
    puts "Cancelled: #{client.control_numbers.cancel(number.id, "Issued in error during SDK example").status}"
  end

  # Sends TZS 5,000 to another PaySafe project by handle and lists recent transfers.
  def transfer(to)
    client = PaySafe::Client.new
    begin
      t = client.transfers.create({ to: to, amount: 5000, note: "Shared delivery cost" },
                                  idempotency_key: "transfer-#{to}-#{Time.now.utc.strftime("%F")}")
      puts "Transfer #{t.id} #{t.status} to #{t.to["name"]} (#{t.to["organization"]})"
      puts "Review finished: #{client.transfers.wait_for_terminal(t.id).status}" unless t.terminal?
    rescue PaySafe::InsufficientFundsError => e
      puts "Not enough available balance (have #{e.available})"
    end
    client.transfers.list(limit: 5).each { |x| puts "#{x.created_at} #{x.direction} #{x.amount} #{x.status}" }
  end

  # Registers a webhook endpoint, stores its secret, disables it and deletes it again.
  def webhook_endpoints(url)
    client = PaySafe::Client.new
    endpoint = client.webhook_endpoints.create(url: url, description: "Order fulfilment",
                                               events: %w[payment.succeeded payment.failed refund.succeeded])
    # The secret is returned once. Put it in your secret store as PAYSAFE_WEBHOOK_SECRET.
    puts "Endpoint #{endpoint.id} created; secret starts with #{endpoint.secret[0, 20]}…"
    client.webhook_endpoints.list.each { |e| puts "#{e.id} #{e.status} #{e.url} streak=#{e.failure_streak}" }
    puts "Now #{client.webhook_endpoints.update(endpoint.id, status: "DISABLED").status}"
    client.webhook_endpoints.delete(endpoint.id)
    puts "Deleted"
  end

  # Lists recent payment events and shows the delivery attempts for the newest one.
  def events
    client = PaySafe::Client.new
    events = client.events.list(type: "payment.succeeded", from: (Time.now.utc - 86_400).strftime("%Y-%m-%dT%H:%M:%SZ"), limit: 10)
    events.each { |e| puts "#{e.created_at} #{e.id} #{e.payment&.id}" }
    return if events.empty?

    client.events.get(events.first.id).deliveries.each do |d|
      puts "  attempt #{d["attempt"]} #{d["status"]} HTTP #{d["response_status"] || "-"} #{d["latency_ms"] || "-"}ms"
    end
  end

  # Reads the balance, the latest ledger entries and recent customers.
  def customers_and_balance
    client = PaySafe::Client.new
    balance = client.balance.get
    puts "Available TZS #{balance.available_amount}, pending TZS #{balance.pending_amount}"
    client.balance.transactions(limit: 5).each { |tx| puts "#{tx.created_at} #{tx.direction} #{tx.bucket} #{tx.amount} -> #{tx.balance_after}" }
    client.customers.list(limit: 5).each { |c| puts "#{c.id} #{c.phone} paid #{c.payment_count || 0} times, TZS #{c.total_paid || 0}" }
  end

  # Verifies the shared webhook test vector; see examples/webhooks/ for servers.
  def verify_webhook_self_test
    v = JSON.parse(File.read(File.expand_path("../tests/fixtures/webhook-vector.json", __dir__)))
    event = PaySafe::Webhooks.construct_event(v["secret"], v["body"], v["header"], now: v["nowValid"])
    puts "Self-test ok: #{event.type} #{event.payment&.id}"
  end
end

if $PROGRAM_NAME == __FILE__
  name, *rest = ARGV
  case name || "auth"
  when "auth" then Examples.auth
  when "create-payment" then Examples.create_payment(rest[0] || "+255712340000")
  when "get-payment" then Examples.get_payment(rest.fetch(0))
  when "list-payments" then Examples.list_payments
  when "refund" then Examples.refund(rest.fetch(0), rest[1]&.to_i)
  when "payment-link" then Examples.payment_link
  when "control-number" then Examples.control_number
  when "transfer" then Examples.transfer(rest.fetch(0))
  when "webhook-endpoints" then Examples.webhook_endpoints(rest.fetch(0))
  when "events" then Examples.events
  when "customers-and-balance" then Examples.customers_and_balance
  when "verify-webhook" then Examples.verify_webhook_self_test
  else abort "unknown example #{name}"
  end
end
