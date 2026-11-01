# frozen_string_literal: true

module PaySafe
  module Resources
    class Customers < Base
      def list(params = {}, opts = {})
        p = Util.stringify(params)
        Validate.string(p["search"], "search", 0, 120)
        Page.from_response(send("GET", path("customers"), query: query(p, "search"), opts: opts), Customer) do |cursor|
          list(p.merge("cursor" => cursor), opts)
        end
      end

      def get(id, opts = {})
        decode(send("GET", path("customers", Validate.id(id)), opts: opts), Customer)
      end
    end
  end
end
