## Context

The repository currently contains project setup, not a working Ruby gem.
The primary consumers are Rails developers declaring an API and TypeScript
frontend developers importing its contract. This is a proposed design.

Two transports must not be conflated: conventional Rails JSON routes are
called with `OpenAPILink`; `RPCLink` needs the oRPC RPC envelope and server
routing defined in the dependent procedure change.

## Goals / Non-Goals

**Goals:**

- One explicit Ruby contract declaration per exposed endpoint.
- Runnable Zod schemas and typed oRPC contracts, not TypeScript interfaces
  disguised as runtime validators.
- Export without modifying controller behavior or requiring Node on Rails.
- Prove actual generated-client calls against a packaged gem in Rails.

**Non-Goals:**

- Infer contracts from ActiveRecord columns, strong parameters or responses.
- Publish every Rails route, generate OpenAPI documents or a frontend SDK.
- Add runtime validation to conventional controllers implicitly.
- Support files, streaming, arbitrary Zod transforms or every Rails route form.

## Decisions

### 1. Start with stable oRPC v1, not unversioned current documentation

Live npm metadata inspected during planning reports `@orpc/contract` 1.15.5
as `latest` and Zod 4.6.5 as `latest`. The current oRPC site documents v2 beta:
its migration guide changes `.route(...)` to OpenAPI metadata, package imports,
RPC type metadata and error envelopes. Use the official **v1** documentation
for this first implementation. These observations are a planning snapshot,
not a claim that live docs describe precisely those npm patch versions.

Initial fixture pins: oRPC packages 1.15.5, Zod 4.6.5, and a compatible locked
TypeScript version. Confirm package availability and compile the fixture before
implementation relies on them. Keep all oRPC packages on the same version.
Generated public imports use `@orpc/contract` and `zod`; HTTP client examples
use `@orpc/client` and `@orpc/openapi-client/fetch`.

Proposed Ruby/Rails matrix: Ruby 3.3 with Rails 7.2 and Ruby 3.4 with Rails 8.1,
with compatible Rails patches locked per fixture. Treat these as acceptance
targets, not verified support. Ruby requirement is `>= 3.3`; initial Rails
bounds are `>= 7.2, < 9`. Test declared supported lines before releasing; narrow
bounds rather than advertise an incompatible combination. Node is test/client
tooling only; use a pinned supported LTS image, not a Rails runtime dependency.

Alternative: start on v2 beta. Rejected for the first stable gem because its
wire/API changes would blur the compatibility target. v2 support needs a
separate versioned decision and fixture, not a silent generator change.

### 2. Explicit controller contracts, normalized schema representation

Use `OrpcRails` as the Ruby namespace and `require "orpc_rails"` as the entry
point. A Rails concern supplies an export-only declaration associated with a
controller action. The following illustrates the proposed public API:

```ruby
include OrpcRails::Controller
S = OrpcRails::Schema

orpc_contract :show,
  key: "widgets.show",
  method: :get,
  path: "/widgets/:id",
  input: S.object(params: S.object(id: S.string)),
  output: S.object(id: S.string, name: S.string)
```

The implementation can refine method names, but MUST retain one opt-in
registration with action, stable router key, method, path, input and output.
Normalize declarations into an immutable intermediate representation shared
by export and later procedure validation. Never execute handler bodies to
infer schemas. Registration must converge after Rails reloads rather than
accumulate duplicate entries.

Support strings with length bounds, finite numbers with bounds, safe integers
with bounds, booleans, JSON scalar literals, string enums, homogeneous arrays,
objects, optional object properties and nullable values. Objects reject
unknown properties in generated validation. Optional means omission;
nullable means JSON null. Reject defaults, arbitrary Ruby predicates,
transforms, recursive schemas and unsupported nodes instead of emitting `any`.
Numbers/integers follow JavaScript representability; larger IDs and decimal
amounts must be declared and serialized as strings. Dates/times are explicit
strings, not implicitly revived JS Dates. Output schemas describe wire JSON,
not ActiveRecord or Ruby objects before serialization.

Alternative: add dry-schema, JSON Schema conversion or a TypeScript parser.
Rejected: a bounded IR with matching validators can cover the initial scope
without new runtime dependencies or ambiguous conversion semantics.

### 3. Detailed HTTP inputs, ordinary JSON outputs

Generate v1 `oc.route({ method, path, inputStructure: 'detailed' })` contracts.
Convert a supported Rails segment `:id` into oRPC `{id}`. The contract path
includes its application route prefix; examples use the server origin as
OpenAPILink's `url` to avoid duplicating that prefix.

Input has only declared `params`, `query`, `headers`, and `body` fields.
Path parameters and query leaves are strings because Rails receives them as
strings. The initial query profile is flat scalar strings with optional
omission; no nullable query values or arrays/nested query objects. Headers
are lowercase string fields. GET has no request body; POST/PUT/PATCH/DELETE
can use a declared JSON body. Body schemas include any Rails parameter root
such as `{ widget: { name: ... } }` explicitly; export never adds wrapping.

Output is the compact JSON body and a declared success status, initially 200
or 201. No 204/empty responses, redirects or response-header schemas in the
first slice. Export rejects unsupported method/path shapes, missing or extra
path parameters, incompatible input locations and route/action mismatches.
Use explicit HTTP method/path to disambiguate Rails routes; verify it resolves
to the declared controller/action. Wildcards, optional path segments, dynamic
controller dispatch and unsupported constrained routes fail with a location.

