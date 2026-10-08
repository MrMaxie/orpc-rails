## Context

This change depends on the schema representation, registry/exporter and
packaged-gem Testcontainers fixture from `export-rails-contracts`.
The export-only baseline is implemented and its packaged-gem acceptance passes
on both locked Rails targets. The optional procedure slice now implements
bounded dispatch, validation and separate contract export; installed-gem echo,
null and declared-error calls pass both targets. Conventional contracts remain
usable alone. Implementation evidence lives in tasks.md; no release is implied.

An ergonomic Ruby procedure DSL is not sufficient for compatibility with
RPCLink: the route, serialization envelope, HTTP errors and typed error shape
must match the chosen oRPC version.

## Goals / Non-Goals

**Goals:**

- Declare a procedure's input, output, errors and Ruby implementation together.
- Call it through the official oRPC v1 RPCLink with generated contract types.
- Reuse Rails authentication/callbacks and per-request application context.
- Share schema semantics between Ruby validation and generated Zod.

**Non-Goals:**

- Rewrite existing controllers or change export-only mode.
- Replicate the complete JS oRPC middleware/plugin/router API.
- Support v2 beta, batching, GET RPC, files, streams or native-type metadata.
- Add an HTTP server, authentication provider, database or Node runtime service.

## Decisions

### 1. Reuse the schema IR and add optional handlers

A controller concern supplies procedure declarations using the same immutable
schemas as export-only declarations. API shape:

```ruby
class RpcController < ApplicationController
  include OrpcRails::Procedures
  wrap_parameters false # dedicated RPC controller; never change other controllers
  before_action :authenticate_user!

  S = OrpcRails::Schema

  orpc_procedure "widgets.create",
    input: S.object(name: S.string),
    output: S.object(id: S.string, name: S.string),
    errors: { "CONFLICT" => { status: 409,
      data: S.object(name: S.string) } } do |input:, context:|
    # Call ordinary application services with context[:user].
  end

  def orpc_context
    { user: current_user }
  end
end
```

The concrete DSL spelling can be refined before release. The declaration
fields and input/output/error semantics cannot be guessed from Ruby handlers.
Procedure declarations export standard `oc.input(...).output(...).errors(...)`
contracts, without Rails HTTP route metadata masquerading as RPC transport.
The caller supplies the mounted RPC prefix in `RPCLink` configuration.

Keep exports separate: existing `orpc:export[path]` / `orpc:check[path]` remain
HTTP-only. Add `orpc:export_rpc[path,controller]` and
`orpc:check_rpc[path,controller]`, requiring one registered, named dispatch
controller (for example `RpcController`). Each RPC module exports `contract`,
`Contract` and `schemas` for that controller only. Equal keys in an HTTP module
and an RPC module are allowed; collisions within one module are not. Reuse
ordering/quoting/atomic-write/check mechanics, not HTTP `.route(...)` metadata.
Export never evaluates a handler or context builder; neither is serialized.

Require JSON-valued inputs and outputs with a schema; callers use an explicit
empty object for no input and an explicit null schema/value for null output.
The profile does not represent root `undefined`. Reuse the supported types
and strict-object, safe-integer, omission/null semantics of the first change.
Ruby validation MUST match generated Zod validation without coercion,
key dropping, default insertion or arbitrary predicates. The decoder produces
string-keyed hashes; handlers return string-keyed JSON hashes, arrays and
scalars, not ActiveRecord models or symbol-keyed hashes requiring guesswork.

For the pinned Zod 4.6.5, string length bounds count Unicode code points, not
UTF-16 units or grapheme clusters. Validate UTF-8 first and use Ruby character
length; do not normalize combining sequences. Both sides accept a single
U+1F600 at max length 1 and reject `e` plus U+0301 at that bound. Keep these as
version-sensitive conformance cases, not an assumption about every Zod v4.

Schema validation and transport admission are distinct. `S.number` describes
finite numeric values; the RPC JSON profile additionally rejects any numeric
value that is mathematically integral and outside the safe-integer range,
including Float/exponent forms. A value can pass `z.number()` yet fail that
wire policy, just as it can pass a schema but exceed the body-size limit.
Cross-language IR conformance compares schema semantics separately from the
additional profile checks. HTTP exports do not acquire RPC-only restrictions.

