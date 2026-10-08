## ADDED Requirements

### Requirement: Procedure handling is explicitly optional

The gem SHALL provide opt-in procedures declaring a registered router key,
input/output schemas, error schemas and Ruby handler. It SHALL require explicit
Rails route mounting to a dedicated dispatch controller, with parameter
wrapping disabled explicitly for that controller only. Loading the gem or registering conventional controller
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

### Requirement: RPC exports are explicit and isolated from HTTP contracts

The gem SHALL provide `orpc:export_rpc[path,controller]` and
`orpc:check_rpc[path,controller]` for one explicitly selected registered
controller. They SHALL export its executable Zod schemas, v1 procedure
`contract` and `Contract` type without HTTP route metadata or evaluating
handlers/context. Existing HTTP export/check tasks SHALL retain their behavior.
Each surface SHALL apply deterministic quoting, reserved-key/collision checks,
atomic writes and non-writing drift checks independently.

#### Scenario: Equal keys in different transports do not collide

- **WHEN** a conventional HTTP controller and the selected RPC controller both
  declare `widgets.create` and their respective export tasks run
- **THEN** separate modules contain their own input/output contracts
- **AND** the HTTP module keeps detailed HTTP mapping while the RPC module uses
  ordinary `oc.input(...).output(...).errors(...)`

#### Scenario: Export selects one controller without running application code

- **WHEN** RPC export selects `RpcController` while another dispatch controller
  also has declarations
- **THEN** only the selected controller's declarations appear
- **AND** no handler or context builder runs; duplicates within the selected
  module fail without replacing the destination

#### Scenario: RPC drift check is non-writing

- **WHEN** a procedure/error declaration differs from the selected generated RPC
  module or that destination is missing
- **THEN** RPC check exits nonzero and leaves the destination bytes/mtime intact
- **AND** it does not modify the HTTP contract

### Requirement: Rails callbacks and request context are preserved

Dispatch SHALL run through the controller lifecycle and preserve application
callbacks, authentication, authorization and CSRF policy. The gem MUST NOT
skip protection or configure CORS automatically. Context SHALL be constructed
for each allowed request, passed only to its handler and excluded from exports,
responses and global registry state. Application middleware/callback/CSRF
responses and exceptions before gem dispatch SHALL NOT be converted into gem
protocol errors. The v1 envelope guarantee SHALL cover gem dispatch/codec
failures after that phase, not earlier application processing.

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

#### Scenario: Malformed body is denied before dispatch

- **WHEN** authentication denies a malformed request before dispatch, or a
  callback/CSRF check fails while reading its Rails parameters
- **THEN** Rails retains the application's denial or parse-error behavior
- **AND** no procedure handler or context builder runs and no global ParseError
  rescue replaces that response with a gem error

### Requirement: Ruby and Zod validate the same schema semantics

Before execution, input SHALL satisfy the shared schema IR without coercion,
unknown-key stripping or implicit defaults. Handler output SHALL satisfy its
schema before a success response is sent. JSON hashes SHALL have string keys.
Ruby and generated Zod SHALL agree on the supported nodes, numeric bounds,
omission/null semantics and invalid values. String length bounds SHALL count
Unicode code points without normalization, matching pinned Zod 4.6.5; array
length bounds SHALL count elements. Wire-profile admission (bytes, depth,
UTF-8 and safe numeric representation) SHALL be checked separately from IR
validation. Unsupported outputs MUST fail safely rather than stringify
arbitrary Ruby objects.

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

#### Scenario: Unicode string bounds agree with the pinned Zod

- **WHEN** Ruby and Zod evaluate max-length-1 strings containing U+1F600,
  precomposed U+00E9, and `e` followed by U+0301
- **THEN** both accept the first two and reject the combining sequence
- **AND** neither uses UTF-16 unit counts, byte counts or implicit normalization

#### Scenario: Wire limits do not silently change the schema IR

- **WHEN** a finite value passes `S.number` / `z.number()` but is an integral
  number outside the RPC safe-integer profile
- **THEN** the RPC codec rejects it before handler invocation
- **AND** shared IR conformance and conventional HTTP exports keep their finite
  number semantics rather than acquiring hidden RPC-only constraints

#### Scenario: Invalid output does not become success

- **WHEN** a handler returns an object missing a required output field,
  a symbol-keyed hash or an unsupported Ruby object
- **THEN** dispatch returns safe `INTERNAL_SERVER_ERROR`/500, not success

### Requirement: Declared errors have validated typed data

Procedures SHALL declare nonblank stable business-error codes with integer HTTP
status 400..599 and a supported, non-optional-root data schema. A raised error
helper SHALL supply code, public message and data; status SHALL come from its
declaration rather than an arbitrary per-raise override.
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
