## Context

This change depends on the schema representation, registry/exporter and
packaged-gem Testcontainers fixture from `export-rails-contracts`.
The gem does not yet implement either change. This document proposes the
optional second slice; conventional controller contracts remain usable alone.

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
schemas as export-only declarations. Proposed API shape:

```ruby
class RpcController < ApplicationController
  include OrpcRails::Procedures
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

Require JSON-valued inputs and outputs with a schema; callers use an explicit
empty object for no input and an explicit null schema/value for null output.
The profile does not represent root `undefined`. Reuse the supported types
and strict-object, safe-integer, omission/null semantics of the first change.
Ruby validation MUST match generated Zod validation without coercion,
key dropping, default insertion or arbitrary predicates. The decoder produces
string-keyed hashes; handlers return string-keyed JSON hashes, arrays and
scalars, not ActiveRecord models or symbol-keyed hashes requiring guesswork.

Alternative: directly wrap arbitrary Rails actions as RPC procedures.
Rejected because body parsing, return values, errors and schema validation
would be implicit. Conventional actions retain the HTTP export-only path.

### 2. Dispatch through an explicitly mounted Rails controller

Applications add an explicit POST route under a chosen RPC prefix to a
controller dispatch action. No automatic mount on `require` or Railtie load.
The remainder of the path identifies a registered dotted key using slash
segments (`/rpc/widgets/create` -> `widgets.create`). The route integration
also returns 405 for other methods under that prefix without invoking a
handler; it never hijacks unrelated application routes.

Only valid registered keys can dispatch. Reject unknown keys, empty or unsafe
segments and encoded path ambiguities; never constantize a request value or
send it as an arbitrary method name. Freeze registry snapshots after loading
and replace registrations on Rails reload, not per request.

Use the Rails controller lifecycle instead of a Rack bypass so authentication,
authorization and request-local helpers remain application-owned. The gem
must not skip CSRF verification, configure CORS or disable host authorization.
Cookie-authenticated deployments retain their CSRF policy; API-mode deployments
can choose their existing token policy. Tests exercise both callback denial and
successful dispatch, including a CSRF-protected controller negative case.

After callbacks allow dispatch, build context for that request only, decode
and validate input, invoke the handler once, validate output and serialize.
Context is not part of the exported contract or response. No request state
may be retained in process-global declarations.

### 3. Implement only the v1 JSON RPC envelope

Use the exact v1 package pins and compatibility gate from the first change.
The unversioned v2 docs are not an implementation source for this codec.

Supported request profile:

```http
POST /rpc/widgets/create
Content-Type: application/json

{"json":{"name":"blue"},"meta":[]}
```

`json` is required and can be any value admitted by the declared schema.
`meta` can be omitted or an empty array. Reject nonempty `meta`, `maps`,
unknown envelope keys, invalid JSON, invalid UTF-8, invalid envelope shapes,
duplicate JSON keys and native/non-JSON values; do not silently discard them.
Duplicate-key detection must happen before ordinary JSON parsing loses the
ambiguity. The implementation gate must prove a bounded Ruby parser approach
using standard libraries; do not claim duplicates are rejected by JSON.parse
by default.

Successful responses use HTTP 200, JSON content type and
`{"json": <validated output>, "meta": []}`. This profile has no native types:
no metadata IDs for Date/BigInt/undefined, no multipart or streaming. Large IDs,
decimals and timestamps remain declared strings, just as in HTTP contracts.
An actual default v1 RPCLink must succeed for valid JSON calls without custom
serializers or a custom fetch adapter.

Apply a configurable body-byte limit before decoding (default 1 MiB), bounded
nesting (default 64), and reject nonfinite numbers and unsafe integers.
A supported structured payload must satisfy these limits on input and output.
Document limits in the public API. Parse without creating symbols from user
keys, invoking constructors or evaluating metadata. An output outside the
profile becomes a safe internal error, never partial success.

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
become internal errors rather than invented typed outcomes.

Gem-generated failures use `defined: false`, safe code/message and consistent
HTTP/envelope status: malformed envelope/input or unsupported metadata ->
`BAD_REQUEST`/400; unknown procedure -> `NOT_FOUND`/404; unsupported method ->
`METHOD_NOT_SUPPORTED`/405; unsupported content type ->
`UNSUPPORTED_MEDIA_TYPE`/415; body size overflow -> `PAYLOAD_TOO_LARGE`/413;
unexpected handler/output/error-data failure -> `INTERNAL_SERVER_ERROR`/500.
Undefined protocol errors include `data: {}`, including internal errors,
and contain no exception text or stack. These are protocol errors, not
declared business errors. Test the exact default client's error decoding;
additional codes need no inference from an exception class.

Do not globally wrap exceptions or responses from Rails callbacks. A normal
callback's denial remains application-controlled and the RPC client call
rejects. Applications wanting typed auth errors can deliberately use declared
procedure errors in their own auth integration; the gem does not infer them.

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

## Open Questions

- Prove exact v1 envelope/error behavior with the pinned official client before
  codec implementation, including omitted metadata and null output.
- Verify standard-library duplicate-key detection and byte/depth-limit behavior
  under the selected Ruby/Rails middleware stack; this blocks accepting the
  codec implementation, not drafting the requirements.

## Source Evidence

- [v1 RPC protocol](https://v1.orpc.dev/docs/advanced/rpc-protocol)
- [v1 JSON serializer](https://v1.orpc.dev/docs/advanced/rpc-json-serializer)
- [v1 contract definitions](https://v1.orpc.dev/docs/contract-first/define-contract)
- [v1 client errors](https://v1.orpc.dev/docs/client/error-handling)
- [v2 wire/API migration](https://orpc.dev/docs/migrations/from-v1)

The v1 references establish the wire boundary; actual fixture tests must prove
the chosen package patches. They do not establish implementation in this gem.
