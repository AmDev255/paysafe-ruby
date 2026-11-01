# frozen_string_literal: true

module PaySafe
  module Resources
    class Events < Base
      def list(params = {}, opts = {})
        p = Util.stringify(params)
        Validate.enum(p["type"], "type", Event::TYPES)
        Validate.date_string(p["from"], "from")
        Validate.date_string(p["to"], "to")
        Validate.id(p["resource_id"], "resource_id") if p["resource_id"]
        q = query(p, "type", "from", "to")
        q["resourceId"] = p["resource_id"] if p["resource_id"]
        Page.from_response(send("GET", path("events"), query: q, opts: opts), Event) { |cursor| list(p.merge("cursor" => cursor), opts) }
      end

      # The event plus every delivery attempt to your endpoints.
      def get(id, opts = {})
        decode(send("GET", path("events", Validate.id(id)), opts: opts), Event)
      end
    end
  end
end
