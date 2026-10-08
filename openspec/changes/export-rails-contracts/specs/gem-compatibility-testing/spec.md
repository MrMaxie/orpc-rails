## ADDED Requirements

### Requirement: The gem has a verifiable distribution boundary

The project SHALL provide an installable `orpc-rails` gem with the `OrpcRails`
namespace and `orpc_rails` require entry point. The gemspec SHALL reference one
Ruby version constant, declare Ruby/Rails bounds and package only distribution
files through an explicit allowlist. It MUST NOT package tests, fixtures,
OpenSpec documents, Node dependencies or workstation-specific files.

#### Scenario: Built artifact loads independently

- **WHEN** the gem is built and installed in a clean gem environment with its
  declared runtime dependencies and no development gems or Node installation
- **THEN** `require "orpc_rails"` succeeds and exposes the documented namespace

#### Scenario: Distribution excludes development state

- **WHEN** the built `.gem` manifest is inspected
- **THEN** it includes the library, license and consumer documentation
- **AND** it excludes tests, container fixtures, generated test contracts,
  Node workspaces and workstation state
- **AND** a second build from the same tree has the same file manifest

### Requirement: Runtime dependencies stay inside the integration boundary

Runtime dependencies SHALL be limited to Rails components actually used and
Ruby standard libraries. The gem MUST NOT require full Rails, ActiveRecord,
Testcontainers, a schema-validation gem, Node or JS packages for Ruby runtime
operation. Development tooling SHALL be declared separately.

#### Scenario: Dependency metadata does not install test infrastructure

- **WHEN** the built gemspec's runtime dependencies are inspected
- **THEN** Testcontainers and other test tools are absent
- **AND** each declared runtime Rails component is required by the library

### Requirement: Compatibility claims are backed by pinned fixture runs

The implementation SHALL declare and test a supported Ruby/Rails matrix and
lock exact fixture dependencies. The initial acceptance targets SHALL be
Ruby 3.3/Rails 7.2 and Ruby 3.4/Rails 8.1, with stable oRPC v1 and Zod v4.
These targets MUST pass before being claimed as supported; incompatible bounds
MUST be narrowed before release. An oRPC major version change MUST require a
separate compatibility decision and fixture, not an implicit use of `latest`.

#### Scenario: Stable client and Rails matrix are exercised

- **WHEN** compatibility validation runs for each declared matrix target
- **THEN** the packaged gem installs and generated contracts typecheck
- **AND** actual client GET and POST calls against that target pass

#### Scenario: Upstream major drift is visible

- **WHEN** a fixture dependency attempts to replace oRPC v1 with v2
- **THEN** lock/version checks fail until the compatibility target is explicitly
  updated and its API/wire tests pass

### Requirement: Integration tests use Testcontainers and real HTTP

A dedicated integration task SHALL use Ruby Testcontainers to run a minimal
Rails HTTP fixture and Node TypeScript client fixture on an isolated network.
The Rails fixture SHALL install the built gem. Tests SHALL use official clients
and generated contracts rather than stubs. The harness SHALL use dynamically
allocated host ports, pinned images/locked packages, bounded HTTP readiness
checks and cleanup on success or failure. No database SHALL be required for
the in-memory acceptance fixtures.

#### Scenario: Client reaches the packaged Rails application

- **WHEN** the integration task starts both fixtures and readiness succeeds
- **THEN** the Node fixture reaches Rails through its network alias
- **AND** its typecheck, schema checks and actual HTTP calls pass

#### Scenario: Container failure does not become a false pass

- **WHEN** Rails fails readiness or the Node client exits nonzero
- **THEN** the integration task fails and supplies sanitized diagnostics
- **AND** it cleans up its containers and network

#### Scenario: Docker absence is actionable

- **WHEN** the integration task runs without a reachable Docker daemon
- **THEN** it exits nonzero with instructions to start/configure Docker
- **AND** it does not silently skip the client acceptance tests

#### Scenario: Unit tests do not require Docker

- **WHEN** the separate unit test task runs without Docker
- **THEN** pure schema, registry, exporter and packaging checks can run
- **AND** that result is not reported as integration compatibility evidence

### Requirement: Acceptance tests can detect broken contracts

The test suite SHALL cover deterministic generation, contract drift, positive
and negative Zod parsing, positive and negative TypeScript inference, actual
GET path/query and POST body mapping, application authentication and unchanged
conventional Rails errors. At least one deliberately invalid contract/payload
SHALL fail its check so the suite cannot pass merely by importing a module.

#### Scenario: A protected route retains Rails authentication

- **WHEN** the official HTTP client calls a protected endpoint without
  credentials and then with the fixture's accepted test credentials
- **THEN** the first request is denied by the existing Rails callback
- **AND** the second returns the expected output

#### Scenario: Broken generation is caught

- **WHEN** a required output field is removed from an actual fixture response
- **THEN** exported-schema parsing fails the integration test even if the HTTP
  request returned 200
