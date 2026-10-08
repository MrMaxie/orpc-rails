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

#### Scenario: Default empty metadata omission is supported

- **WHEN** the pinned default client sends exactly `{"json":{"name":"blue"}}`
  with POST `application/json` and no `meta` member
- **THEN** gem dispatch accepts that supported envelope
- **AND** its success response has HTTP 200 and explicit `meta: []`

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

Once application callbacks allow gem dispatch, the codec SHALL reject malformed
JSON/UTF-8, duplicate decoded keys, comments, invalid escapes, trailing commas,
invalid/extra envelope fields, nonempty metadata, file maps and unsupported
media types. It SHALL enforce controller-level `orpc_limits` before handler
or context execution: defaults 1 MiB and 64 levels, with integer minima 1024
bytes and 3 levels. Bytes SHALL count the complete UTF-8 envelope, not only
`json`; depth SHALL count the outer object as level 1 and each array/object
inside it. Success and declared-error envelopes SHALL obey the same limits.
The byte check SHALL handle absent/misleading Content-Length, and a bounded
read or already-cached body SHALL precede the gem's scan/parse. These limits
SHALL NOT be claimed as bounds on earlier Rails/application parameter parsing.

IR-valid numeric values SHALL additionally be finite and SHALL NOT be
mathematically integral outside ±(2^53 - 1), regardless of Ruby numeric class
or literal/exponent spelling. Raw bytes and decoded keys/strings SHALL be
valid UTF-8, including valid surrogate pairs. Duplicate detection SHALL precede
lossy ordinary parsing and MUST NOT rely on portable `object_class#[]=` or an
option ignored by older JSON versions. JSON 2.x additions SHALL be disabled;
removed JSON 3 options SHALL NOT be passed blindly. Parsing MUST NOT evaluate
code, constantize names or allocate symbols from arbitrary keys.
Only registered keys of the selected dispatch controller SHALL execute.

Application responses/errors before this dispatch phase remain governed by
the Rails lifecycle requirement. Following protocol-failure scenarios assume
that dispatch is reached; they SHALL NOT override an earlier security denial.

#### Scenario: Native metadata is not silently ignored

- **WHEN** a request includes `meta: [[1, "created_at"]]` or a `maps` member
- **THEN** dispatch returns `BAD_REQUEST`/400 and invokes no handler

#### Scenario: Malformed envelope fails predictably

- **WHEN** an allowed request reaching the codec is invalid JSON, lacks `json`,
  repeats `json`, contains
  `meta: {}` or includes an unknown envelope property
- **THEN** it receives `BAD_REQUEST`/400 with the v1 JSON error envelope,
  not Rails HTML or an unwrapped parse-error body, and invokes no handler

#### Scenario: Escaped-equivalent duplicates and invalid Unicode are rejected

- **WHEN** an allowed request contains `"a"` and `"\u0061"` in the same object,
  invalid UTF-8 bytes, a lone high/low surrogate or a JSON comment
- **THEN** the codec returns `BAD_REQUEST`/400 before handler/context execution
- **AND** a valid surrogate pair is admitted if its declared schema permits it

#### Scenario: Request size and depth are bounded

- **WHEN** a payload exceeds the configured byte limit or nesting limit
- **THEN** byte overflow receives `PAYLOAD_TOO_LARGE`/413 and depth overflow
  receives `BAD_REQUEST`/400
- **AND** no handler runs and the failure does not disclose the payload

#### Scenario: Envelope depth includes the wire wrapper

- **WHEN** an otherwise valid `json` value consists of 63 nested arrays at the
  default nesting limit and another consists of 64
- **THEN** the first passes the depth check and the second receives 400
- **AND** output encoding uses the same depth convention

#### Scenario: Profile-rejected numeric spellings cannot bypass the safe range

- **WHEN** an allowed request uses `9007199254740992`, `9007199254740992.0`,
  an equivalent exponent value, or `1e400` where a number schema is declared
- **THEN** the codec rejects it with 400 before handler/context execution
- **AND** such handler output becomes a safe 500 instead of rounded success

#### Scenario: Wrong media type cannot invoke a procedure

- **WHEN** a POST uses multipart or another unsupported content type
- **THEN** it receives `UNSUPPORTED_MEDIA_TYPE`/415 with no handler invocation

#### Scenario: Unknown and unsafe paths cannot dispatch Ruby methods

- **WHEN** an allowed request targets an unknown key, a key registered only to
  another controller, empty/dot segments, or percent-encoded path segments
- **THEN** it receives `NOT_FOUND`/404 and invokes no Ruby method outside the
  explicit registry

#### Scenario: Unsupported HTTP method has no side effects

- **WHEN** callbacks allow dispatch of GET, PUT, PATCH or DELETE under the
  mounted RPC prefix
- **THEN** the response is `METHOD_NOT_SUPPORTED`/405 with `Allow: POST`
- **AND** the procedure handler is not invoked

### Requirement: Errors match the v1 protocol and never look successful

Gem-generated and declared procedure errors SHALL use HTTP 400..599 and a v1
error object under `json`, containing `defined`, `code`, `status` and a safe
`message`, plus empty `meta`. Defined business-error data SHALL conform to its
error schema; undefined protocol errors SHALL contain `data: {}`.
HTTP status and envelope status MUST agree. The server SHALL enforce that
agreement and declared-error validity itself; pinned RPCLink trusts literal
`defined`/`status` rather than checking the server's declarations. Explicit
`data: {}` for generic errors SHALL be gem policy even though the v1 decoder
can accept absent data.
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

#### Scenario: Invalid output cannot defeat the error encoder's own bounds

- **WHEN** validated handler/error data exceeds the configured byte/depth limits
  or contains unsupported Ruby values
- **THEN** dispatch emits the fixed safe undefined 500 envelope with empty data
- **AND** the minimum allowed limits admit that bounded envelope without
  recursive validation failure or disclosure of the rejected value

### Requirement: The protocol is tested through the real Rails stack

Acceptance SHALL reuse the built-gem Testcontainers harness, pinned versions
and official clients from the prerequisite change. It SHALL test RPCLink
success, defined/undefined errors and generated types, plus raw HTTP rejection
cases through the full Rails middleware/controller stack. Procedure additions
MUST NOT regress conventional OpenAPILink contracts. Prerequisite tests using
handwritten contracts/scripted loopback replies or Rails probe controllers
SHALL NOT count as installed-gem procedure acceptance.

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
