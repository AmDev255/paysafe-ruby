# Contributing

Thanks for helping improve the PaySafe Ruby SDK.

## Before you start

- The API contract is the PaySafe OpenAPI specification. The SDK never invents behaviour the API does not document.
- Changes to request or response shapes must match a documented API change. Open an issue first if the docs and the API disagree.
- Keep the public surface consistent with the other PaySafe SDKs (same resources, same operation names in the language's casing).

## Development

```bash
bundle install
```

Run the whole gate before opening a pull request:

```bash
bundle exec rubocop && bundle exec rspec
```

Tests use recorded fixtures under `tests/fixtures/` shared by every PaySafe SDK; do not edit them by hand. Integration tests need `PAYSAFE_SECRET_KEY` (a `paysafe_test_` key) and optionally `PAYSAFE_BASE_URL`; they are skipped when the key is absent. Never use a live key in tests.

## Pull requests

- One change per pull request, with tests.
- Add an entry to `CHANGELOG.md` under Unreleased.
- Do not bump the package version; maintainers do that at release time.
- Never commit API keys, webhook secrets or `.env` files.

## Code style

Formatting and linting are enforced in CI; run the formatter before committing. Prefer small functions and explicit names over comments.
