# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-01

### Added

- Client with sandbox/production selection from the key prefix, configurable base URL, timeout, retries, logger and HTTP client.
- Payments: create, list, get, cancel, wait for terminal state.
- Payment links: create, list, get, update.
- Control numbers: create, list, get, cancel.
- Refunds: create, list, get, wait for terminal state.
- Balance and transactions.
- Customers: list, get.
- Transfers: create, list, get, wait for terminal state.
- Webhook endpoints: list, create, get, update, delete.
- Events: list, get.
- Webhook signature verification and event construction.
- Typed models for every API schema, structured errors per documented code, cursor pagination helpers.

API version: 2026-09-07.
