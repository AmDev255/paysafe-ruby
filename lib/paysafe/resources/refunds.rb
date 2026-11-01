# frozen_string_literal: true

module PaySafe
  module Resources
    class Refunds < Base
      REASONS = %w[requested_by_customer duplicate fraudulent other].freeze
      STATUSES = %w[pending processing succeeded failed rejected].freeze

      # Refunds a succeeded payment (202 Accepted). Omit amount to refund the remaining balance.
      def create(params, opts = {})
        p = Util.stringify(params)
        Validate.id(p["payment"], "payment")
        Validate.optional_amount(p["amount"], 1, 2**62, "amount")
        Validate.enum(p["reason"], "reason", REASONS)
        Validate.metadata(p["metadata"])
        decode(send("POST", path("refunds"), body: encode(p), opts: RequestOptions.with_key(opts)), Refund)
      end

      def list(params = {}, opts = {})
        p = Util.stringify(params)
        Validate.enum(p["status"], "status", STATUSES)
        Validate.id(p["payment"], "payment") if p["payment"]
        Page.from_response(send("GET", path("refunds"), query: query(p, "payment", "status"), opts: opts), Refund) do |cursor|
          list(p.merge("cursor" => cursor), opts)
        end
      end

      def get(id, opts = {})
        decode(send("GET", path("refunds", Validate.id(id)), opts: opts), Refund)
      end

      def wait_for_terminal(id, interval: nil, timeout: nil, on_update: nil, should_stop: nil)
        Validate.id(id)
        poll(fetch: -> { get(id) }, terminal: lambda(&:terminal?), default_interval: 1.0, default_timeout: 60.0, what: "refund #{id}",
             interval: interval, timeout: timeout, on_update: on_update, should_stop: should_stop)
      end
    end
  end
end
