# frozen_string_literal: true

module PaySafe
  module Resources
    class ControlNumbers < Base
      MAX_AMOUNT = 1_000_000_000_000
      STATUSES = %w[active paid expired cancelled].freeze
      STATES = %w[unpaid partial paid overdue].freeze
      MODES = %w[full instalment].freeze

      # Issues a 12-digit pay-by-reference number (201). The number itself is assigned by the server.
      def create(params, opts = {})
        p = Util.stringify(params)
        Validate.required(p["payer_name"], "payer_name")
        Validate.required(p["title"], "title")
        Validate.string(p["payer_name"], "payer_name", 1, 120)
        Validate.string(p["payer_phone"], "payer_phone", 0, 20)
        Validate.string(p["payer_email"], "payer_email", 0, 255)
        Validate.string(p["payer_reference"], "payer_reference", 0, 120)
        Validate.string(p["title"], "title", 1, 150)
        Validate.string(p["description"], "description", 0, 500)
        Validate.string(p["reference"], "reference", 0, 120)
        Validate.string(p["payment_type"], "payment_type", 0, 60)
        Validate.string(p["notes"], "notes", 0, 1000)
        Validate.string(p["image"], "image", 0, 240)
        Validate.enum(p["mode"], "mode", MODES)
        Validate.enum(p["currency"], "currency", %w[TZS])
        Validate.amount(p["amount"], 1, MAX_AMOUNT, "amount")
        Validate.metadata(p["metadata"])
        Validate.date_string(p["expires_at"], "expires_at")
        unless p["instalments"].nil?
          list = p["instalments"]
          raise InvalidRequestError.new("instalments must be a non-empty list", "instalments") unless list.is_a?(Array) && !list.empty?

          list.each_with_index do |item, i|
            raise InvalidRequestError.new("instalments[#{i}] must be a Hash", "instalments") unless item.is_a?(Hash)

            Validate.amount(item["amount"], 1, MAX_AMOUNT, "instalments[#{i}].amount")
            Validate.required(item["due_at"], "instalments[#{i}].due_at")
            Validate.date_string(item["due_at"], "instalments[#{i}].due_at")
          end
        end
        decode(send("POST", path("control-numbers"), body: encode(p), opts: opts), ControlNumber)
      end

      def list(params = {}, opts = {})
        p = Util.stringify(params)
        Validate.enum(p["status"], "status", STATUSES)
        Validate.enum(p["state"], "state", STATES)
        Validate.string(p["q"], "q", 0, 80)
        q = query(p, "status", "state", "batch", "customer", "q")
        Page.from_response(send("GET", path("control-numbers"), query: q, opts: opts), ControlNumber) do |cursor|
          list(p.merge("cursor" => cursor), opts)
        end
      end

      # The number with every payment entry recorded against it.
      def get(id, opts = {})
        decode(send("GET", path("control-numbers", Validate.id(id)), opts: opts), ControlNumber)
      end

      # Only active numbers can be cancelled; the reason (3 to 500 characters) is kept on the number.
      def cancel(id, reason, opts = {})
        Validate.required(reason, "reason")
        Validate.string(reason, "reason", 3, 500)
        decode(send("POST", path("control-numbers", Validate.id(id), "cancel"), body: encode({ "reason" => reason }), opts: opts), ControlNumber)
      end
    end
  end
end
