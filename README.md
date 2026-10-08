# orpc-rails

Export existing Rails JSON endpoints as executable Zod schemas and typed
[oRPC v1](https://v1.orpc.dev) contracts. Call them from TypeScript with the
official `OpenAPILink` client; keep your controllers, callbacks and responses.

## Add to Rails

The gem is not published yet. Use the repository in your Gemfile:

```ruby
gem "orpc-rails", github: "MrMaxie/orpc-rails", branch: "master", require: "orpc_rails"
```

Run `bundle install`. Ruby runtime dependencies are `actionpack` and `railties`;
Node and schema-validation gems are not required on the Rails server.

## Declare an endpoint

```ruby
# config/routes.rb
get "/widgets/:id", to: "widgets#show"

# app/controllers/widgets_controller.rb
class WidgetsController < ApplicationController
  include OrpcRails::Controller
  S = OrpcRails::Schema

  orpc_contract :show,
    key: "widgets.show", method: :get, path: "/widgets/:id", success_status: 200,
    input: S.object(params: S.object(id: S.string)),
    output: S.object(id: S.string, name: S.string)

  def show
    widget = Widget.find(params[:id])
    render json: { id: widget.id.to_s, name: widget.name }
  end
end
```

Only declared actions are exported. Declarations do not add routes, validate
requests, change authentication or wrap Rails errors. Describe the JSON you
actually send, not an ActiveRecord model's attributes.

## Generate and check

Choose an existing destination directory:

```sh
bundle exec rake 'orpc:export[frontend/src/contract.ts]'
bundle exec rake 'orpc:check[frontend/src/contract.ts]'
```

Both tasks load the application's controllers and validate their routes.
Export replaces the selected file atomically after validation. Check exits
nonzero on missing or changed contracts and never writes the file.

The generated module exports `contract`, `Contract` and `schemas`, keyed by
the dotted endpoint name. Equivalent declarations produce identical bytes.

## Call from TypeScript

Install the tested v1 packages in the frontend:

```sh
npm install @orpc/client@1.15.5 @orpc/contract@1.15.5 @orpc/openapi-client@1.15.5 zod@4.6.5
```

```ts
import { createORPCClient } from '@orpc/client'
import type { ContractRouterClient } from '@orpc/contract'
import { OpenAPILink } from '@orpc/openapi-client/fetch'
import type { JsonifiedClient } from '@orpc/openapi-client'
import { contract, schemas } from './contract'

const link = new OpenAPILink(contract, { url: 'http://localhost:3000' })
const client: JsonifiedClient<ContractRouterClient<typeof contract>> =
  createORPCClient(link)

const widget = await client.widgets.show({ params: { id: '42' } })
schemas['widgets.show'].output.parse(widget)
```

Use the server origin as `url`; generated paths already include the Rails
route prefix. Configure authentication through the link's headers or fetch
options as appropriate for your application. Static client types do not
validate controller responses: call the exported schemas when you need
runtime validation. Existing non-2xx Rails bodies remain application-defined.

## Schema and HTTP limits

```ruby
S.string(min_length: 1, max_length: 80)
S.number(min: 0, max: 100.5)
S.integer(min: 0, max: 100)
S.boolean
S.literal("fixed")                 # string, finite number, boolean or null
S.enum("draft", "published")
S.array(S.string, min_length: 1, max_length: 10)
S.object(nickname: S.string.optional, note: S.string.nullable)
```

Objects reject unknown fields. `.optional` permits omission of an object
property; `.nullable` permits JSON null. Combine them as
`S.string.nullable.optional`. Optional roots and optional array elements are
not supported. Integers and integer-valued bounds must stay within
`-(2^53 - 1)..(2^53 - 1)`; serialize larger IDs and decimal amounts as strings.
Dates and times are explicit strings. No defaults, transforms, recursive
schemas or arbitrary Ruby predicates are inferred.

Inputs use detailed locations:

- `params`: required string fields matching every `:segment` in the path.
- `query`: flat string fields, optionally omitted; no arrays, nested objects or
  nulls. An empty string is distinct from omission.
- `headers`: lowercase HTTP names with string values, optionally omitted.
- `body`: an explicit JSON schema for POST, PUT, PATCH or DELETE. Include the
  Rails root yourself, for example
  `S.object(body: S.object(widget: S.object(name: S.string)))`.

GET bodies are rejected. Success status must be 200 or 201; output is the JSON
body. Simple literal paths and required `:segments` are supported. Wildcards,
optional segments, constrained routes, dynamic controller dispatch and
potentially shadowed routes are rejected instead of guessed. Router keys must
be dotted identifiers without duplicates, prefix collisions or reserved
JavaScript/oRPC segments.

## Tested compatibility

The packaged gem, generated TypeScript and real HTTP calls are tested on
Linux containers with these pairs:

| Ruby | Rails |
| --- | --- |
| 3.3.12 | 7.2.4 |
| 3.4.11 | 8.1.4 |

The client fixture pins oRPC 1.15.5, Zod 4.6.5, TypeScript 5.9.3 and Node
24.18.0. Use the v1 documentation; current oRPC v2 APIs are not this
compatibility target. The optional RPCLink/procedure API is not implemented.

## Development

```sh
bundle install
bundle exec rake test
ruby bin/test-integration          # both Ruby/Rails pairs
ruby bin/test-integration rails72  # one pair
```

Unit and packaging tests need no Docker. Integration tests require a reachable
Linux Docker daemon and use Ruby Testcontainers to install the built gem in
Rails and run a separate official-client container. They use locked fixture
dependencies, ephemeral host ports and per-run networks, clean up on failure,
and fail explicitly if Docker is unavailable. Initial image/dependency builds
need network access.

## License

[MIT](LICENSE).
