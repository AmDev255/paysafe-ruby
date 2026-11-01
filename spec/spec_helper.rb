# frozen_string_literal: true

require "webmock/rspec"
require "paysafe"
require_relative "support"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :defined
  config.before(:each, :live) { WebMock.allow_net_connect! }
  config.after(:each, :live) { WebMock.disable_net_connect! }
end
