# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "securerandom"
require "time"
require "uri"

require_relative "paysafe/version"
require_relative "paysafe/errors"
require_relative "paysafe/util"
require_relative "paysafe/validate"
require_relative "paysafe/api_response"
require_relative "paysafe/request_options"
require_relative "paysafe/models"
require_relative "paysafe/page"
require_relative "paysafe/webhooks"
require_relative "paysafe/client"
require_relative "paysafe/resources/base"
require_relative "paysafe/resources/payments"
require_relative "paysafe/resources/payment_links"
require_relative "paysafe/resources/control_numbers"
require_relative "paysafe/resources/refunds"
require_relative "paysafe/resources/balance"
require_relative "paysafe/resources/customers"
require_relative "paysafe/resources/transfers"
require_relative "paysafe/resources/webhook_endpoints"
require_relative "paysafe/resources/events"

# Official PaySafe SDK. Start with PaySafe::Client.new(api_key: "paysafe_test_...").
module PaySafe
  def self.new(**options)
    Client.new(**options)
  end
end