Alternative: directly wrap arbitrary Rails actions as RPC procedures.
Rejected because body parsing, return values, errors and schema validation
would be implicit. Conventional actions retain the HTTP export-only path.

### 2. Dispatch through an explicitly mounted Rails controller

Applications mount one dedicated controller explicitly. To reach the same
controller lifecycle for unsupported methods and empty procedure paths, use:

```ruby
# config/routes.rb — example prefix, owned by the application
match "/rpc", to: "rpc#orpc_dispatch", via: :all, format: false
match "/rpc/*orpc_path", to: "rpc#orpc_dispatch", via: :all, format: false
```

The transport still accepts POST only; `via: :all` permits its 405 response,
not extra handler methods. `format: false` prevents a suffix becoming Rails
format metadata. No automatic mount on `require` or Railtie load.
The remainder of the path identifies a registered dotted key using slash
segments (`/rpc/widgets/create` -> `widgets.create`). The route integration
also returns 405 for other methods under that prefix without invoking a
handler after application callbacks allow dispatch; it never hijacks unrelated
application routes. Callback denials take precedence over gem protocol errors.

Only valid registered keys can dispatch. Reject unknown keys, empty or unsafe
segments and encoded path ambiguities; never constantize a request value or
send it as an arbitrary method name. Lookup is scoped to this dispatch
controller, not every procedure in the application. Keys use the existing
ASCII identifier/reserved-segment rules; reject percent-encoded segments,
empty segments and dot segments rather than normalize them into another key.
Freeze declarations and replace them on Rails reload, not per request.

Use the Rails controller lifecycle instead of a Rack bypass so authentication,
authorization and request-local helpers remain application-owned. The gem
must not skip CSRF verification, configure CORS or disable host authorization.
Cookie-authenticated deployments retain their CSRF policy; API-mode deployments
can choose their existing token policy. Tests exercise both callback denial and
successful dispatch, including a CSRF-protected controller negative case.

After callbacks allow dispatch: check method/media/path, bound and decode the
body, validate input, build context for this request, invoke the handler once,
validate output/profile and serialize. Invalid input does not run the handler
or context builder. Context is not part of the exported contract or response.
No request state may be retained in process-global declarations.

Raw-body probes through both Rails stacks show that `request.raw_post` is
repeatable after valid parameter access, and malformed JSON can reach an
API controller's action when callbacks do not access `params`. A callback
that reads malformed JSON via `params` can instead fail before the action;
CSRF enforcement likewise precedes it. Such earlier middleware/callback/CSRF
responses and parse exceptions remain application-owned. The v1 envelope
guarantee starts in gem dispatch/decoding, not outside that phase; do not
install a global ParseError rescue or change Rails parameter parsers.

Rails instrumentation may inspect the body before the action, even with
parameter wrapping disabled. The gem's byte/depth checks protect its own
codec and handler admission, not total memory/CPU used by earlier Rails or
application processing. Deployment-level request limits remain separate.

### 3. Implement only the v1 JSON RPC envelope

Use the exact v1 package pins and compatibility gate from the first change.
The unversioned v2 docs are not an implementation source for this codec.

Supported request profile:

```http
POST /rpc/widgets/create
Content-Type: application/json

{"json":{"name":"blue"}}
```

`json` is required and can be any value admitted by the declared schema.
`meta` can be omitted or an empty array. Reject nonempty `meta`, `maps`,
unknown envelope keys, invalid JSON, invalid UTF-8, invalid envelope shapes,
duplicate JSON keys and native/non-JSON values; do not silently discard them.
Duplicate-key detection must happen before ordinary JSON parsing loses the
ambiguity. Use a bounded standard-library `StringScanner` lexical prepass
tracking object keys after escape decoding, structural depth and valid JSON
tokens, followed by ordinary parsing. It must reject escaped-equivalent keys,
comments, invalid escapes and trailing commas, not build a permissive JSONC
reader. `StrictJson` implements this iterative prepass; the codec unit suite
and full-stack rejection cases verify it on both locked JSON versions.

The locked matrix exposes incompatible parser conveniences: json 2.7.2 calls
`object_class#[]=` for both duplicate members but ignores
`allow_duplicate_key: false`; json 3.0.2 rejects duplicates natively but converts
objects after parsing and calls that setter only once. Neither convenience is
a uniform duplicate detector. For JSON 2.x explicitly disable
`create_additions`; JSON 3 removed additions and rejects that option. Always
use nonsymbolizing plain data parsing, no caller-supplied classes or hooks.
Validate raw bytes as UTF-8 and every decoded key/string again; older parsers
can admit malformed binary strings or lone low surrogates.

