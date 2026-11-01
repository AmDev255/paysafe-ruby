# frozen_string_literal: true

# Sinatra endpoint for PaySafe webhooks: `PAYSAFE_WEBHOOK_SECRET=... ruby examples/webhooks/sinatra_app.rb`.
require "set"
require "sinatra"
require "paysafe"

SECRET = ENV.fetch("PAYSAFE_WEBHOOK_SECRET")
SEEN = Set.new

post "/paysafe/webhook" do
  raw_body = request.body.read # exact bytes, never parsed JSON
  begin
    event = PaySafe::Webhooks.construct_event(SECRET, raw_body, request.env["HTTP_PAYSAFE_SIGNATURE"])
  rescue PaySafe::SignatureVerificationError => e
    halt 400, "invalid signature: #{e.reason}"
  end
  halt 200, "duplicate" unless SEEN.add?(event.id)

  case event.type
  when "payment.succeeded" then puts "paid #{event.payment.id} #{event.payment.amount}" # mark the order paid
  when "payment.failed", "payment.expired" then puts "not paid: #{event.type}"
  else puts "ignored #{event.type}"
  end
  "ok"
end
