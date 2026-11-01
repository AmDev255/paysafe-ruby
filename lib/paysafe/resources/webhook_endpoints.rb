# frozen_string_literal: true

module PaySafe
  module Resources
    class WebhookEndpoints < Base
      # Every endpoint of the project; the API does not paginate this resource.
      def list(opts = {})
        response = send("GET", path("webhook-endpoints"), opts: opts)
        Array(response.json&.dig("data")).grep(Hash).map { |e| WebhookEndpoint.from(e, response) }
      end

      # Registers an endpoint. The signing secret is only returned here; store it immediately.
      def create(params, opts = {})
        p = Util.stringify(params)
        Validate.required(p["url"], "url")
        Validate.url(p["url"], "url", 500)
        Validate.string(p["description"], "description", 0, 255)
        validate_events(p["events"])
        decode(send("POST", path("webhook-endpoints"), body: encode(p), opts: opts), WebhookEndpoint)
      end

      def get(id, opts = {})
        decode(send("GET", path("webhook-endpoints", Validate.id(id)), opts: opts), WebhookEndpoint)
      end

      def update(id, params, opts = {})
        p = Util.stringify(params)
        Validate.url(p["url"], "url", 500)
        Validate.string(p["description"], "description", 0, 255)
        Validate.enum(p["status"], "status", %w[ENABLED DISABLED])
        validate_events(p["events"])
        decode(send("PATCH", path("webhook-endpoints", Validate.id(id)), body: encode(p), opts: opts), WebhookEndpoint)
      end

      def delete(id, opts = {})
        send("DELETE", path("webhook-endpoints", Validate.id(id)), opts: opts)
        nil
      end

      private

      def validate_events(events)
        return if events.nil?
        unless events.is_a?(Array) && !events.empty?
          raise InvalidRequestError.new('events must be a non-empty list of event types or ["*"]',
                                        "events")
        end

        events.each do |e|
          raise InvalidRequestError.new("Unknown event type #{e}", "events") unless e == "*" || Event::TYPES.include?(e)
        end
      end
    end
  end
end
