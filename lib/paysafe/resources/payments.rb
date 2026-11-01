# frozen_string_literal: true

module PaySafe
  module Resources
    class Payments < Base
      MIN_AMOUNT = 1000
      MAX_AMOUNT = 10_000_000
      CHANNELS = %w[mpesa tigopesa airtel halopesa].freeze
      STATUSES = %w[created pending processing requires_action succeeded failed cancelled expired partially_refunded refunded].freeze

      # Starts a mobile-money charge (202 Accepted). An Idempotency-Key is generated when opts has none;
      # read it from payment.last_response.idempotency_key and persist it before retrying yourself.
      def create(params, opts = {})
        p = Util.stringify(params)
        Validate.amount(p["amount"], MIN_AMOUNT, MAX_AMOUNT, "amount")
        Validate.phone(p.dig("customer", "phone"), "customer.phone")
        Validate.string(p.dig("customer", "name"), "customer.name", 1, 100)
        Validate.string(p.dig("customer", "email"), "customer.email", 3, 255)
        Validate.enum(p["currency"], "currency", %w[TZS])
        Validate.enum(p["channel"], "channel", CHANNELS)
        Validate.string(p["reference"], "reference", 1, 120)
        Validate.string(p["description"], "description", 1, 255)
        Validate.metadata(p["metadata"])
        Validate.optional_amount(p["expires_in"], 60, 900, "expires_in")
        decode(send("POST", path("payments"), body: encode(p), opts: RequestOptions.with_key(opts)), Payment)
      end

      def list(params = {}, opts = {})
        p = Util.stringify(params)
        Validate.enum(p["status"], "status", STATUSES)
        q = query(p, "status", "reference", "customer_phone", "created_gte", "created_lte")
        Page.from_response(send("GET", path("payments"), query: q, opts: opts), Payment) { |cursor| list(p.merge("cursor" => cursor), opts) }
      end

      def get(id, opts = {})
        decode(send("GET", path("payments", Validate.id(id)), opts: opts), Payment)
      end

      # Only payments in created or pending can be cancelled. The API requires an Idempotency-Key here.
      def cancel(id, reason = nil, opts = {})
        Validate.string(reason, "reason", 0, 255)
        body = reason.nil? ? {} : { "reason" => reason }
        decode(send("POST", path("payments", Validate.id(id), "cancel"), body: encode(body), opts: RequestOptions.with_key(opts)), Payment)
      end

      # Polls get until the payment is terminal (default every 2 s, up to 2 min).
      def wait_for_terminal(id, interval: nil, timeout: nil, on_update: nil, should_stop: nil)
        Validate.id(id)
        poll(fetch: -> { get(id) }, terminal: lambda(&:terminal?), default_interval: 2.0, default_timeout: 120.0, what: "payment #{id}",
             interval: interval, timeout: timeout, on_update: on_update, should_stop: should_stop)
      end
    end
  end
end
