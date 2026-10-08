## ADDED Requirements

### Requirement: Only declared endpoints are exported

The gem SHALL export only explicitly registered controller actions with a
stable dotted router key, HTTP method/path, input schema and output schema.
Registration SHALL be idempotent across Rails reloads. Export-only registration
MUST NOT install request validation, alter rendering/authentication callbacks,
mount routes or expose undeclared actions.

#### Scenario: Conventional controller remains conventional

- **WHEN** a Rails controller registers `widgets.show` for `GET /widgets/:id`
  while also containing an unregistered `destroy` action
- **THEN** the contract contains only `widgets.show`
- **AND** the existing `show` action, callbacks, status and JSON are unchanged

#### Scenario: Reload does not duplicate contracts

- **WHEN** Rails reloads the same declared controller twice
- **THEN** one current registration is exported with the same router key

### Requirement: Supported schemas have precise JSON semantics

The gem SHALL support bounded strings, finite bounded numbers, bounded safe
integers, booleans, JSON scalar literals, string enums, homogeneous arrays,
objects, optional object properties and nullable values. Generated Zod schemas
SHALL reject unknown object properties. Omission and null MUST be distinct.
Unsupported schemas MUST fail export with an endpoint and schema location;
they MUST NOT become `any`, `unknown` or a guessed schema.

#### Scenario: Optional is not nullable

- **WHEN** `nickname` is optional but not nullable and `note` is required
  and nullable
- **THEN** generated validation accepts omitted `nickname` and null `note`
- **AND** it rejects null `nickname`, omitted `note` and unknown fields

#### Scenario: Integers preserve JavaScript precision

- **WHEN** a schema declares an integer with bounds outside
  `-(2^53 - 1)` through `2^53 - 1`
- **THEN** export fails and identifies the field requiring string encoding

#### Scenario: Unsupported transformation is not silently erased

- **WHEN** a declaration contains an arbitrary Ruby predicate or transform
- **THEN** export fails without replacing the current destination file

### Requirement: HTTP mapping matches the existing Rails route

The exporter SHALL verify that each method/path resolves to its declared Rails
controller/action and map simple `:segment` parameters to `{segment}`.
Contracts SHALL use detailed input locations (`params`, `query`, `headers`,
`body`) and compact JSON output. Params, flat query leaves and lowercase
headers SHALL have string wire types. Body schemas SHALL preserve explicitly
declared JSON roots. Supported methods SHALL be GET, POST, PUT, PATCH and DELETE;
success status SHALL be explicitly 200 or 201. Unsupported route shapes or
location/type combinations MUST fail export rather than change the route.

#### Scenario: GET preserves path and query strings

- **WHEN** `GET /widgets/:id` declares string `params.id` and optional string
  `query.search` and the official client calls it with `id: "42"`
  and `search: "blue & green"`
- **THEN** Rails receives the correct path value and decoded query value
- **AND** no JSON request body or duplicate route prefix is sent

#### Scenario: Empty query string is not omission

- **WHEN** a caller supplies an optional query string as `""` and then omits it
  in a separate call
- **THEN** Rails receives an empty string in the first call and no query field
  in the second

#### Scenario: JSON body keeps Rails parameter wrapping

- **WHEN** `POST /widgets` declares body `{ widget: { name: string } }`
  and success status 201
- **THEN** the client sends that JSON root unchanged
- **AND** Rails receives `params[:widget][:name]` and the client reads its JSON
  success body

#### Scenario: Path and action mismatch is rejected

- **WHEN** a declaration targets a different controller/action than its route
  or omits a required path parameter
- **THEN** export fails with the conflicting route and declaration location

#### Scenario: Unsupported HTTP mapping is rejected

- **WHEN** a declaration uses an optional path segment, wildcard, GET body,
  nested query object, nullable query value or empty 204 output
- **THEN** export fails with the unsupported mapping identified

### Requirement: Generated contracts work with the official HTTP client

Export SHALL produce importable TypeScript with executable Zod input/output
schemas, a nested v1 oRPC router `contract` and `Contract` type alias.
The generated module SHALL import only Zod and `@orpc/contract`, with no server
implementation or application context. A frontend SHALL be able to call the
Rails endpoints using official `createORPCClient` and `OpenAPILink`, with
`JsonifiedClient<ContractRouterClient<typeof contract>>` types and no custom
transport. Contract generation MUST NOT claim automatic controller validation
or typed oRPC errors for arbitrary Rails error bodies.

#### Scenario: Real client, real endpoint

- **WHEN** a TypeScript fixture imports the generated module, typechecks it
  and calls `widgets.show` through official OpenAPILink against live Rails
- **THEN** the call resolves to the expected JSON output with inferred types
- **AND** parsing that output with the exported Zod schema succeeds

#### Scenario: Types and validators are not vacuous

- **WHEN** the fixture passes a number instead of string `params.id`
  or parses a response missing required `name`
- **THEN** the former fails TypeScript compilation and the latter fails Zod
  parsing without a cast that disables the test

#### Scenario: Existing Rails errors remain application-defined

- **WHEN** an exported conventional endpoint returns its existing 422 JSON
  validation error
- **THEN** the Rails status/body are unchanged and the client rejects the call
- **AND** the generated contract does not mark that arbitrary body as a defined
  oRPC business error

### Requirement: Exports are deterministic and safe

Generation SHALL sort router entries and fields, escape all literal data and
emit UTF-8/LF without timestamps, absolute machine paths or secrets.
It SHALL reject duplicate/prefix-colliding router keys, oRPC reserved keys and
unsafe prototype keys. The export task SHALL write only the selected file,
atomically after complete validation. A check task SHALL fail on drift without
modifying the destination.

#### Scenario: Equivalent declarations produce identical bytes

- **WHEN** equivalent declarations are exported in separate processes with
  different registration order
- **THEN** the generated files are byte-identical

#### Scenario: Literal content cannot inject code

- **WHEN** an enum contains quotes, backslashes, Unicode or text resembling
  TypeScript source
- **THEN** generated code compiles and the schema retains the exact literal
  value without executing that text

#### Scenario: Conflicting router keys fail safely

- **WHEN** registrations include `widgets` and `widgets.show`, duplicate
  `widgets.show` declarations, or a reserved segment such as `then`
- **THEN** export fails and leaves the previous file unchanged

#### Scenario: Drift check never writes

- **WHEN** a schema changes after its contract was generated and the check
  task is run
- **THEN** the task exits nonzero and identifies contract drift
- **AND** the file contents and modification time remain unchanged
