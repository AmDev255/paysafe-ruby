# Examples

`examples.rb` holds the runnable examples; each reads `PAYSAFE_SECRET_KEY`:

```bash
PAYSAFE_SECRET_KEY=paysafe_test_... ruby examples/examples.rb auth
ruby examples/examples.rb create-payment +255712340000
ruby examples/examples.rb verify-webhook      # self-test against the shared vector
```

Names: `auth`, `create-payment`, `get-payment`, `list-payments`, `refund`, `payment-link`, `control-number`, `transfer`, `webhook-endpoints`, `events`, `customers-and-balance`, `verify-webhook`.

`webhooks/rails_controller.rb` and `webhooks/sinatra_app.rb` show the same verification inside Rails and Sinatra.