The pinned default RPCLink omits empty request metadata. It accepts omitted
or empty response metadata; the gem deliberately emits `meta: []`. Date,
BigInt, NaN and undefined array entries produce metadata and stay unsupported.
Root undefined becomes `{}` and is rejected for lacking `json`. Infinity can
already have become JSON null before reaching Rails; the server cannot infer
that origin. Client-side schema parsing is required to catch it before sending.

Successful responses use HTTP 200, JSON content type and
`{"json": <validated output>, "meta": []}`. This profile has no native types:
no metadata IDs for Date/BigInt/undefined, no multipart or streaming. Large IDs,
decimals and timestamps remain declared strings, just as in HTTP contracts.
An actual default v1 RPCLink must succeed for valid JSON calls without custom
serializers or a custom fetch adapter.

Add controller-level `orpc_limits max_body_bytes: 1_048_576, max_nesting: 64`;
these are the defaults. Require integer limits of at least 1024 bytes and
3 nesting levels so the fixed safe error envelope fits even at minimum limits.
The byte limit counts the complete UTF-8 wire envelope. Depth counts the outer
object as level 1 and each nested array/object as another level: `json` holding
63 nested arrays fits 64; 64 arrays does not. Apply the same convention to
success and declared-error envelopes before sending. A scalar does not add a
container level. Fixed protocol errors use bounded public messages and `{}`
data, never a recursively failing application-output validator.

Check size before gem decoding, including bodies with absent/misleading
Content-Length; do not trust that header as the sole oracle. Decode no more
than limit + 1 bytes from a fresh stream, or size-check the raw body already
cached by Rails before scanning it. Reject nonfinite parsed numbers, unsafe
integral numeric values and non-JSON Ruby outputs. Minimum-limit validation,
exact-limit/overflow and output limits are acceptance tests. An output outside
the profile becomes a safe internal error, never partial success.

Alternative: implement all native serializer IDs and GET query envelopes.
Deferred: these increase untrusted parsing and cross-language coercion scope
without being necessary for a first useful Rails procedure API.

### 4. Separate declared errors from safe protocol failures

For v1, a declared business error has the HTTP status registered in its
contract and an envelope containing:

```json
{
  "json": {
    "defined": true,
    "code": "CONFLICT",
    "status": 409,
    "message": "Widget already exists",
    "data": { "name": "blue" }
  },
  "meta": []
}
```

`status` is part of v1 error JSON; v2 removes it. Declared error codes must be
nonempty stable strings, their statuses must be 400..599 and their data must
have a supported schema. The application raises an `OrpcRails::Error` helper
with code, public message and data; only a matching declaration with validated
data can set `defined: true`. Invalid error data or undeclared raised codes
become internal errors rather than invented typed outcomes. The helper takes
`code`, public `message` and `data`; HTTP status comes only from its registered
integer status, not a per-raise override. For example:

```ruby
raise OrpcRails::Error.new("CONFLICT",
  message: "Widget already exists", data: { "name" => input.fetch("name") })
```

Gem-generated failures use `defined: false`, safe code/message and consistent
HTTP/envelope status: malformed envelope/input or unsupported metadata ->
`BAD_REQUEST`/400; unknown procedure -> `NOT_FOUND`/404; unsupported method ->
`METHOD_NOT_SUPPORTED`/405; unsupported content type ->
`UNSUPPORTED_MEDIA_TYPE`/415; body size overflow -> `PAYLOAD_TOO_LARGE`/413;
unexpected handler/output/error-data failure -> `INTERNAL_SERVER_ERROR`/500.
Undefined protocol errors include `data: {}`, including internal errors,
and contain no exception text or stack. These are protocol errors, not
declared business errors. Exact pinned-client tests confirm `defined` and
`status` are literal v1 members. `data` is optional in the upstream decoder;
explicit `{}` for undefined errors is this gem's policy, not an upstream
mandatory field. The client trusts envelope status and `defined`; it does not
verify status agreement or declaration/data validity for the Ruby server.
The gem must enforce those checks itself. Additional codes need no inference
from an exception class.

