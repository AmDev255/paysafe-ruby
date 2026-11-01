# PaySafe Ruby SDK

Official Ruby library for the [PaySafe](https://paysafe.co.tz) payments API. Accept mobile-money payments in Tanzania, issue refunds, control numbers and payment links, move money between projects, and receive signed webhooks.

Part of the [PaySafe SDK directory](https://github.com/AmDev255/paysafe-sdks). API reference: https://paysafe.co.tz/docs.

## Features

- Every served PaySafe API operation (29 operations, 10 resources) with typed request and response models
- Sandbox and production selected automatically from the key prefix
- Safe retries that honour `Retry-After`, idempotency keys that survive retries, cursor pagination helpers
- Polling helpers that wait for a payment, refund or transfer to reach a terminal state
- Webhook signature verification with secret rotation support and constant-time comparison
- One structured exception per documented error code, every error carries the request id
- Configurable timeouts, base URL, logger and HTTP client

## Installation

```bash
gem install paysafe-tz
# or in your Gemfile
gem "paysafe-tz"
```

## Requirements

Ruby 3.1 or newer. Uses `Net::HTTP` from the standard library.

## Authentication

Create a secret key in the dashboard under API keys. Test keys start with `paysafe_test_`, live keys with `paysafe_live_`. Keep keys on the server; never ship them in browsers or mobile apps. The SDK reads `PAYSAFE_SECRET_KEY` when no key is passed.

## Sandbox setup

Use a `paysafe_test_` key. The sandbox is the same API with a simulated provider; the last four digits of the customer phone choose the outcome (`0000` succeeds, `1111` is declined, `4444` expires, see the [Sandbox guide](https://paysafe.co.tz/docs/sandbox)).

## Production setup

Switch to a `paysafe_live_` key once your organisation is verified. Register a live webhook endpoint and add your server's address to the project's IP allowlist. Nothing else changes.

## Quickstart

```ruby
require "paysafe"

client = PaySafe::Client.new(api_key: ENV.fetch("PAYSAFE_SECRET_KEY")) # paysafe_test_… selects the sandbox

payment = client.payments.create(
  { amount: 10_000, customer: { phone: "+255712340000", name: "Amina Juma" }, reference: "order-8812" }, # TZS, integer
  idempotency_key: "order-8812-attempt-1" # persist the key before calling
)
puts "#{payment.id} #{payment.status}" # 202 Accepted: still pending

done = client.payments.wait_for_terminal(payment.id) # or wait for the webhook
puts "Paid, net TZS #{done.net}" if done.successful?
```

## Supported API resources

| Resource | Operations |
|---|---|
| Payments | create, list, get, cancel, waitForTerminal |
| Payment links | create, list, get, update |
| Control numbers | create, list, get, cancel |
| Refunds | create, list, get, waitForTerminal |
| Balance | get, transactions |
| Customers | list, get |
| Transfers | create, list, get, waitForTerminal |
| Webhook endpoints | list, create, get, update, delete |
| Events | list, get |
| Webhooks | verifySignature, constructEvent |

Planned by PaySafe and not yet served (not included): `ping`, payouts (`createPayout`, `getPayout`), `rotateWebhookEndpointSecret`.

## Usage examples

Runnable programs live in [`examples/examples.rb`](examples/examples.rb) (see [`examples/README.md`](examples/README.md)): authentication, creating and polling a payment, listing with pagination, refunds, payment links, control numbers, transfers, webhook endpoints, events, customers and balance, and a webhook self-test, plus Rails and Sinatra handlers under `examples/webhooks/`.

Every resource takes a params Hash (symbol or string keys, snake_case like the API) and an optional options Hash (`idempotency_key`, `request_id`, `timeout`, `max_retries`, `headers`). Lists return a `PaySafe::Page` (Enumerable) with `data`, `has_more?`, `next_cursor`, `next_page` and `auto_paging_each`.

```ruby
# Pagination
client.payments.list(status: "succeeded", limit: 100).auto_paging_each { |p| }

# Refunds
refund = client.refunds.create(payment: payment.id, amount: 5000, reason: "requested_by_customer")

# Payment links and control numbers
link = client.payment_links.create(title: "Workshop ticket", amount: 25_000)
number = client.control_numbers.create(payer_name: "Amina Juma", title: "Term 2 fees", amount: 450_000)

# Transfers, balance, customers, events
transfer = client.transfers.create(to: "merchant_shop", amount: 5000)
balance = client.balance.get
customer = client.customers.get("cus_…")
event = client.events.get("evt_…")

# Webhook endpoints (the secret is returned once)
endpoint = client.webhook_endpoints.create(url: "https://example.com/paysafe", events: ["payment.succeeded"])
```

Responses are `PaySafe::ApiObject` instances (`Payment`, `Refund`, …): fields are readable as methods (`payment.amount`) or with `[]`; nested objects are plain Hashes with string keys; `to_h` and `to_json` give the raw data. Every object carries `last_response` with `status`, `request_id`, `rate_limit`, `idempotent_replayed?` and the `idempotency_key` that was sent. The client is thread-safe and uses `Net::HTTP` with certificate verification always on.

Retries: 429 and 503 wait for `Retry-After`; `idempotency_in_progress` waits one second; 5xx and network errors are retried only when the request is idempotent (GET, PATCH, DELETE, or a POST with an idempotency key). The SDK generates a UUID key for `payments.create`, `refunds.create`, `transfers.create` and `payments.cancel` when you do not pass one; pass your own key derived from the order to survive process restarts.

Security: ids, filters, headers and amounts are validated before any request (amounts must be Integers); path and query values are percent-encoded; the base URL must be https (plain http only for localhost or `allow_insecure_http: true`); redirects are never followed; response bodies are capped at 16 MB; JSON is parsed with `JSON.parse` only; the key never appears in exceptions, `inspect` or logs.

## Error handling

Every non-2xx response raises a subclass of `PaySafe::ApiError` chosen by the error code, with `status`, `code`, `message`, `request_id`, `param`, `details`, `doc_url`, `retry_after` and `rate_limit`:

```ruby
begin
  client.payments.cancel(id)
rescue PaySafe::ValidationError => e     # 400: fix the request (e.param names the field)
rescue PaySafe::InvalidStateError => e   # 409: read the object and decide again
rescue PaySafe::RateLimitError => e      # 429 after retries: back off e.retry_after seconds
rescue PaySafe::ApiError => e            # anything else from the API; e.to_s is "code (status) message [request_id]"
rescue PaySafe::ApiConnectionError => e  # no response at all (DNS, TLS, timeout: ApiTimeoutError)
rescue PaySafe::InvalidRequestError => e # rejected locally before any request was sent
end
```

Classes: ValidationError, AuthenticationError, PermissionError (`ip_not_allowed?`, `observed_ip`), FeatureDisabledError, NotFoundError, InsufficientFundsError (`available`, `requested`), ConflictError, IdempotencyConflictError, IdempotencyInProgressError, InvalidStateError, RateLimitError (`scope`), ProviderError, ProviderUnavailableError, ServiceUnavailableError, InternalError, ApiConnectionError, ApiTimeoutError, ResponseTooLargeError, SignatureVerificationError, PollingTimeoutError, ConfigurationError, InvalidRequestError. Unknown codes map by HTTP status.

## Webhook integration

Verify the raw body before parsing it. `PaySafe::Webhooks.construct_event` checks the `PaySafe-Signature` header (HMAC-SHA256 over `t.body`, 300 s tolerance, constant-time comparison, several `v1=` values during rotation) and returns a typed `PaySafe::Event`:

```ruby
raw_body = request.raw_post # exact bytes, never params
begin
  event = PaySafe::Webhooks.construct_event(ENV.fetch("PAYSAFE_WEBHOOK_SECRET"), raw_body, request.headers["PaySafe-Signature"])
  mark_paid(event.payment.reference) if event.type == "payment.succeeded" # deduplicate on event.id first
rescue PaySafe::SignatureVerificationError
  head :bad_request
end
```

`PaySafe::Webhooks.verify_signature` returns a boolean instead of raising; both accept an Array of secrets and a `tolerance:` keyword. `examples/webhooks/` holds a Rails controller and a Sinatra app, and `ruby examples/examples.rb verify-webhook` runs the self-test.

## Testing

```bash
bundle install
bundle exec rubocop && bundle exec rspec && gem build paysafe-tz.gemspec
```

Tests run offline against the fixtures in `tests/fixtures/` that are shared by every PaySafe SDK, with HTTP stubbed by WebMock. The integration specs run only when `PAYSAFE_SECRET_KEY` holds a `paysafe_test_` key (and optionally `PAYSAFE_BASE_URL`); they refuse live keys and use the sandbox phone suffixes documented at https://paysafe.co.tz/docs/sandbox. See `examples/README.md` for the runnable examples.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
