# Security policy

## Reporting a vulnerability

Email security@paysafe.co.tz with a description of the issue, the affected version and steps to reproduce. Do not open a public issue for security problems. You will receive an acknowledgement within two business days.

## Scope

This repository contains the PaySafe Ruby SDK. Issues in the PaySafe API or dashboard should also go to the address above.

## Handling secrets

- Secret keys (`paysafe_test_…`, `paysafe_live_…`) and webhook secrets must stay on your server. The SDK never logs them.
- Rotate any key that has been committed to source control or pasted into a chat or ticket.
- Verify webhook signatures before parsing a delivery; the SDK provides `verifySignature` and `constructEvent` for this.

## Supported versions

The latest minor release receives security fixes.
