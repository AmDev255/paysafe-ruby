# frozen_string_literal: true

module PaySafe
  module Resources
    class Balance < Base
      def get(opts = {})
        decode(send("GET", path("balance"), opts: opts), PaySafe::Balance)
      end

      # Ledger entries, newest first.
      def transactions(params = {}, opts = {})
        p = Util.stringify(params)
        Page.from_response(send("GET", path("transactions"), query: query(p), opts: opts), Transaction) do |cursor|
          transactions(p.merge("cursor" => cursor), opts)
        end
      end
    end
  end
end
