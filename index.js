import { readFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { spawn } from 'node:child_process'
import { homedir } from 'node:os'
import path from 'node:path'

const statePath = path.join(homedir(), 'Library', 'Application Support', 'QuotaBar', 'state.json')
const collectorPath = path.join(homedir(), 'Library', 'Application Support', 'QuotaBar', 'collect.mjs')

export const inject = ['webServer']

export function apply(ctx) {
  ctx.effect(() => {
    const disposers = [
      ctx.webServer.register({
        kind: 'exact',
        path: '/quota-hub/api/state',
        handler: (req, res) => handleState(req, res),
      }),
      ctx.webServer.register({
        kind: 'exact',
        path: '/quota-hub/api/refresh',
        handler: (req, res) => handleRefresh(req, res),
      }),
    ]
    return () => { for (const d of disposers) d() }
  }, 'quota-hub: routes')
}

function sameOrigin(req) {
  const site = req.headers['sec-fetch-site']
  if (typeof site === 'string' && site !== 'same-origin' && site !== 'none') return false
  const origin = req.headers.origin
  if (typeof origin !== 'string') return true
  try { return new URL(origin).host === req.headers.host } catch { return false }
}

async function handleState(req, res) {
  if (!sameOrigin(req)) { res.statusCode = 403; res.end(); return }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.statusCode = 405
    res.setHeader('allow', 'GET, HEAD')
    res.end()
    return
  }
  try {
    const text = await readFile(statePath, 'utf8')
    const body = Buffer.from(text)
    res.statusCode = 200
    res.setHeader('content-type', 'application/json; charset=utf-8')
    res.setHeader('cache-control', 'no-store')
    res.setHeader('content-length', body.length)
    res.end(req.method === 'HEAD' ? undefined : body)
  } catch (error) {
    const body = JSON.stringify({ ok: false, error: error && error.code === 'ENOENT' ? 'missing' : 'unreadable' })
    res.statusCode = 200
    res.setHeader('content-type', 'application/json; charset=utf-8')
    res.setHeader('cache-control', 'no-store')
    res.end(body)
  }
}

async function handleRefresh(req, res) {
  if (!sameOrigin(req)) { res.statusCode = 403; res.end(); return }
  if (req.method !== 'POST') {
    res.statusCode = 405
    res.setHeader('allow', 'POST')
    res.end()
    return
  }
  const node = ['/opt/homebrew/bin/node', '/usr/local/bin/node', '/usr/bin/node']
    .find((c) => existsSync(c))
  if (!node) {
    res.statusCode = 500
    res.end(JSON.stringify({ ok: false, error: 'node 不可用' }))
    return
  }
  const child = spawn(node, [collectorPath], { detached: true, stdio: 'ignore' })
  child.unref()
  res.statusCode = 200
  res.setHeader('content-type', 'application/json; charset=utf-8')
  res.end(JSON.stringify({ ok: true }))
}
