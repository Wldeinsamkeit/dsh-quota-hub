// QuotaBar collector：读取 config.json，抓取各提供商额度，写出 state.json
// 无第三方依赖（Node 18+ 自带 fetch）
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { homedir } from 'node:os'
import path from 'node:path'

const BASE = path.join(homedir(), 'Library', 'Application Support', 'QuotaBar')
const CONFIG = path.join(BASE, 'config.json')
const STATE = path.join(BASE, 'state.json')

function readDshCredential(refName) {
  try {
    const text = readFileSync(path.join(homedir(), '.dsh', '.credentials.yaml'), 'utf8')
    const m = text.match(new RegExp(refName + '\\s*:\\s*(\\S+)'))
    return m ? m[1] : null
  } catch { return null }
}

function loadConfig() {
  if (!existsSync(CONFIG)) return {}
  try { return JSON.parse(readFileSync(CONFIG, 'utf8')) } catch { return {} }
}

async function jfetchOnce(url, headers = {}, timeoutMs = 15000) {
  const ctrl = new AbortController()
  const t = setTimeout(() => ctrl.abort(), timeoutMs)
  try {
    const r = await fetch(url, { headers, signal: ctrl.signal })
    const text = await r.text()
    try { return { status: r.status, json: JSON.parse(text) } }
    catch { return { status: r.status, text } }
  } finally { clearTimeout(t) }
}

