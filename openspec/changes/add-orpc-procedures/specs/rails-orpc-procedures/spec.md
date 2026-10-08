## ADDED Requirements

### Requirement: Procedure handling is explicitly optional

The gem SHALL provide opt-in procedures declaring a registered router key,
input/output schemas, error schemas and Ruby handler. It SHALL require explicit
Rails route mounting. Loading the gem or registering conventional controller
contracts MUST NOT mount an RPC route or invoke procedure behavior.

#### Scenario: Export-only application needs no procedure server

- **WHEN** an application loads the gem and exports conventional contracts
  without enabling procedure dispatch
- **THEN** its existing Rails endpoints still work and no RPC route exists

#### Scenario: Mounted procedure is callable by key

- **WHEN** the application explicitly registers `widgets.create` and mounts
  dispatch under `/rpc`
- **THEN** a valid POST to `/rpc/widgets/create` invokes that handler once
- **AND** unrelated Rails routes keep their previous behavior

### Requirement: Rails callbacks and request context are preserved

Dispatch SHALL run through the controller lifecycle and preserve application
callbacks, authentication, authorization and CSRF policy. The gem MUST NOT
skip protection or configure CORS automatically. Context SHALL be constructed
for each allowed request, passed only to its handler and excluded from exports,
responses and global registry state.

#### Scenario: Authentication denial prevents execution

- **WHEN** an application's authentication callback denies the request
- **THEN** the procedure handler is not invoked and the Rails denial is retained

#### Scenario: Context belongs to one request

- **WHEN** two requests use different authenticated test users
- **THEN** each handler sees only the context for its request
- **AND** neither user's context appears in the other response or export

#### Scenario: Cookie-authenticated controller retains CSRF protection

- **WHEN** a CSRF-protected controller receives a procedure POST without a
  valid token
- **THEN** Rails denies it according to application policy before handler
  invocation
- **AND** a request with a valid token and credentials can invoke the handler

### Requirement: Ruby and Zod validate the same schema semantics

Before execution, input SHALL satisfy the shared schema IR without coercion,
unknown-key stripping or implicit defaults. Handler output SHALL satisfy its
schema before a success response is sent. JSON hashes SHALL have string keys.
Ruby and generated Zod SHALL agree on the supported nodes, numeric bounds,
omission/null semantics and invalid values. Unsupported outputs MUST fail
safely rather than stringify arbitrary Ruby objects.

#### Scenario: Invalid input cannot reach business logic

- **WHEN** required string `name` is missing, null or a number, or an undeclared
  property is supplied
- **THEN** the response is an undefined `BAD_REQUEST`/400 error
- **AND** the handler invocation count remains zero

#### Scenario: Optional and nullable remain distinct in both languages

- **WHEN** the same conformance fixture is evaluated in Ruby and generated Zod
  with omitted optional properties and required nullable properties
- **THEN** both accept the valid fixture and reject missing required or
  non-nullable null values identically

#### Scenario: Invalid output does not become success

- **WHEN** a handler returns an object missing a required output field,
  a symbol-keyed hash or an unsupported Ruby object
- **THEN** dispatch returns safe `INTERNAL_SERVER_ERROR`/500, not success

### Requirement: Declared errors have validated typed data

Procedures SHALL declare business-error codes with HTTP status and data schema.
Only a declared raised error with conforming data SHALL be emitted as a defined
v1 oRPC error. Unknown codes, invalid error data and unexpected exceptions
SHALL become safe undefined internal errors. Internal response content MUST
exclude exception messages, stacks, credentials and request context.

#### Scenario: Defined conflict survives the official client

- **WHEN** a handler raises declared `CONFLICT` with status 409 and valid
  `{ "name": "blue" }` error data
- **THEN** the official RPC client rejects with code, status, public message
  and validated data preserved
- **AND** its `isDefinedError` predicate recognizes the error as defined

#### Scenario: Invalid business error becomes a safe failure

- **WHEN** a handler raises an undeclared error code or declared error with
  invalid data
- **THEN** the client receives undefined `INTERNAL_SERVER_ERROR`/500
- **AND** the response contains no raw exception or invalid business data
