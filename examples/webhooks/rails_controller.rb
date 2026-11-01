# frozen_string_literal: true

# Rails controller for PaySafe webhooks. Reviewed, not run in this repository.
# routes.rb: post "/paysafe/webhook", to: "paysafe_webhooks#create"
# Skip CSRF for this endpoint: PaySafe signs the body instead.
class PaysafeWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    raw_body = request.raw_post # exact bytes, never params
    event = PaySafe::Webhooks.construct_event(ENV.fetch("PAYSAFE_WEBHOOK_SECRET"), raw_body, request.headers["PaySafe-Signature"])
    return head :ok if WebhookEvent.exists?(event_id: event.id) # deduplicate

    WebhookEvent.create!(event_id: event.id, type: event.type)
    case event.type
    when "payment.succeeded"
      Order.find_by(reference: event.payment.reference)&.mark_paid!(event.payment.id)
    when "payment.failed", "payment.expired"
      Order.find_by(reference: event.payment.reference)&.mark_failed!(event.type)
    end
    head :ok
  rescue PaySafe::SignatureVerificationError => e
    render plain: "invalid signature: #{e.reason}", status: :bad_request
  end
end
