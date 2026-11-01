# frozen_string_literal: true

module PaySafe
  module Resources
    class Transfers < Base
      # Moves money from this project's available balance to another PaySafe project (201).
      def create(params, opts = {})
        p = Util.stringify(params)
        Validate.required(p["to"], "to")
        Validate.string(p["to"], "to", 3, 31)
        Validate.amount(p["amount"], 1, 2**62, "amount")
        Validate.enum(p["currency"], "currency", %w[TZS])
        Validate.string(p["note"], "note", 0, 140)
        decode(send("POST", path("transfers"), body: encode(p), opts: RequestOptions.with_key(opts)), Transfer)
      end

      def list(params = {}, opts = {})
        p = Util.stringify(params)
        Page.from_response(send("GET", path("transfers"), query: query(p), opts: opts), Transfer) { |cursor| list(p.merge("cursor" => cursor), opts) }
      end

      def get(id, opts = {})
        decode(send("GET", path("transfers", Validate.id(id)), opts: opts), Transfer)
      end

      def wait_for_terminal(id, interval: nil, timeout: nil, on_update: nil, should_stop: nil)
        Validate.id(id)
        poll(fetch: -> { get(id) }, terminal: lambda(&:terminal?), default_interval: 2.0, default_timeout: 120.0, what: "transfer #{id}",
             interval: interval, timeout: timeout, on_update: on_update, should_stop: should_stop)
      end
    end
  end
end