Do not globally wrap exceptions or responses from Rails callbacks. A normal
callback's denial remains application-controlled and the RPC client call
rejects. Merely raising the helper from a Rails callback does not enter the
handler codec. Typed authorization errors can be raised deliberately within
the allowed procedure/context phase; the gem does not infer them from denials.

Alternative: map ActiveRecord exceptions globally or return HTTP 200 with an
error field. Rejected: both change Rails behavior and obscure the client's
success/error contract.

### 5. Extend the existing Testcontainers fixture, not infrastructure

Reuse its packaged gem, Rails/Node containers, pinned versions, isolated
network, readiness and cleanup. Add a generated procedure contract and the
official `createORPCClient` from `@orpc/client` with `RPCLink` from
`@orpc/client/fetch`; use `ContractRouterClient<typeof contract>` without any
casts to bypass inference.

Exercise nested routing, success, null output, string IDs beyond JS integer
precision, strict optional/nullable input, declared business error data and
client `isDefinedError` behavior. Use raw HTTP for malformed envelopes and
unsupported methods/types, then verify error envelopes with the pinned official
client where that client can emit the request. Cover nonempty metadata,
malformed/deep/oversized JSON, invalid output, callback denial, CSRF enforcement
and two consecutive requests with distinct contexts. Export-only regression
tests continue to pass with procedure support installed but unmounted.

## Risks / Trade-offs

- Limited wire support could be mistaken for full oRPC parity → document the
  JSON/POST/v1 profile and reject unsupported inputs explicitly.
- Ruby/Zod validators can diverge → share IR, use cross-language positive and
  negative conformance fixtures for every supported node.
- Rails body parsing can run before custom decoding → keep dispatch parsing
  explicit and test error cases through the full middleware/controller stack.
- Callback responses may not be typed oRPC errors → preserve them, document
  application-owned auth behavior and test rejection with the real client.
- Resource limits and JSON duplicate-key handling are subtle → prove parser
  behavior with raw bytes before implementing handler dispatch.

## Migration Plan

Land only after export-only acceptance passes. Applications explicitly include
the procedure concern and mount a route; removing the route disables procedures
without affecting conventional endpoints or generated HTTP contracts.
No data migration or deployment service is required. Keep JS/Ruby compatibility
fixtures synchronized; do not upgrade to v2 implicitly. Archive only after
implementation/acceptance, never because planning artifacts are complete.

## Implementation Verification

Keep prerequisite oracles separate from product acceptance:
`rpc-compatibility.test.ts` uses handwritten contracts and scripted loopback
HTTP, and `rpc_prerequisites_test.rb` uses Rails probe controllers. Those
results alone never establish a working gem RPC server.

Product acceptance now uses `rpc-client.test.ts` with generated contracts
against the installed gem, `rpc_dispatch_test.rb` through the actual Rails
stack, and `unmounted_test.rb` for export-only behavior without an RPC route.
`schema_conformance.rb` generates paired Ruby/Zod cases over all shared nodes;
`rpc_codec_test.rb` covers strict scanning and input/output resource bounds.
The combined Testcontainers matrix passes both locked Ruby/Rails/JSON targets.

Regression cases cover absolute REQUEST_URI values, trailing empty segments
and arbitrary Ruby equality hooks: Boolean validation checks exact types,
not overridable equality. Complete review and acceptance before separately
archiving; implementation checks do not authorize a release, tag or publication.

## Source Evidence

- [v1 RPC protocol](https://v1.orpc.dev/docs/advanced/rpc-protocol)
- [v1 JSON serializer](https://v1.orpc.dev/docs/advanced/rpc-json-serializer)
- [v1 contract definitions](https://v1.orpc.dev/docs/contract-first/define-contract)
- [v1 client errors](https://v1.orpc.dev/docs/client/error-handling)
- [v2 wire/API migration](https://orpc.dev/docs/migrations/from-v1)
- [json 3.0.2 source](https://github.com/ruby/json/blob/v3.0.2/lib/json/common.rb)
- [json 3.0.2 changes](https://github.com/ruby/json/blob/v3.0.2/CHANGES.md)

Exact package evidence is the locked fixture and its executable tests. Zod
4.6.5 `v4/core/checks.js` uses `codePointLength` for string bounds; this is
package-source evidence, not an assertion about unversioned documentation.

The v1 references establish the wire boundary; actual fixture tests must prove
the chosen package patches. They do not establish implementation in this gem.
