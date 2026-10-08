import assert from 'node:assert/strict'
import { createServer } from 'node:http'
import type { IncomingHttpHeaders } from 'node:http'
import test from 'node:test'
import type { TestContext } from 'node:test'
import { oc, type ContractRouterClient } from '@orpc/contract'
import { createORPCClient, isDefinedError, ORPCError } from '@orpc/client'
import { StandardRPCJsonSerializer, StandardRPCSerializer } from '@orpc/client/standard'
import { RPCLink } from '@orpc/client/fetch'
import * as z from 'zod'

// A wire oracle, not the gem's procedure server: real loopback HTTP, default
// pinned RPCLink, scripted responses. Rails dispatch acceptance is still pending.
const widgetOutput = z.strictObject({ id: z.string(), name: z.string() })
const contract = {
  widgets: {
    create: oc.input(z.strictObject({ name: z.string(), nickname: z.string().optional() }))
      .output(widgetOutput)
      .errors({ CONFLICT: { status: 409, data: z.strictObject({ name: z.string() }) } }),
  },
  probe: {
    nullOutput: oc.input(z.strictObject({})).output(z.null()),
    // Deliberately outside the gem's JSON profile: observe native serializer
    // behavior without casts or pretending these are supported procedure schemas.
    native: oc.input(z.union([z.date(), z.bigint(), z.number(), z.array(z.string().optional()), z.undefined()])).output(z.null()),
  },
}

type Captured = { method: string | undefined; url: string | undefined; headers: IncomingHttpHeaders; body: string }
type Reply = { status: number; body: unknown }

async function wireServer(t: TestContext, reply: Reply) {
  const requests: Captured[] = []
  const server = createServer(async (request, response) => {
    const chunks: Buffer[] = []
    for await (const chunk of request) chunks.push(Buffer.from(chunk))
    requests.push({ method: request.method, url: request.url, headers: request.headers, body: Buffer.concat(chunks).toString('utf8') })
    response.writeHead(reply.status, { 'content-type': 'application/json' })
    response.end(JSON.stringify(reply.body))
  })
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject)
    server.listen(0, '127.0.0.1', resolve)
  })
  t.after(() => new Promise<void>((resolve, reject) => {
    server.closeAllConnections()
    server.close(error => error ? reject(error) : resolve())
  }))
  const address = server.address()
  assert.ok(address && typeof address !== 'string')
  return { requests, url: `http://127.0.0.1:${address.port}/rpc` }
}

test('default RPCLink sends POST, nested slash path and json without empty meta', async t => {
  const server = await wireServer(t, { status: 200, body: { json: { id: '9007199254740993', name: 'blue' }, meta: [] } })
  const client: ContractRouterClient<typeof contract> = createORPCClient(new RPCLink({ url: server.url }))
  const result = await client.widgets.create({ name: 'blue', nickname: undefined })
  assert.deepEqual(result, { id: '9007199254740993', name: 'blue' })
  widgetOutput.parse(result)
  const [request] = server.requests
  assert.equal(request.method, 'POST')
  assert.equal(request.url, '/rpc/widgets/create')
  assert.equal(request.headers['content-type'], 'application/json')
  assert.equal(request.body, '{"json":{"name":"blue"}}')
})

test('JSON null round trips with omitted or empty response metadata', async t => {
  for (const body of [{ json: null }, { json: null, meta: [] }]) {
    const server = await wireServer(t, { status: 200, body })
    const client: ContractRouterClient<typeof contract> = createORPCClient(new RPCLink({ url: server.url }))
    assert.equal(await client.probe.nullOutput({}), null)
    assert.equal(server.requests[0].body, '{"json":{}}')
  }
})

test('literal v1 defined/status/error data survive official serialization and decoding', async t => {
  const expected = new ORPCError('CONFLICT', {
    defined: true, status: 409, message: 'Widget already exists', data: { name: 'blue' },
  }).toJSON()
  assert.deepEqual(expected, {
    defined: true, code: 'CONFLICT', status: 409, message: 'Widget already exists', data: { name: 'blue' },
  })
  const serializer = new StandardRPCSerializer(new StandardRPCJsonSerializer())
  assert.equal(JSON.stringify(serializer.serialize(expected)), JSON.stringify({ json: expected }))
  const server = await wireServer(t, { status: 409, body: { json: expected, meta: [] } })
  const client: ContractRouterClient<typeof contract> = createORPCClient(new RPCLink({ url: server.url }))
  await assert.rejects(client.widgets.create({ name: 'blue' }), (error: unknown) => {
    assert.ok(error instanceof ORPCError)
    assert.equal(isDefinedError(error), true)
    assert.deepEqual(error.toJSON(), expected)
    return true
  })
})

