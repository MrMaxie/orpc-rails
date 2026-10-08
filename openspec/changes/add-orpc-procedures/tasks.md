## 1. Prove prerequisites and wire assumptions

- [ ] 1.1 Require passing export-rails-contracts acceptance and reuse its schema,
  registry, generator, gem package and locked Testcontainers fixtures.
- [ ] 1.2 Capture pinned v1 RPCLink JSON requests/success/error responses to prove
  POST method selection, null output, omitted metadata and literal wire
  `defined`/`status` fields before coding; assert exact raw generic-error
  envelopes with `data: {}` as well as official client decoding.
- [ ] 1.3 Prove bounded standard-library JSON parsing, duplicate-key detection
  and full-stack malformed-input handling without extra runtime dependencies;
  verify raw-body access and handling of Rails parameter parse errors yield
  the v1 error envelope without changing application callback responses.

## 2. Add optional procedure declarations and validation

- [ ] 2.1 Add input/output/error/handler declarations and generated procedure
  contracts; validate codes/status/data and reject invalid registrations.
- [ ] 2.2 Implement Ruby validation over the shared IR; compare Ruby and Zod
  acceptance/rejection fixtures for every node and constraint.
- [ ] 2.3 Add application-controlled per-request context and safe error helpers;
  test context isolation, unknown codes and invalid error data.

## 3. Implement the bounded Rails RPC adapter

- [ ] 3.1 Add explicit controller dispatch/mounting and registry-only path lookup;
  preserve callbacks, authorization and CSRF, with no automatic routes.
- [ ] 3.2 Add POST JSON-envelope decoding, byte/depth limits and safe rejection
  of unsupported metadata, maps, numbers, paths and media types.
- [ ] 3.3 Add output validation and exact v1 success/error encoding; verify
  status agreement, declared data and safe internal errors.
- [ ] 3.4 Reject unsupported methods with 405/Allow without executing handlers;
  verify error behavior through the complete Rails middleware stack.

## 4. Extend actual-client Testcontainers acceptance

- [ ] 4.1 Typecheck generated procedure contracts and exercise official RPCLink
  nested success, empty-object input, null output and string large IDs.
- [ ] 4.2 Verify schema-invalid input, declared CONFLICT data/isDefinedError,
  undeclared errors, unexpected exceptions and invalid outputs.
- [ ] 4.3 Exercise raw malformed/duplicate/deep/oversized envelopes, nonempty
  meta/maps, unsupported content types/methods and unsafe/unknown paths.
- [ ] 4.4 Prove zero handler side effects after failures, separate request
  contexts, authentication denial and valid/invalid CSRF-token behavior.
- [ ] 4.5 Run both OpenAPILink and RPCLink acceptance for the supported matrix;
  test procedures unmounted and confirm export-only regressions are absent.

## 5. Document the opt-in surface

- [ ] 5.1 Document procedure declaration, explicit mounting, context/error helpers,
  official RPCLink client and POST/JSON/v1 limits beside export-only usage.
- [ ] 5.2 Verify no new Ruby runtime dependencies, packaged fixture leaks or
  changes to application security policy; review eventual SemVer impact.
- [ ] 5.3 Archive only after implementation and acceptance; no release, tag or
  publication is authorized by completing this planning change.