async function jfetch(url, headers = {}, timeoutMs = 15000) {
  const h = { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36', ...headers }
  try {
    return await jfetchOnce(url, h, timeoutMs)
  } catch {
    // 网络抖动自动重试一次
    await new Promise((res) => setTimeout(res, 1500))
    return jfetchOnce(url, h, timeoutMs)
  }
}

// ---- DeepSeek：官方余额接口（按量 prepaid，无 5h/周窗口） ----
async function collectDeepSeek(c) {
  const apiKey = (c && c.apiKey) || readDshCredential('DEEPSEEK_API_KEY')
  if (!apiKey) return { id: 'deepseek', label: 'DeepSeek', ok: false, error: '未找到 DeepSeek API Key（config / DSH 凭据库）', metrics: [] }
  const r = await jfetch('https://api.deepseek.com/user/balance', { Authorization: 'Bearer ' + apiKey })
  if (r.status !== 200 || !r.json) throw new Error('HTTP ' + r.status)
  const bi = (r.json.balance_infos || [])[0]
  const currency = bi && bi.currency ? bi.currency : ''
  return {
    id: 'deepseek', label: 'DeepSeek', ok: true, metrics: [
      { kind: 'balance', label: '余额' + (currency ? '（' + currency + '）' : ''), value: bi ? bi.total_balance : '—' },
    ],
  }
}

// ---- Z.ai / 智谱 GLM Coding Plan：官方配额端点（Coding Plan Key 直查，无需 cookie） ----
async function collectZai(c) {
  const id = 'zai-coding'
  const cfg = c || {}
  const key = cfg.apiKey || readDshCredential('ZAI_CODING_CN_API_KEY')
  if (!key) return { id, label: 'Z.ai · GLM Coding', ok: false, error: '未找到 Coding Plan Key（config / DSH 凭据库）', metrics: [] }
  const base = (cfg.baseUrl || 'https://open.bigmodel.cn').replace(/\/+$/, '')
  try {
    const r = await jfetch(base + '/api/monitor/usage/quota/limit', { Authorization: 'Bearer ' + key })
    if (r.status !== 200 || !r.json || !r.json.data) throw new Error('HTTP ' + r.status)
    const limits = r.json.data.limits || []
    const level = r.json.data.level || ''
    const metrics = limits.map((l) => {
      const is5h = l.unit === 3 || l.number === 5
      return {
        kind: is5h ? 'window5h' : 'weekly',
        label: is5h ? '5 小时额度' : '每周额度',
        used: l.currentValue, limit: l.usage, unit: 'credits',
        resetsAt: l.nextResetTime || 0,
      }
    })
    return { id, label: 'Z.ai · GLM Coding' + (level ? '（' + level + '）' : ''), ok: metrics.length > 0, metrics }
  } catch (error) {
    const manual = cfg.manual || {}
    if ((manual.fiveHour && (manual.fiveHour.used || manual.fiveHour.limit)) ||
        (manual.weekly && (manual.weekly.used || manual.weekly.limit))) {
      const metrics = []
      if (manual.fiveHour) metrics.push({ kind: 'window5h', label: '5 小时额度', used: manual.fiveHour.used, limit: manual.fiveHour.limit, unit: manual.fiveHour.unit || '', resetsAt: manual.fiveHour.resetsAt || 0 })
      if (manual.weekly) metrics.push({ kind: 'weekly', label: '每周额度', used: manual.weekly.used, limit: manual.weekly.limit, unit: manual.weekly.unit || '', resetsAt: manual.weekly.resetsAt || 0 })
      return { id, label, ok: true, metrics }
    }
    return { id, label, ok: false, error: error && error.message ? error.message : 'quota 查询失败', metrics: [] }
  }
}

// ---- MiniMax：mmx quota show（已登录）或官方 /v1/token_plan/remains ----
function mmxQuotaJson() {
  for (const bin of ['/opt/homebrew/bin/mmx', '/usr/local/bin/mmx']) {
    if (!existsSync(bin)) continue
    try {
      const out = execFileSync(bin, ['quota', 'show', '--output', 'json'], { encoding: 'utf8', timeout: 20000 })
      return JSON.parse(out)
    } catch {}
  }
  return null
}

function mapMiniMaxRemains(json) {
  const remains = (json && json.model_remains) || []
  const metrics = []
  for (const m of remains) {
    const suffix = remains.length > 1 && m.model_name && m.model_name !== 'general' ? ' · ' + m.model_name : ''
    if (m.end_time) {
      metrics.push({
        kind: 'window5h', label: '5 小时额度' + suffix,
        used: m.current_interval_usage_count || 0, limit: m.current_interval_total_count || 0,
        remainingPercent: typeof m.current_interval_remaining_percent === 'number' ? m.current_interval_remaining_percent : null,
        resetsAt: m.end_time,
      })
    }
    if (m.current_weekly_status === 3) {
      metrics.push({ kind: 'weekly', label: '每周额度' + suffix, value: '∞ 无限制', resetsAt: m.weekly_end_time || 0 })
    } else if (m.weekly_end_time) {
      metrics.push({
        kind: 'weekly', label: '每周额度' + suffix,
        used: m.current_weekly_usage_count || 0, limit: m.current_weekly_total_count || 0,
        remainingPercent: typeof m.current_weekly_remaining_percent === 'number' ? m.current_weekly_remaining_percent : null,
        resetsAt: m.weekly_end_time,
      })
    }
  }
  return metrics
}

async function collectMiniMax(c) {
  const id = 'minimax', label = 'MiniMax'
  let json = null
  if (!c || c.useMmx !== false) {
    try { json = mmxQuotaJson() } catch {}
  }
  const mmKey = (c && c.apiKey) || readDshCredential('MINIMAX_API_KEY')
  if (!json && mmKey) {
    const origins = [c.baseUrl, 'https://www.minimax.cn', 'https://www.minimax.io', 'https://www.minimaxi.com'].filter(Boolean)
    for (const origin of origins) {
      try {
        const r = await jfetch(origin.replace(/\/+$/, '') + '/v1/token_plan/remains', { Authorization: 'Bearer ' + mmKey })
        if (r.status === 200 && r.json && r.json.model_remains) { json = r.json; break }
      } catch {}
    }
  }
  if (!json) return { id, label, ok: false, error: 'mmx 未登录且无 MiniMax API Key', metrics: [] }
  const metrics = mapMiniMaxRemains(json)
  return { id, label, ok: metrics.length > 0, metrics }
}

// ---- Gemini（AI Pro）：消费级会员无公开额度 API，支持手工档 ----
async function collectGemini(c) {
  const id = 'gemini', label = 'Gemini · AI Pro'
  if (!c) return { id, label, ok: false, error: '未配置（config.json → gemini）', metrics: [] }
  if (c.manual && c.manual.daily) {
    return { id, label, ok: true, metrics: [
      { kind: 'daily', label: 'CLI 请求（今日）', used: c.manual.daily.used, limit: c.manual.daily.limit, unit: 'req', resetsAt: 0 },
    ] }
  }
  return { id, label, ok: false, error: '未配置（官方无额度 API，先用手工档）', metrics: [] }
}

// ---- OpenAI Codex（ChatGPT OAuth，5h + 7d 窗口） ----
async function collectCodex(c) {
  const id = 'codex', label = 'Codex · ChatGPT'
  const home = homedir()
  const candidates = [
    process.env.CODEX_HOME ? path.join(process.env.CODEX_HOME, 'auth.json') : null,
    path.join(home, '.codex', 'auth.json'),
    path.join(home, '.config', 'codex', 'auth.json'),
  ].filter(Boolean)
  const authFile = candidates.find((f) => existsSync(f))
  if (!authFile) return { id, label, ok: false, error: '未找到 ~/.codex/auth.json', metrics: [] }

  let tok
  try { tok = JSON.parse(readFileSync(authFile, 'utf8')) } catch (e) { return { id, label, ok: false, error: 'auth.json 解析失败', metrics: [] } }
  const access = tok && tok.tokens && tok.tokens.access_token
  if (!access) return { id, label, ok: false, error: 'auth.json 无 access_token（可能用的 API key 模式）', metrics: [] }

  const headers = { Authorization: 'Bearer ' + access, Accept: 'application/json' }
  if (tok.tokens.account_id) headers['ChatGPT-Account-Id'] = tok.tokens.account_id

  const r = await jfetch('https://chatgpt.com/backend-api/wham/usage', headers, 15000)
  if (r.status === 401 || r.status === 403) {
    return { id, label, ok: false, error: 'Codex 登录态过期：终端跑一次 codex 即可刷新', metrics: [] }
  }
  if (r.status !== 200 || !r.json) throw new Error('HTTP ' + r.status)

  const j = r.json
  const metrics = []
  const windows = (j.rate_limit && [j.rate_limit.primary_window, j.rate_limit.secondary_window]) || []
  for (const w of windows.filter(Boolean)) {
    const secs = w.limit_window_seconds || 0
    const is5h = secs === 18000
    const isWeek = secs === 604800
    metrics.push({
      kind: is5h ? 'window5h' : (isWeek ? 'weekly' : 'window' + secs),
      label: (is5h ? '5 小时窗口' : (isWeek ? '每周窗口' : '窗口(' + secs + 's)')),
      remainingPercent: typeof w.used_percent === 'number' ? 100 - w.used_percent : null,
      resetsAt: w.reset_at ? w.reset_at * 1000 : 0,
    })
  }
  if (j.credits && j.credits.has_credits) {
    metrics.push({ kind: 'balance', label: 'Codex Credits', value: String(j.credits.balance) })
  }
  return { id, label: label + (j.plan_type ? '（' + j.plan_type + '）' : ''), ok: metrics.length > 0, metrics }
}

// ---- 通用手工条目：cfg.manual = [{ id,label,metrics:[...] }] ----
function collectManualList(c) {
  const list = (c && Array.isArray(c.manual)) ? c.manual : []
  return list.map((m) => ({
    id: m.id || ('manual-' + (m.label || '')),
    label: m.label || m.id || '手工条目',
    ok: true,
    metrics: (m.metrics || []).map((x) => ({
      kind: x.kind || 'custom', label: x.label || '', used: x.used, limit: x.limit,
      value: x.value, unit: x.unit || '', resetsAt: x.resetsAt || 0,
    })),
  }))
}

const cfg = loadConfig()
const providers = []
const errors = []

for (const [name, fn] of [
  ['deepseek', collectDeepSeek],
  ['zai', collectZai],
  ['minimax', collectMiniMax],
  ['codex', collectCodex],
  ['gemini', collectGemini],
]) {
  try { providers.push(await fn(cfg[name])) }
  catch (e) {
    const msg = e && e.message ? e.message : String(e)
    errors.push(name + ': ' + msg)
    providers.push({ id: name, label: name, ok: false, error: msg, metrics: [] })
  }
}
for (const p of collectManualList(cfg)) providers.push(p)

mkdirSync(BASE, { recursive: true })
writeFileSync(STATE, JSON.stringify({ updatedAt: Date.now(), providers, errors }, null, 2))
console.log('state written:', STATE, '| providers:', providers.length, errors.length ? '| errors: ' + errors.join('; ') : '')
