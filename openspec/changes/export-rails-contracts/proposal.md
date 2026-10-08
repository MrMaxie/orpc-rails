## Why

Rails developers need usable Zod/oRPC contracts for their existing JSON
endpoints without rewriting controllers or running a TypeScript backend.
The repository has no gem implementation yet; this change defines the first
working export-only slice and its cross-language acceptance tests.

## What Changes

- Add explicit endpoint declarations and a small Ruby schema DSL.
- Generate deterministic TypeScript Zod schemas and an oRPC contract router.
- Call conventional Rails routes with the official oRPC `OpenAPILink`.
- Keep controller execution, validation, authentication and rendering unchanged.
- Establish Ruby gem packaging and Testcontainers compatibility checks.
- Target stable oRPC v1 and Zod v4 first; do not mix in v2 beta APIs.

## Capabilities

### New Capabilities

- `rails-contract-export`: Explicit Rails endpoint registration, supported
  schemas, deterministic generation and usable HTTP client contracts.
- `gem-compatibility-testing`: Installable gem, dependency boundaries and
  reproducible Rails/TypeScript acceptance tests using Testcontainers.

### Modified Capabilities

None. There are no accepted capability specs to modify.

## Impact

Implementation will add the `orpc-rails` gemspec, namespaced Ruby library,
Rails integration and export tasks, unit tests, a minimal Rails fixture and
TypeScript client tests. Existing application routes require only explicit
contract declarations, not replacement handlers.

Runtime uses Ruby and existing Rails components. Zod, oRPC, TypeScript and
Testcontainers are consumer-side or development tooling, not Ruby request-path
dependencies. No Node service, database or additional schema gem is required.

The optional RPC server is a separate dependent change:
[add-orpc-procedures](../add-orpc-procedures/proposal.md).
This proposal is not a claim of implemented or released behavior.
