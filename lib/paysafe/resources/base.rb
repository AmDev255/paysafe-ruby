# frozen_string_literal: true

module PaySafe
  module Resources
    class Base
      MIN_INTERVAL = 0.5
      SLOW_AFTER = 30.0
      SLOW_INTERVAL = 5.0

      def initialize(client)
        @client = client
      end

      private

      def path(*segments)
        "/v1#{segments.map { |s| "/#{Util.encode(s)}" }.join}"
      end

      def send(method, path, query: {}, body: nil, opts: {})
        @client.send_request(method, path, query, body, opts)
      end

      def decode(response, klass)
        data = response.json
        unless data
          raise ApiError.new(status: response.status, code: "invalid_json", message: "The API returned a body this SDK could not parse",
                             request_id: response.request_id, headers: response.headers)
        end

        klass.from(data, response)
      end

      def encode(params)
        JSON.generate(params)
      end

      def query(params, *extra)
        Validate.limit(params["limit"])
        Validate.cursor(params["cursor"])
        q = {}
        q["limit"] = params["limit"].to_s if params["limit"]
        q["cursor"] = params["cursor"] if params["cursor"]
        extra.each do |key|
          value = params[key]
          q[key] = value.to_s if value && !value.to_s.empty?
        end
        q
      end

      def poll(fetch:, terminal:, default_interval:, default_timeout:, what:, interval: nil, timeout: nil, on_update: nil, should_stop: nil)
        interval = [interval || default_interval, MIN_INTERVAL].max
        timeout ||= default_timeout
        waited = 0.0
        last = nil
        first = true
        loop do
          obj = fetch.call
          status = obj["status"]
          on_update&.call(status) if first || status != last
          first = false
          last = status
          return obj if terminal.call(obj)
          raise PollingTimeoutError.new("Polling for #{what} was cancelled", obj) if should_stop&.call
          raise PollingTimeoutError.new("#{what} did not reach a terminal state within #{timeout} s", obj) if waited >= timeout

          delay = interval
          delay = SLOW_INTERVAL if waited >= SLOW_AFTER && delay < SLOW_INTERVAL
          delay = [delay, timeout - waited].min
          @client.pause(delay)
          waited += delay
        end
      end
    end
  end
end
