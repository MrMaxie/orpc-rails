## 1. Prove prerequisites and wire assumptions

- [x] 1.1 Require passing export-rails-contracts acceptance and reuse its schema,
  registry, generator, gem package and locked Testcontainers fixtures.
- [x] 1.2 Capture pinned v1 RPCLink JSON requests/success/error responses to prove
  POST method selection, null output, omitted metadata and literal wire
  `defined`/`status` fields before coding; assert exact raw generic-error
  envelopes with `data: {}` as well as official client decoding.
- [ ] 1.3 Prove bounded standard-library strict JSON decoding and duplicate-key
  detection, then gem-owned malformed-input envelopes through the full stack.
  Earlier Rails callback/CSRF denials or parse errors remain application-owned.
  - [x] 1.3.1 Probe locked json 2.7.2/3.0.2 option and duplicate behavior,
    additions, invalid encoding/surrogates, envelope depth and number parsing.
  - [x] 1.3.2 Prove repeatable raw-body access, parameter-reading callback
    behavior, denial precedence and valid/missing CSRF-token handling with
    isolated Rails probe controllers; these are not a gem RPC adapter.
  - [ ] 1.3.3 Implement/test a bounded StringScanner prepass for strict tokens,
    escaped-equivalent duplicate keys, UTF-8/surrogates and depth; ensure the
    supported JSON versions cannot ignore a needed option silently.
  - [ ] 1.3.4 Test complete-wire byte/depth limits, minimum valid configuration,
    absent/misleading Content-Length, safe numeric profile and output/error
    bounds before accepting the codec. Do not add a JSON/schema runtime gem.

## 2. Add optional procedure declarations and validation

- [ ] 2.1 Add input/output/error/handler declarations and selected-controller
  RPC export/check tasks; validate codes/status/data, root schemas and keys.
  Reject invalid registrations and collisions without changing HTTP exports;
  export must not execute a handler/context or emit HTTP `.route` metadata.
- [ ] 2.2 Implement Ruby validation over the shared IR; compare Ruby and Zod
  acceptance/rejection fixtures for every node and constraint. Include pinned
  Zod Unicode code-point lengths, combining sequences, numeric literal/bound
  edges and omission/null; keep additional wire-profile admission separate.
- [ ] 2.3 Add application-controlled per-request context and safe error helpers;
  test context isolation, unknown codes and invalid error data.

## 3. Implement the bounded Rails RPC adapter

- [ ] 3.1 Add dedicated controller dispatch and explicit all-method catch routes
  with format disabled; only POST runs handlers. Scope lookup to that controller,
  reject encoded/unsafe paths, and preserve callback/CSRF precedence and routes.
- [ ] 3.2 Add POST JSON-envelope decoding with `orpc_limits` and the proven
  scanner/profile checks. Reject unsupported metadata/maps/media; failures
  before input acceptance must run neither handler nor context builder.
- [ ] 3.3 Add output/schema/profile validation and exact v1 success/error
  encoding; enforce status agreement and declared data on the server, not by
  trusting RPCLink. Derive helper status from its declaration and prove fixed
  internal errors fit minimum limits without recursively failing validation.
- [ ] 3.4 Reject unsupported methods with 405/Allow without executing handlers;
  verify error behavior through the complete Rails middleware stack.

## 4. Extend actual-client Testcontainers acceptance

- [ ] 4.1 Typecheck generated procedure contracts and exercise official RPCLink
  nested success, empty-object input, null output and string large IDs.
- [ ] 4.2 Verify schema-invalid input, declared CONFLICT data/isDefinedError,
  undeclared errors, unexpected exceptions and invalid outputs.
- [ ] 4.3 Exercise raw malformed/duplicate/escaped-key/deep/oversized envelopes,
  invalid Unicode, JSON comments/escapes, numeric spellings, nonempty meta/maps,
  unsupported media/methods and unsafe/unknown/cross-controller paths.
- [ ] 4.4 Prove zero handler/context calls after input failures, separate request
  contexts, authentication denial, valid/invalid CSRF-token behavior and earlier
  parameter-parse failures retained under application policy.
- [ ] 4.5 Run both OpenAPILink and RPCLink acceptance for the supported matrix;
  test procedures unmounted and confirm export-only regressions are absent.

## 5. Document the opt-in surface

- [ ] 5.1 Document procedure declaration, explicit mounting, context/error helpers,
  official RPCLink client and POST/JSON/v1 limits beside export-only usage.
- [ ] 5.2 Verify no new Ruby runtime dependencies, packaged fixture leaks or
  changes to application security policy; review eventual SemVer impact.
- [ ] 5.3 Archive only after implementation and acceptance; no release, tag or
  publication is authorized by completing this planning change.

## First TDD delivery sequence

1. Complete 1.3.3–1.3.4 with red tests for raw ambiguity/resource boundaries
   before admitting untrusted input to a gem handler.
2. Take one JSON echo procedure through 2.1/2.2/3.1–3.3/4.1 as a vertical
   slice: failing generated-contract/client test, minimal Ruby implementation,
   then green installed-gem calls on both Rails targets. Keep HTTP tests green.
3. Add null output and declared conflict in their own red/green increments,
   then safe internal errors, callbacks/CSRF/context and the remaining rejection
   matrix. Refactor only while both language/transport suites stay green.
4. Complete product documentation and independent review after these acceptance
   tests pass. Prerequisite loopback/probe results cannot complete sections 2–5.

## Current prerequisite evidence

- `test/fixtures/client/rpc-compatibility.test.ts` uses default pinned RPCLink
  over real loopback HTTP, scripted responses and handwritten typed contracts.
  `npm run --prefix test/fixtures/client rpc:compatibility` checks inferred types
  and exact request/error bytes, metadata/null/native-value behavior and Zod
  code-point lengths. It is not generated-contract or Rails RPC acceptance.
- `test/fixtures/rails/rpc_prerequisites_test.rb` runs via the existing
  Testcontainers harness with locked Ruby/Rails/JSON. It probes parser options
  and real Rails lifecycle/CSRF behavior, not a secure codec or gem procedure.
- `ruby bin/test-integration` passes on Ruby 3.3.12/Rails 7.2.4/json 2.7.2
  and Ruby 3.4.11/Rails 8.1.4/json 3.0.2: each runs 69 packaged unit tests,
  2 Railtie task tests, 11 parser/lifecycle probes, 10 RPC wire-oracle tests,
  1 existing client compatibility test and 7 OpenAPILink HTTP tests, including
  TypeScript checks, with no failures or skips. RPC product acceptance remains
  pending; passing oracle/probe tests do not change that boundary.
- Current product surfaces in `lib/` remain export-only; no procedure task,
  dispatch, validator or error helper is claimed implemented by these probes.
- Scanner correctness, a first installed-gem RPCLink procedure call and all
  procedure acceptance remain unchecked above.
