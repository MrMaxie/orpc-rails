import assert from 'node:assert/strict'
import test from 'node:test'
import { oc, type ContractRouterClient } from '@orpc/contract'
import { createORPCClient } from '@orpc/client'
import { OpenAPILink } from '@orpc/openapi-client/fetch'
import type { JsonifiedClient } from '@orpc/openapi-client'
import * as z from 'zod'

const output = z.strictObject({ id: z.string(), name: z.string() })
const contract = {
  widgets: {
    show: oc.route({
      method: 'GET', path: '/widgets/{id}', inputStructure: 'detailed',
    }).input(z.strictObject({
      params: z.strictObject({ id: z.string() }),
      query: z.strictObject({ search: z.string().optional() }).optional(),
    })).output(output),
  },
}

test('pinned v1 contract and link retain path/query and inferred JSON output', async () => {
  let requested: URL | undefined
  const link = new OpenAPILink(contract, {
    url: 'http://fixture.invalid',
    fetch: async (request) => {
      requested = new URL(request.url)
      return Response.json({ id: '42', name: 'blue' })
    },
  })
  const client: JsonifiedClient<ContractRouterClient<typeof contract>> =
    createORPCClient(link)
  const result = await client.widgets.show({
    params: { id: '42' }, query: { search: 'blue & green' },
  })
  assert.equal(requested?.pathname, '/widgets/42')
  assert.equal(requested?.searchParams.get('search'), 'blue & green')
  assert.deepEqual(output.parse(result), { id: '42', name: 'blue' })
  assert.equal(output.safeParse({ id: '42' }).success, false)
  assert.equal(output.safeParse({ id: '42', name: 'blue', extra: 1 }).success, false)
})

// Compile-only negative control: unused on purpose, but checked by tsc.
function rejectWrongInput(client: ContractRouterClient<typeof contract>) {
  // @ts-expect-error path parameters are strings, not numbers
  void client.widgets.show({ params: { id: 42 } })
}
void rejectWrongInput
