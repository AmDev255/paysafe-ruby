# frozen_string_literal: true

module PaySafe
  module Resources
    class PaymentLinks < Base
      STATUSES = %w[active paused archived].freeze

      def create(params, opts = {})
        p = Util.stringify(params)
        Validate.required(p["title"], "title")
        Validate.string(p["title"], "title", 2, 120)
        Validate.string(p["description"], "description", 1, 1000)
        Validate.optional_amount(p["amount"], Payments::MIN_AMOUNT, Payments::MAX_AMOUNT, "amount")
        Validate.optional_amount(p["min_amount"], Payments::MIN_AMOUNT, Payments::MAX_AMOUNT, "min_amount")
        Validate.optional_amount(p["max_amount"], Payments::MIN_AMOUNT, Payments::MAX_AMOUNT, "max_amount")
        Validate.enum(p["currency"], "currency", %w[TZS])
        Validate.optional_amount(p["max_payments"], 1, 1_000_000, "max_payments")
        Validate.date_string(p["expires_at"], "expires_at")
        Validate.string(p["success_message"], "success_message", 1, 255)
        Validate.url(p["redirect_url"], "redirect_url", 500)
        Validate.string(p["logo"], "logo", 0, 240)
        Validate.string(p["accent_color"], "accent_color", 0, 32)
        decode(send("POST", path("payment-links"), body: encode(p), opts: opts), PaymentLink)
      end

      def list(params = {}, opts = {})
        p = Util.stringify(params)
        Validate.enum(p["status"], "status", STATUSES)
        Page.from_response(send("GET", path("payment-links"), query: query(p, "status"), opts: opts), PaymentLink) do |cursor|
          list(p.merge("cursor" => cursor), opts)
        end
      end

      def get(id, opts = {})
        decode(send("GET", path("payment-links", Validate.id(id)), opts: opts), PaymentLink)
      end

      # Pause, resume, archive or edit a link. The amount cannot be changed; archiving is permanent.
      def update(id, params, opts = {})
        p = Util.stringify(params)
        Validate.string(p["title"], "title", 2, 120)
        Validate.enum(p["status"], "status", STATUSES)
        Validate.string(p["description"], "description", 1, 1000)
        Validate.optional_amount(p["max_payments"], 1, 1_000_000, "max_payments")
        Validate.date_string(p["expires_at"], "expires_at")
        Validate.string(p["success_message"], "success_message", 1, 255)
        Validate.url(p["redirect_url"], "redirect_url", 500)
        Validate.string(p["logo"], "logo", 0, 240)
        Validate.string(p["accent_color"], "accent_color", 0, 32)
        decode(send("PATCH", path("payment-links", Validate.id(id)), body: encode(p), opts: opts), PaymentLink)
      end

      def pause(id, opts = {})
        update(id, { status: "paused" }, opts)
      end

      def resume(id, opts = {})
        update(id, { status: "active" }, opts)
      end

      def archive(id, opts = {})
        update(id, { status: "archived" }, opts)
      end
    end
  end
end
