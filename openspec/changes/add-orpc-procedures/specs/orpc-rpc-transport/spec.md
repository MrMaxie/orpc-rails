## ADDED Requirements

### Requirement: JSON POST calls interoperate with pinned v1 RPCLink

The RPC endpoint SHALL accept POST JSON at an explicitly mounted prefix followed
by registered procedure path segments. Input SHALL use a required `json` member
and omitted or empty-array `meta`; output SHALL use `json` and empty-array
`meta` with HTTP 200 and JSON content type. Only supported schema-valid JSON
values SHALL cross this transport. The official pinned v1 RPCLink MUST call it
without custom transport or serializers. The gem MUST NOT claim full oRPC
serializer support or v2 compatibility.

#### Scenario: Default client round trip

- **WHEN** official RPCLink calls `widgets.create({ name: "blue" })` using
  the generated contract and `/rpc` prefix
- **THEN** Rails routes to `widgets.create` and validates the input
- **AND** the client decodes its declared JSON output successfully

#### Scenario: JSON null and string identifiers retain their types

- **WHEN** procedures return a declared null value and a declared string ID
  such as `"9007199254740993"`
- **THEN** RPCLink receives null and that exact string, not undefined or a
  lossy numeric ID

#### Scenario: Version incompatibility is not hidden

- **WHEN** a fixture uses an oRPC v2 client or a nonempty native-type metadata
  payload
- **THEN** it is outside the claimed compatibility profile
- **AND** unsupported metadata is rejected rather than silently decoded as JSON

### Requirement: Requests are bounded and decoded as untrusted data

The endpoint SHALL reject malformed JSON/UTF-8, duplicate JSON keys, invalid
or extra envelope fields, nonempty metadata, file maps and unsupported media
types. It SHALL enforce configurable byte and nesting limits before handler
execution (defaults: 1 MiB and 64 levels). Numeric input/output MUST conform to
the shared finite-number and safe-integer schema semantics. Input parsing MUST
NOT evaluate code, constantize names or allocate symbols from arbitrary keys.
Only explicitly registered procedure paths SHALL execute.

#### Scenario: Native metadata is not silently ignored

- **WHEN** a request includes `meta: [[1, "created_at"]]` or a `maps` member
- **THEN** dispatch returns `BAD_REQUEST`/400 and invokes no handler

#### Scenario: Malformed envelope fails predictably

- **WHEN** a request is invalid JSON, lacks `json`, repeats `json`, contains
  `meta: {}` or includes an unknown envelope property
- **THEN** it receives `BAD_REQUEST`/400 with the v1 JSON error envelope,
  not Rails HTML or an unwrapped parse-error body, and invokes no handler

#### Scenario: Request size and depth are bounded

- **WHEN** a payload exceeds the configured byte limit or nesting limit
- **THEN** byte overflow receives `PAYLOAD_TOO_LARGE`/413 and depth overflow
  receives `BAD_REQUEST`/400
- **AND** no handler runs and the failure does not disclose the payload

#### Scenario: Wrong media type cannot invoke a procedure

- **WHEN** a POST uses multipart or another unsupported content type
- **THEN** it receives `UNSUPPORTED_MEDIA_TYPE`/415 with no handler invocation

#### Scenario: Unknown and unsafe paths cannot dispatch Ruby methods

- **WHEN** a request targets an unknown key, unsafe segment or ambiguous encoded
  path
- **THEN** it receives `NOT_FOUND`/404 and invokes no Ruby method outside the
  explicit registry

#### Scenario: Unsupported HTTP method has no side effects

- **WHEN** GET, PUT, PATCH or DELETE is used under the mounted RPC prefix
- **THEN** the response is `METHOD_NOT_SUPPORTED`/405 with `Allow: POST`
- **AND** the procedure handler is not invoked

### Requirement: Errors match the v1 protocol and never look successful

Gem-generated and declared procedure errors SHALL use HTTP 400..599 and a v1
error object under `json`, containing `defined`, `code`, `status` and a safe
`message`, plus empty `meta`. Defined business-error data SHALL conform to its
error schema; undefined protocol errors SHALL contain `data: {}`.
HTTP status and envelope status MUST agree.
Unexpected exceptions and invalid outputs SHALL become undefined 500 errors
without exception text, stacks or application context. Application callback
responses SHALL remain application-controlled, not globally rewritten.
The listed undefined error codes SHALL be this gem's protocol-failure policy;
compatibility MUST be verified against the pinned client's decoder.

#### Scenario: Protocol failure is an undefined client error

- **WHEN** schema-invalid input is sent through the official client
- **THEN** it rejects with undefined `BAD_REQUEST`, status 400
- **AND** it does not return an HTTP-200 error object as successful output

#### Scenario: Unexpected exception is safely encoded

- **WHEN** a handler raises an exception containing a simulated secret
- **THEN** the HTTP and envelope status are both 500 and code is
  `INTERNAL_SERVER_ERROR` with `defined: false` and `data: {}`
- **AND** the test asserts those raw envelope fields and the official client's
  decoded error, with no secret, stack or context in either

### Requirement: The protocol is tested through the real Rails stack

Acceptance SHALL reuse the built-gem Testcontainers harness, pinned versions
and official clients from the prerequisite change. It SHALL test RPCLink
success, defined/undefined errors and generated types, plus raw HTTP rejection
cases through the full Rails middleware/controller stack. Procedure additions
MUST NOT regress conventional OpenAPILink contracts.

#### Scenario: Both modes coexist

- **WHEN** the fixture registers a conventional HTTP contract and an optional
  RPC procedure
- **THEN** OpenAPILink calls the unchanged HTTP route and RPCLink calls the
  mounted procedure using their respective generated contracts
- **AND** the prerequisite export-only acceptance suite still passes

#### Scenario: Client and byte-level rejection coverage are complementary

- **WHEN** the Testcontainers integration task runs
- **THEN** official client tests verify successful/failed typed calls
- **AND** raw HTTP tests verify malformed, duplicate-key, deep, oversized,
  metadata, path, method and content-type rejection without business effects
