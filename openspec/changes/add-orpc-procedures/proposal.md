## Why

Some Rails applications want oRPC-style procedures and typed errors as well as
contract export. They need an optional Ruby handler layer compatible with the
real oRPC RPC client, without introducing a Node server or replacing Rails
request context and authentication.

## What Changes

- Add opt-in Ruby procedures with declared input, output and business errors.
- Mount a JSON-only, POST-only oRPC v1 RPC endpoint explicitly in Rails.
- Add selected-controller RPC export/check tasks without changing HTTP exports.
- Validate input/output against the shared IR plus explicit bounded wire rules.
- Preserve Rails callbacks/CSRF and per-request context; keep earlier Rails
  denials separate from gem dispatch/codec error envelopes.
- Verify successful and failed calls with the official TypeScript `RPCLink`.

## Capabilities

### New Capabilities

- `rails-orpc-procedures`: Optional procedure declarations, Rails dispatch,
  validation, request context and safe typed errors.
- `orpc-rpc-transport`: A bounded v1 JSON wire profile tested against RPCLink.

### Modified Capabilities

None. This adds an optional layer without changing export-only requirements.

## Impact

Depends on [export-rails-contracts](../export-rails-contracts/proposal.md)
for schemas, registry, generator and the gem/Testcontainers harness.
That baseline now passes packaged-gem acceptance on both locked Rails targets.
Prerequisite gates remain wire/parser/lifecycle probes, separate from actual
product acceptance. The implemented codec, runtime validation and selected
procedure exporter now pass installed-gem echo/null/declared-error acceptance
with generated contracts on both locked targets; tasks.md records coverage.

Adds Ruby procedure/controller integration and a codec for the JSON subset of
stable oRPC v1. Generated procedure contracts use the same Zod/oRPC imports;
clients additionally use `@orpc/client/fetch` for `RPCLink`.
No new Ruby runtime dependency, Node service or database is required.

This optional second slice remains an unarchived change, not a published
release or full support for all oRPC transports, serializers and plugins.
