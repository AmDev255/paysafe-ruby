# frozen_string_literal: true

module PaySafe
  # Read-only view of an API object. Fields are reachable as methods or with [] (string or symbol keys);
  # nested objects stay plain Hashes with string keys.
  class ApiObject
    attr_accessor :last_response

    def initialize(data)
      @data = data.is_a?(Hash) ? data : {}
    end

    def self.from(data, response = nil)
      obj = new(data)
      obj.last_response = response
      obj
    end

    def [](key)
      @data[key.to_s]
    end

    def key?(key)
      @data.key?(key.to_s)
    end

    def to_h
      @data
    end

    def to_json(*args)
      @data.to_json(*args)
    end

    def ==(other)
      other.is_a?(ApiObject) && other.to_h == @data
    end

    def inspect
      "#<#{self.class.name} #{@data.slice("id", "object", "status").map { |k, v| "#{k}=#{v.inspect}" }.join(" ")}>"
    end

    def method_missing(name, *args)
      key = name.to_s
      return @data[key] if args.empty? && @data.key?(key)

      super
    end

    def respond_to_missing?(name, include_private = false)
      @data.key?(name.to_s) || super
    end
  end

  class Payment < ApiObject
    TERMINAL_STATUSES = %w[succeeded failed cancelled expired partially_refunded refunded].freeze
    SUCCESSFUL_STATUSES = %w[succeeded partially_refunded refunded].freeze

    def terminal?
      TERMINAL_STATUSES.include?(self["status"])
    end

    def successful?
      SUCCESSFUL_STATUSES.include?(self["status"])
    end
  end

  class PaymentLink < ApiObject; end

  class ControlNumber < ApiObject
    def terminal?
      %w[paid expired cancelled].include?(self["status"])
    end

    def entries
      Array(self["entries"])
    end
  end

  class Refund < ApiObject
    def terminal?
      %w[succeeded failed rejected].include?(self["status"])
    end

    def successful?
      self["status"] == "succeeded"
    end
  end

  class Transfer < ApiObject
    def terminal?
      %w[completed rejected reversed].include?(self["status"])
    end
  end

  class Balance < ApiObject
    def available_amount(currency = "TZS")
      Array(self["available"]).find { |m| m["currency"] == currency }&.dig("amount") || 0
    end

    def pending_amount(currency = "TZS")
      Array(self["pending"]).find { |m| m["currency"] == currency }&.dig("amount") || 0
    end
  end

  class Transaction < ApiObject; end
  class Customer < ApiObject; end

  class WebhookEndpoint < ApiObject
    def enabled?
      self["status"] == "ENABLED"
    end
  end

  class Event < ApiObject
    TYPES = %w[
      payment.pending payment.processing payment.requires_action payment.succeeded payment.failed payment.expired payment.cancelled
      refund.pending refund.succeeded refund.failed
      payout.processing payout.paid payout.failed
      transfer.sent transfer.received transfer.in_review transfer.rejected transfer.reversed
      control_number.partially_paid control_number.paid control_number.expired control_number.cancelled
    ].freeze

    def data_object
      self["data"].is_a?(Hash) && self["data"]["object"].is_a?(Hash) ? self["data"]["object"] : {}
    end

    def payment
      decode_if("payment.", Payment)
    end

    def refund
      decode_if("refund.", Refund)
    end

    def transfer
      decode_if("transfer.", Transfer)
    end

    def control_number
      decode_if("control_number.", ControlNumber)
    end

    def deliveries
      Array(self["deliveries"])
    end

    private

    def decode_if(prefix, klass)
      self["type"].to_s.start_with?(prefix) ? klass.from(data_object, last_response) : nil
    end
  end
end
