import assert from 'node:assert/strict'
import test from 'node:test'
import { createORPCClient, isDefinedError, ORPCError } from '@orpc/client'
import { RPCLink } from '@orpc/client/fetch'
import type { ContractRouterClient } from '@orpc/contract'
import { contract, schemas } from './rpc-contract.ts'
import { conformance } from './schema-conformance.ts'

const origin = process.env.API_URL
assert.ok(origin)
const client: ContractRouterClient<typeof contract> = createORPCClient(new RPCLink({
  url: `${origin}/rpc`, headers: { 'x-fixture-token': 'test-token' },
}))

test('generated echo contract calls the installed gem through default RPCLink', async () => {
  const output = await client.widgets.echo({ name: 'blue', note: null })
  assert.deepEqual(output, { id: '9007199254740993', name: 'blue', note: null })
  schemas['widgets.echo'].output.parse(output)
  const unicode = await client.widgets.echo({ name: 'é', note: 'note', nickname: '😀' })
  assert.equal(unicode.nickname, '😀')
})

test('invalid inputs reject through the real client without coercion', async () => {
  // RPCLink does not validate schemas automatically; server validation is real.
  await assert.rejects(client.widgets.echo({ name: 'blue', note: null, nickname: 'e\u0301' }), (error: unknown) => {
    assert.ok(error instanceof ORPCError)
    assert.equal(error.code, 'BAD_REQUEST')
    assert.equal(error.status, 400)
    assert.equal(error.defined, false)
    return true
  })
})

test('unexpected handlers and invalid outputs fail safely through RPCLink', async () => {
  for (const name of ['explode', 'broken', 'oversized']) {
    await assert.rejects(client.widgets.echo({ name, note: null }), (error: unknown) => {
      assert.ok(error instanceof ORPCError)
      assert.equal(error.code, 'INTERNAL_SERVER_ERROR')
      assert.equal(error.status, 500)
      assert.equal(error.defined, false)
      assert.equal(error.message, 'Internal server error')
      assert.deepEqual(error.data, {})
      return true
    })
  }
})

test('generated validators agree with Ruby on every supported schema node', () => {
  for (const { schema, samples } of conformance) {
    for (const { value, expected } of samples) assert.equal(schema.safeParse(value).success, expected)
  }
})

test('empty object input and explicit null output survive the installed codec', async () => {
  assert.equal(await client.probe.nullOutput({}), null)
})

test('declared conflict retains status/data and isDefinedError through RPCLink', async () => {
  await assert.rejects(client.widgets.create({ name: 'blue' }), (error: unknown) => {
    assert.ok(error instanceof ORPCError)
    assert.equal(isDefinedError(error), true)
    assert.equal(error.code, 'CONFLICT')
    assert.equal(error.status, 409)
    assert.deepEqual(error.data, { name: 'blue' })
    return true
  })
  for (const name of ['undeclared', 'invalid-error', 'huge-error']) {
    await assert.rejects(client.widgets.create({ name }), (error: unknown) => {
      assert.ok(error instanceof ORPCError)
      assert.equal(isDefinedError(error), false)
      assert.equal(error.code, 'INTERNAL_SERVER_ERROR')
      assert.equal(error.message, 'Internal server error')
      assert.deepEqual(error.data, {})
      return true
    })
  }
})

function typeControls() {
  // @ts-expect-error name must be a string in the generated contract
  void client.widgets.echo({ name: 42, note: null })
  // @ts-expect-error required nullable note cannot be omitted
  void client.widgets.echo({ name: 'blue' })
  // @ts-expect-error router exposes no arbitrary Ruby methods
  void client.widgets.destroy({})
}
void typeControls
