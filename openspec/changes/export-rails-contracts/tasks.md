## 1. Lock the compatibility target and package boundary

- [x] 1.1 Verify oRPC 1.15.5, Zod 4.6.5 and compatible TypeScript fixture pins;
  compile a minimal v1 contract/OpenAPILink example before implementing export.
- [x] 1.2 Verify the proposed Ruby 3.3/Rails 7.2 and Ruby 3.4/Rails 8.1 targets;
  record tested bounds and lock dependencies for each fixture.
- [x] 1.3 Add the gemspec, `OrpcRails` namespace, require entry point and single
  version constant; justify each Rails component dependency.
- [x] 1.4 Add Minitest/Rake development tasks and package-manifest tests;
  build/install/require the gem without development gems or Node.

## 2. Define schemas and explicit endpoint registration

- [x] 2.1 Implement the bounded immutable schema representation; test optional
  versus null, strict objects, numeric bounds and unsupported nodes.
- [x] 2.2 Implement controller opt-in declarations and reload-safe registry;
  prove undeclared actions are excluded and callbacks/rendering are unchanged.
- [x] 2.3 Resolve explicit methods/paths to controller actions; reject invalid
  routes, missing parameters, unsupported query/body locations and key clashes.

## 3. Generate real TypeScript contracts

- [x] 3.1 Emit reusable Zod schemas, detailed-input v1 oRPC contracts and nested
  router/type exports using safely quoted literals and stable ordering.
- [x] 3.2 Implement explicit-destination export and non-writing drift checks;
  test atomic failure, byte stability and escaped literal injection cases.
- [x] 3.3 Typecheck positive and negative client inputs and validate representative
  valid/invalid wire payloads with the generated Zod schemas.

## 4. Prove compatibility through Testcontainers

- [x] 4.1 Add a minimal in-memory Rails fixture installing the built `.gem` and
  a locked Node fixture using official OpenAPILink; no database or custom link.
- [x] 4.2 Implement isolated network/ephemeral ports, bounded HTTP readiness,
  sanitized failure diagnostics and cleanup on success/induced failure.
- [x] 4.3 Exercise real GET path/query, POST wrapped JSON/201, authenticated
  routes and unchanged conventional Rails 422 responses.
- [x] 4.4 Prove invalid output parsing and invalid TypeScript inputs fail;
  exercise deterministic regeneration and non-writing contract drift.
- [x] 4.5 Run unit/package checks and the Testcontainers integration suite for
  the supported matrix; fail integration explicitly when Docker is unavailable.

## 5. Prepare the public API for adoption

- [x] 5.1 Document one conventional-controller declaration, export/check commands,
  official client imports, supported schema/route limits and tested versions.
- [x] 5.2 Confirm generated modules and gem contents contain only public contract
  and distribution data; no business logic, credentials or fixture artifacts.
- [x] 5.3 Review compatibility and consumer-visible outcomes before an eventual
  SemVer release; do not publish, tag or archive this change during planning.

## Verification evidence

- `bundle exec rake test`: 69 tests, including schema, controller/registry,
  route shadowing, export atomicity/drift and the twice-built gem manifest.
- `ruby bin/test-integration`: both locked pairs pass — Ruby 3.3.12/Rails 7.2.4
  and Ruby 3.4.11/Rails 8.1.4. Each runs 69 tests against the installed gem,
  2 real Railtie task tests, the pinned v1 API gate, TypeScript inference checks
  and 7 official-client HTTP/Zod tests.
- Red controls observed before green: missing package/library/declaration/export
  surfaces; missing generated schema endpoint in TypeScript; route shadowing;
  unsafe numeric bounds. Real malformed output is rejected by generated Zod.
- Readiness timeout and a nonzero Node typecheck failed the integration job;
  owned containers/networks were removed. An unreachable Docker daemon exits
  nonzero with recovery guidance. No unit result substitutes for integration.
- Independent export and packaging reviews were rechecked after fixes and
  consumer documentation. OpenSpec validation is a structural check, not the
  Ruby/client compatibility oracle.
- The optional procedure change remains separate and unimplemented. This
  change has not been archived, published or tagged.