Existing non-2xx Rails responses remain application-defined. The contract
must NOT claim typed oRPC business errors for arbitrary Rails error bodies.
The official client's ordinary error behavior remains available; applications
can choose their own custom error decoder outside this gem's first slice.
Export-only mode installs no callbacks, routes or error-rendering hooks.

### 4. Deterministic, safe source generation

Export nested router objects with actual Zod schemas and explicit `.input`
and `.output` definitions. Export reusable schemas plus `contract` and a
`Contract` type alias. Generated code imports no Rails code, `@orpc/server`,
private values or application business logic.

Quote identifiers and literal values with a JSON-compatible encoder; never
interpolate caller-supplied TypeScript source. Reject invalid/colliding router
keys, prefix collisions such as `widgets` versus `widgets.show`, oRPC reserved
keys (`then`, `bind`, `call`, `apply`, `valueOf`, `toString`, `toJSON`) and unsafe
prototype keys. Sort declarations and fields deterministically; emit UTF-8
with LF, no timestamps, absolute paths or machine identifiers.

Proposed tasks: `bundle exec rake 'orpc:export[path/to/contract.ts]'` writes
only the requested destination, and `orpc:check[path/to/contract.ts]` compares
without writing. Build and validate in memory first; replace the output
atomically only on success. A failed export leaves an existing file unchanged.

Minimal frontend consumption uses the official client, not a custom wrapper:

```ts
import { createORPCClient } from '@orpc/client'
import type { ContractRouterClient } from '@orpc/contract'
import { OpenAPILink } from '@orpc/openapi-client/fetch'
import type { JsonifiedClient } from '@orpc/openapi-client'
import { contract } from './contract'

const link = new OpenAPILink(contract, { url: apiOrigin })
const client: JsonifiedClient<ContractRouterClient<typeof contract>> =
  createORPCClient(link)
await client.widgets.show({ params: { id: '42' } })
```

The generated Zod schemas are runnable, but neither static types nor this link
by itself guarantees automatic application-level request/response validation.
Tests parse fixtures with the exported schemas explicitly and verify client
inference with positive and negative TypeScript compilation cases.

### 5. Small gem and actual client acceptance

Separate `lib/orpc_rails/schema`, registry/export and Rails concern/Railtie
surfaces without introducing a generic adapter framework. Runtime dependencies
are the Rails components actually used (`actionpack`, `railties`) plus Ruby
standard libraries; do not depend on full Rails or ActiveRecord unnecessarily.
Testcontainers, Rails fixture server, TypeScript and JS packages are development
or fixture dependencies. Use Minitest and Rake; no parallel test framework is
needed for the initial gem.

Use an explicit distribution allowlist and a single Ruby version constant
referenced by the gemspec. Build the `.gem`, install it in the fixture and test
that installed artifact, not just a source checkout. No release/version bump or
CHANGELOG entry is created until there is a consumer outcome to release.

Ruby Testcontainers orchestrates a Rails HTTP container and a Node client
container on an isolated network. Publish an ephemeral host port for readiness
checks; Node reaches Rails by container network alias, not its own localhost.
Use locked dependencies and pinned images, a bounded HTTP readiness probe,
`ensure` cleanup and no fixed sleeps or fixed host ports. The fixture uses
in-memory widgets; no database/cache/queue is necessary.

Run the real generated contract through `tsc --noEmit` and actual official
client HTTP calls. Cover GET path/query and POST JSON-rooted bodies, protected
routes, unchanged ordinary Rails errors, invalid schema declarations,
deterministic output and intentional contract drift. Container startup/client
failure fails the integration job with sanitized logs; missing Docker is not
a silently skipped successful integration run. Unit-only tests remain runnable
without Docker through a separate task.

## Risks / Trade-offs

- Explicit declarations can drift from controller output → real client tests
  and schema parsing of actual response JSON, plus a non-writing export check.
- Query strings do not retain JSON scalar types → string-only initial query
  profile; conversion stays in conventional Rails code.
- A small schema DSL excludes some APIs → reject unsupported constructs rather
  than weaken types or infer conversions.
- Version bounds overstate support → test supported Rails lines and document
  matrix exclusions before packaging a release.
- Importing shared contracts can expose data → export declarations only, never
  defaults from application instances, credentials or request context.

## Migration Plan

Implement and test export-only mode first. Existing applications opt in one
route at a time; removing a declaration only removes that exported contract.
No controller replacement or database migration is involved. Breaking contract
changes require SemVer review; regenerate client contracts in the same change.
Do not archive this proposal into accepted specs before implementation and
acceptance. The optional procedure proposal depends on this change.

## Open Questions

- Validate the proposed Ruby/Rails matrix and exact JS fixture pins before
  declaring them supported; this is the first implementation gate.
- Final DSL spelling can be refined before it becomes public. The registration
  fields, JSON semantics and transport distinction are normative.

## Source Evidence

- [v1 contract definitions](https://v1.orpc.dev/docs/contract-first/define-contract)
- [v1 HTTP link](https://v1.orpc.dev/docs/openapi/client/openapi-link)
- [v1 input/output mapping](https://v1.orpc.dev/docs/openapi/input-output-structure)
- [v2 migration](https://orpc.dev/docs/migrations/from-v1)
- [npm contract metadata](https://registry.npmjs.org/@orpc/contract/latest)
- [npm Zod metadata](https://registry.npmjs.org/zod/latest)
- [RubyGems specification](https://guides.rubygems.org/specification-reference/)
- [Ruby Testcontainers](https://github.com/testcontainers/testcontainers-ruby)

These are upstream references, not evidence that this gem already works.
Exact package behavior must be checked against the pinned test fixture.