test('generic error uses false, matching status and explicit empty data', async t => {
  const expected = new ORPCError('INTERNAL_SERVER_ERROR', {
    defined: false, status: 500, message: 'Internal server error', data: {},
  }).toJSON()
  assert.deepEqual(expected, {
    defined: false, code: 'INTERNAL_SERVER_ERROR', status: 500, message: 'Internal server error', data: {},
  })
  const server = await wireServer(t, { status: 500, body: { json: expected, meta: [] } })
  const client: ContractRouterClient<typeof contract> = createORPCClient(new RPCLink({ url: server.url }))
  await assert.rejects(client.widgets.create({ name: 'blue' }), (error: unknown) => {
    assert.ok(error instanceof ORPCError)
    assert.equal(isDefinedError(error), false)
    assert.deepEqual(error.toJSON(), expected)
    return true
  })
})

test('missing defined field is malformed; absent data alone is accepted by v1', async t => {
  const base = { code: 'CONFLICT', status: 409, message: 'Widget already exists' }
  for (const json of [base, { ...base, defined: true }]) {
    const server = await wireServer(t, { status: 409, body: { json } })
    const client: ContractRouterClient<typeof contract> = createORPCClient(new RPCLink({ url: server.url }))
    await assert.rejects(client.widgets.create({ name: 'blue' }), (error: unknown) => {
      assert.ok(error instanceof ORPCError)
      assert.equal(isDefinedError(error), 'defined' in json)
      if ('defined' in json) assert.equal(error.data, undefined)
      return true
    })
  }
})

test('client trusts envelope status: the Rails codec must enforce agreement itself', async t => {
  const json = new ORPCError('CONFLICT', { defined: true, status: 409, data: { name: 'blue' } }).toJSON()
  const server = await wireServer(t, { status: 500, body: { json } })
  const client: ContractRouterClient<typeof contract> = createORPCClient(new RPCLink({ url: server.url }))
  await assert.rejects(client.widgets.create({ name: 'blue' }), (error: unknown) => {
    assert.ok(error instanceof ORPCError)
    assert.equal(error.status, 409)
    assert.equal(isDefinedError(error), true)
    return true
  })
})

test('native types and undefined require rejection outside the JSON-only profile', async t => {
  const cases = [
    { input: new Date('2026-01-01T00:00:00.000Z'), body: '{"json":"2026-01-01T00:00:00.000Z","meta":[[1]]}' },
    { input: 9007199254740993n, body: '{"json":"9007199254740993","meta":[[0]]}' },
    { input: NaN, body: '{"json":null,"meta":[[2]]}' },
    { input: [undefined], body: '{"json":[null],"meta":[[3,0]]}' },
    { input: undefined, body: '{}' },
  ]
  for (const { input, body } of cases) {
    const server = await wireServer(t, { status: 200, body: { json: null } })
    const client: ContractRouterClient<typeof contract> = createORPCClient(new RPCLink({ url: server.url }))
    await client.probe.native(input)
    assert.equal(server.requests[0].body, body)
  }
})

test('Infinity loses its origin as JSON null: validate before sending, not by server inference', async t => {
  for (const input of [Infinity, -Infinity]) {
    assert.equal(z.number().safeParse(input).success, false)
    const server = await wireServer(t, { status: 200, body: { json: null } })
    const client: ContractRouterClient<typeof contract> = createORPCClient(new RPCLink({ url: server.url }))
    await client.probe.native(input)
    assert.equal(server.requests[0].body, '{"json":null}')
  }
})

test('GET is configurable upstream but outside the gem POST-only profile', async t => {
  const error = new ORPCError('METHOD_NOT_SUPPORTED', { status: 405, data: {} }).toJSON()
  const server = await wireServer(t, { status: 405, body: { json: error, meta: [] } })
  const client: ContractRouterClient<typeof contract> = createORPCClient(new RPCLink({ url: server.url, method: 'GET' }))
  await assert.rejects(client.widgets.create({ name: 'blue' }), (caught: unknown) => {
    assert.ok(caught instanceof ORPCError)
    assert.equal(caught.status, 405)
    assert.equal(isDefinedError(caught), false)
    return true
  })
  const [request] = server.requests
  assert.equal(request.method, 'GET')
  assert.equal(request.body, '')
  const url = new URL(request.url!, server.url)
  assert.equal(url.searchParams.get('data'), '{"json":{"name":"blue"}}')
})

test('pinned Zod length counts Unicode code points and number schemas do not impose wire limits', () => {
  const oneUnit = z.string().max(1)
  assert.equal(oneUnit.safeParse('é').success, true)
  assert.equal(oneUnit.safeParse('😀').success, true)
  assert.equal(z.string().min(2).safeParse('😀').success, false)
  assert.equal(oneUnit.safeParse('e\u0301').success, false)
  assert.equal(z.number().safeParse(9007199254740992).success, true)
  assert.equal(z.int().safeParse(9007199254740992).success, false)
})

function inferredTypes(client: ContractRouterClient<typeof contract>) {
  // @ts-expect-error procedure input name is a string
  void client.widgets.create({ name: 42 })
  // @ts-expect-error unknown input properties are not contract members
  void client.widgets.create({ name: 'blue', extra: true })
  // @ts-expect-error a JSON-null output cannot be treated as a widget
  const widget: Promise<{ id: string }> = client.probe.nullOutput({})
  void widget
}
void inferredTypes
