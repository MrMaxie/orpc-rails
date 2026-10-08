## 1. Lock the compatibility target and package boundary

- [ ] 1.1 Verify oRPC 1.15.5, Zod 4.6.5 and compatible TypeScript fixture pins;
  compile a minimal v1 contract/OpenAPILink example before implementing export.
- [ ] 1.2 Verify the proposed Ruby 3.3/Rails 7.2 and Ruby 3.4/Rails 8.1 targets;
  record tested bounds and lock dependencies for each fixture.
- [ ] 1.3 Add the gemspec, `OrpcRails` namespace, require entry point and single
  version constant; justify each Rails component dependency.
- [ ] 1.4 Add Minitest/Rake development tasks and package-manifest tests;
  build/install/require the gem without development gems or Node.

## 2. Define schemas and explicit endpoint registration

- [ ] 2.1 Implement the bounded immutable schema representation; test optional
  versus null, strict objects, numeric bounds and unsupported nodes.
- [ ] 2.2 Implement controller opt-in declarations and reload-safe registry;
  prove undeclared actions are excluded and callbacks/rendering are unchanged.
- [ ] 2.3 Resolve explicit methods/paths to controller actions; reject invalid
  routes, missing parameters, unsupported query/body locations and key clashes.

## 3. Generate real TypeScript contracts

- [ ] 3.1 Emit reusable Zod schemas, detailed-input v1 oRPC contracts and nested
  router/type exports using safely quoted literals and stable ordering.
- [ ] 3.2 Implement explicit-destination export and non-writing drift checks;
  test atomic failure, byte stability and escaped literal injection cases.
- [ ] 3.3 Typecheck positive and negative client inputs and validate representative
  valid/invalid wire payloads with the generated Zod schemas.

## 4. Prove compatibility through Testcontainers

- [ ] 4.1 Add a minimal in-memory Rails fixture installing the built `.gem` and
  a locked Node fixture using official OpenAPILink; no database or custom link.
- [ ] 4.2 Implement isolated network/ephemeral ports, bounded HTTP readiness,
  sanitized failure diagnostics and cleanup on success/induced failure.
- [ ] 4.3 Exercise real GET path/query, POST wrapped JSON/201, authenticated
  routes and unchanged conventional Rails 422 responses.
- [ ] 4.4 Prove invalid output parsing and invalid TypeScript inputs fail;
  exercise deterministic regeneration and non-writing contract drift.
- [ ] 4.5 Run unit/package checks and the Testcontainers integration suite for
  the supported matrix; fail integration explicitly when Docker is unavailable.

## 5. Prepare the public API for adoption

- [ ] 5.1 Document one conventional-controller declaration, export/check commands,
  official client imports, supported schema/route limits and tested versions.
- [ ] 5.2 Confirm generated modules and gem contents contain only public contract
  and distribution data; no business logic, credentials or fixture artifacts.
- [ ] 5.3 Review compatibility and consumer-visible outcomes before an eventual
  SemVer release; do not publish, tag or archive this change during planning.
