# frozen_string_literal: true

require_relative "lib/paysafe/version"

Gem::Specification.new do |s|
  s.name = "paysafe-tz"
  s.version = PaySafe::VERSION
  s.summary = "Official PaySafe Ruby SDK"
  s.description = "Mobile-money payments in Tanzania, refunds, control numbers, payment links, transfers and signed webhooks."
  s.authors = ["PaySafe"]
  s.homepage = "https://github.com/AmDev255/paysafe-ruby"
  s.license = "MIT"
  s.required_ruby_version = ">= 3.1"
  s.files = Dir["lib/**/*.rb"] + %w[LICENSE README.md CHANGELOG.md]
  s.require_paths = ["lib"]
  s.metadata = {
    "homepage_uri" => s.homepage,
    "source_code_uri" => s.homepage,
    "changelog_uri" => "#{s.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://paysafe.co.tz/docs",
    "bug_tracker_uri" => "#{s.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }
end
