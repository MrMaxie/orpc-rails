import assert from 'node:assert/strict'
import test from 'node:test'
import { createORPCClient } from '@orpc/client'
import type { ContractRouterClient } from '@orpc/contract'
import { OpenAPILink } from '@orpc/openapi-client/fetch'
import type { JsonifiedClient } from '@orpc/openapi-client'
import { contract, schemas } from './contract.ts'

const origin = process.env.API_URL
assert.ok(origin, 'API_URL must point at the Rails Testcontainers fixture')
const client: JsonifiedClient<ContractRouterClient<typeof contract>> =
  createORPCClient(new OpenAPILink(contract, {
    url: origin, headers: { 'x-fixture-token': 'test-token' },
  }))

test('GET path and query retain strings and encoded punctuation', async () => {
  const result = await client.widgets.show({
    params: { id: '42' }, query: { search: 'blue & green' },
  })
  assert.deepEqual(result, { id: '42', name: 'blue', search: 'blue & green' })
  schemas['widgets.show'].output.parse(result)
})

test('empty query value is distinct from omission', async () => {
  const empty = await client.widgets.show({ params: { id: '42' }, query: { search: '' } })
  const omitted = await client.widgets.show({ params: { id: '42' } })
  assert.equal(empty.search, '')
  assert.equal('search' in omitted, false)
})

test('POST keeps the Rails JSON root and large identifiers remain strings', async () => {
  const result = await client.widgets.create({ body: { widget: { name: 'green' } } })
  assert.deepEqual(result, { id: '9007199254740993', name: 'green' })
  schemas['widgets.create'].output.parse(result)
  const response = await fetch(`${origin}/widgets`, {
    method: 'POST', headers: {
      'content-type': 'application/json', 'x-fixture-token': 'test-token',
    }, body: JSON.stringify({ widget: { name: 'green' } }),
  })
  assert.equal(response.status, 201)
})

test('Rails authentication callback is unchanged', async () => {
  const anonymous: JsonifiedClient<ContractRouterClient<typeof contract>> =
    createORPCClient(new OpenAPILink(contract, { url: origin }))
  await assert.rejects(anonymous.widgets.show({ params: { id: '42' } }))
  const response = await fetch(`${origin}/widgets/42`)
  assert.equal(response.status, 401)
  assert.deepEqual(await response.json(), { error: 'Unauthorized' })
})

test('conventional Rails 422 remains application-defined', async () => {
  await assert.rejects(client.widgets.create({ body: { widget: { name: 'invalid' } } }))
  const response = await fetch(`${origin}/widgets`, {
    method: 'POST', headers: {
      'content-type': 'application/json', 'x-fixture-token': 'test-token',
    }, body: JSON.stringify({ widget: { name: 'invalid' } }),
  })
  assert.equal(response.status, 422)
  assert.deepEqual(await response.json(), { errors: ['Name invalid'] })
})

test('exported validators detect broken real HTTP output and invalid input', async () => {
  const broken = await client.widgets.create({ body: { widget: { name: 'broken-output' } } })
  assert.equal(schemas['widgets.create'].output.safeParse(broken).success, false)
  assert.equal(schemas['widgets.show'].input.safeParse({ params: { id: 42 } }).success, false)
  assert.equal(schemas['widgets.show'].input.safeParse({ params: { id: null } }).success, false)
  assert.equal(schemas['widgets.show'].input.safeParse({ params: { id: '42', extra: true } }).success, false)
  assert.equal('destroy' in contract.widgets, false)
})

function typeAssertions() {
  // @ts-expect-error path parameter is a wire string
  void client.widgets.show({ params: { id: 42 } })
  // @ts-expect-error Rails body wrapping is explicit
  void client.widgets.create({ name: 'green' })
  // @ts-expect-error unregistered action is not exposed
  void client.widgets.destroy({ params: { id: '42' } })
}
void typeAssertions
