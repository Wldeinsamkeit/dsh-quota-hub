window.__ModuleLoader__.load({
  id: '@local/quota-hub',
  factory(require) {
    const React = require('react')
    const h = React.createElement
    const { useEffect, useMemo, useRef, useState } = React

    const NS = 'quota-hub'
    const DICTS = {
      zh: {
        title: '额度中心',
        subtitle: '各 AI 提供商实时额度',
        refresh: '刷新',
        refreshing: '刷新中…',
        updated: '更新于',
        noData: '暂无数据。点「刷新」，或检查 QuotaBar 配置。',
        resetAt: '重置',
        resetDone: '已重置',
        remaining: '剩余',
        unlimited: '∞ 无限制',
      },
      en: {
        title: 'Quota Hub',
        subtitle: 'Live quotas across AI providers',
        refresh: 'Refresh',
        refreshing: 'Refreshing…',
        updated: 'Updated',
        noData: 'No data. Click Refresh, or check the QuotaBar config.',
        resetAt: 'Resets',
        resetDone: 'Reset',
        remaining: 'Remaining',
        unlimited: '∞ Unlimited',
      },
    }
    function fallback(key) { return DICTS.zh[key] || DICTS.en[key] || key }

    function useTranslate(locale) {
      const [rev, setRev] = useState(0)
      useEffect(function () {
        if (!locale || typeof locale.subscribe !== 'function') return undefined
        return locale.subscribe(function () { setRev(function (v) { return v + 1 }) })
      }, [locale])
      return useMemo(function () {
        void rev
        if (locale && typeof locale.bind === 'function') return locale.bind(NS)
        return fallback
      }, [locale, rev])
    }

    function brandBlue() { return 'rgb(77, 107, 254)' }
    function barColor(ratio) {
      if (ratio > 0.95) return 'var(--dsw-alias-state-error-primary)'
      if (ratio > 0.8) return 'var(--dsw-alias-state-warn-primary)'
      return brandBlue()
    }
    function ratioOf(m) {
      if (m.unlimited === true) return null
      if (typeof m.remainingPercent === 'number') return Math.min(1, Math.max(0, (100 - m.remainingPercent) / 100))
      if (typeof m.used === 'number' && typeof m.limit === 'number' && m.limit > 0) return Math.min(1, Math.max(0, m.used / m.limit))
      return null
    }
    function rightText(m) {
      if (m.unlimited === true) return '∞'
      if (typeof m.remainingPercent === 'number') return '剩余 ' + Math.round(m.remainingPercent) + '%'
      if (typeof m.value === 'string' && m.value) return m.value
      const u = Math.round(m.used || 0)
      const l = Math.round(m.limit || 0)
      const unit = m.unit ? ' ' + m.unit : ''
      return l > 0 ? u + ' / ' + l + unit : u + unit
    }

    function fmtClock(ms) {
      if (!ms) return ''
      const d = new Date(ms)
      const p = (n) => String(n).padStart(2, '0')
      return p(d.getMonth() + 1) + '/' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes())
    }
    function fmtUpdated(ms) {
      if (!ms) return '—'
      const d = new Date(ms)
      const p = (n) => String(n).padStart(2, '0')
      return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds())
    }

    const STYLES = [
      '.qh-root{position:relative;display:flex;flex-direction:column;height:100%;min-height:0;background:var(--dsw-alias-bg-base);color:var(--dsw-alias-label-primary);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;}',
      '.qh-bar{flex:none;border-bottom:1px solid var(--dsw-alias-border-l1);}',
      '.qh-bar-inner{max-width:784px;margin:0 auto;padding:11px 28px;display:flex;align-items:center;justify-content:space-between;gap:16px;box-sizing:border-box;}',
      '.qh-bar-title{display:flex;align-items:center;gap:10px;min-width:0;}',
      '.qh-mark{width:26px;height:26px;border-radius:9px;flex:none;display:inline-flex;align-items:center;justify-content:center;background:var(--dsw-alias-bg-layer-2);color:var(--dsw-alias-brand-primary);}',
      '.qh-bar-copy{display:flex;flex-direction:column;min-width:0;}',
      '.qh-bar-name{font-size:13px;font-weight:600;line-height:1.25;}',
      '.qh-bar-sub{font-size:11px;margin-top:2px;color:var(--dsw-alias-label-secondary);font-variant-numeric:tabular-nums;white-space:nowrap;}',
      '.qh-refresh{width:30px;height:30px;flex:none;border-radius:9px;border:1px solid var(--dsw-alias-border-l1);background:transparent;color:var(--dsw-alias-label-secondary);display:inline-flex;align-items:center;justify-content:center;cursor:pointer;}',
      '.qh-refresh:hover:not(:disabled){background:var(--dsw-alias-bg-layer-2);color:var(--dsw-alias-label-primary);}',
      '.qh-refresh:disabled{opacity:.6;cursor:default;}',
      '.qh-refresh:focus-visible{outline:2px solid var(--dsw-alias-brand-primary);outline-offset:2px;}',
      '.qh-scroll{flex:1;min-height:0;overflow-y:auto;overscroll-behavior:contain;}',
      '.qh-body{max-width:784px;margin:0 auto;padding:26px 28px 90px;box-sizing:border-box;display:flex;flex-direction:column;gap:14px;}',
      '.qh-card{padding:14px 16px;border:1px solid var(--dsw-alias-border-l1);border-radius:12px;background:var(--dsw-alias-bg-layer-1);}',
      '.qh-card-head{display:flex;align-items:center;gap:8px;margin-bottom:10px;}',
      '.qh-dot{width:7px;height:7px;border-radius:50%;flex:none;}',
      '.qh-name{font-size:13px;font-weight:650;line-height:1.4;}',
      '.qh-err{font-size:11px;line-height:1.6;color:var(--dsw-alias-label-secondary);}',
      '.qh-metric{display:flex;flex-direction:column;gap:5px;padding:6px 0;}',
      '.qh-metric-row{display:flex;align-items:baseline;gap:8px;}',
      '.qh-metric-label{font-size:12px;color:var(--dsw-alias-label-secondary);}',
      '.qh-metric-value{margin-left:auto;font-size:11px;font-weight:500;font-variant-numeric:tabular-nums;}',
      '.qh-reset{font-size:10px;color:var(--dsw-alias-label-secondary);opacity:.85;}',
      '.qh-bar-track{height:8px;border-radius:999px;background:var(--dsw-alias-bg-layer-2);overflow:hidden;}',
      '.qh-bar-fill{height:100%;border-radius:999px;transition:width .4s ease;}',
      '.qh-empty{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;min-height:60vh;text-align:center;color:var(--dsw-alias-label-secondary);}',
      '.qh-empty-title{font-size:14px;font-weight:600;color:var(--dsw-alias-label-primary);}',
      '@media (max-width:640px){.qh-bar-inner{padding:10px 16px;}.qh-body{padding:20px 16px 80px;}}',
    ].join('')

    function MetricRow(props) {
      const m = props.metric
      const ratio = ratioOf(m)
      return h('div', { className: 'qh-metric' },
        h('div', { className: 'qh-metric-row' },
          h('span', { className: 'qh-metric-label' }, m.label || ''),
          h('span', { className: 'qh-metric-value', style: ratio != null ? { color: barColor(ratio) } : null }, rightText(m)),
        ),
        ratio != null
          ? h('div', { className: 'qh-bar-track', role: 'progressbar', 'aria-valuenow': Math.round(ratio * 100), 'aria-valuemin': 0, 'aria-valuemax': 100 },
            h('div', { className: 'qh-bar-fill', style: { width: Math.round(ratio * 100) + '%', background: barColor(ratio) } }))
          : null,
        m.resetsAt ? h('div', { className: 'qh-reset' }, t('resetAt') + ' ' + fmtClock(m.resetsAt)) : null,
      )
      function t(k) { return props.t ? props.t(k) : k }
    }

    function ProviderCard(props) {
      const p = props.provider
      return h('div', { className: 'qh-card' },
        h('div', { className: 'qh-card-head' },
          h('span', { className: 'qh-dot', style: { background: p.ok ? 'var(--dsw-alias-state-success-primary)' : 'var(--dsw-alias-state-error-primary)' } }),
          h('span', { className: 'qh-name' }, p.label || p.id),
        ),
        p.error && !(p.metrics || []).length
          ? h('div', { className: 'qh-err' }, p.error)
          : null,
        (p.metrics || []).map(function (m, i) {
          return h(MetricRow, { metric: m, key: (m.label || '') + i, t: props.t })
        }),
      )
    }

    function QuotaHubPanel(props) {
      const t = props.t
      const [state, setState] = useState(null)
      const [busy, setBusy] = useState(false)
      const timerRef = useRef(null)

      const load = function () {
        fetch('quota-hub/api/state', { cache: 'no-store' })
          .then(function (r) { return r.json() })
          .then(function (d) { if (d && (d.ok === true || d.error)) setState(d) })
          .catch(function () {})
      }

      const refreshNow = function () {
        if (busy) return
        setBusy(true)
        fetch('quota-hub/api/refresh', { method: 'POST' })
          .catch(function () {})
          .finally(function () {
            let tries = 0
            const poll = setInterval(function () {
              tries += 1
              load()
              if (tries >= 3) { clearInterval(poll); setBusy(false) }
            }, 2500)
          })
      }

      useEffect(function () { load() }, [])
      useEffect(function () {
        timerRef.current = setInterval(load, 10000)
        return function () { clearInterval(timerRef.current) }
      }, [])

      const providers = state && Array.isArray(state.providers) ? state.providers : []
      const hasData = providers.length > 0

      let content = null
      if (hasData) {
        content = h('div', { className: 'qh-body' },
          providers.map(function (p) { return h(ProviderCard, { provider: p, key: p.id, t: t }) }),
        )
      } else if (state && state.error === 'missing') {
        content = h('div', { className: 'qh-empty' },
          h('div', { className: 'qh-empty-title' }, 'QuotaBar 数据不存在'),
          h('div', null, '先安装并启动菜单栏 QuotaBar，或点「刷新」生成。'),
        )
      } else {
        content = h('div', { className: 'qh-empty' },
          h('div', { className: 'qh-empty-title' }, busy ? '正在采集…' : '暂无数据'),
          h('div', null, '点右上角「刷新」试试。'),
        )
      }

      return h('section', { className: 'qh-root', 'aria-label': t('title') },
        h('style', null, STYLES),
        h('header', { className: 'qh-bar' },
          h('div', { className: 'qh-bar-inner' },
            h('div', { className: 'qh-bar-title' },
              h('span', { className: 'qh-mark' },
                h('svg', { viewBox: '0 0 24 24', width: 15, height: 15, fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', 'aria-hidden': true, style: { display: 'block' } },
                  h('path', { d: 'M4 19h16' }),
                  h('path', { d: 'M6 19V9m6 10V5m6 14v-8' }),
                ),
              ),
              h('span', { className: 'qh-bar-copy' },
                h('span', { className: 'qh-bar-name' }, t('title')),
                h('span', { className: 'qh-bar-sub' }, t('subtitle') + ' · ' + t('updated') + ' ' + fmtUpdated(state && state.updatedAt)),
              ),
            ),
            h('button', {
              type: 'button',
              className: 'qh-refresh',
              onClick: refreshNow,
              disabled: busy,
              title: t('refresh'),
              'aria-label': t('refresh'),
            },
              busy
                ? h('span', { className: 'li-spin', style: { width: 12, height: 12, borderRadius: '50%', border: '1.5px solid var(--dsw-alias-border-l2)', borderTopColor: 'var(--dsw-alias-brand-primary)', display: 'block', animation: 'qhspin .8s linear infinite' } })
                : h('svg', { viewBox: '0 0 24 24', width: 15, height: 15, fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', 'aria-hidden': true, style: { display: 'block' } },
                  h('path', { d: 'M19.5 11.2a7.5 7.5 0 1 1-2.2-5.1' }),
                  h('path', { d: 'M19.7 3.6v4.6h-4.6' }),
                ),
            ),
          ),
        ),
        h('div', { className: 'qh-scroll' }, content),
        h('style', null, '@keyframes qhspin{to{transform:rotate(360deg)}}'),
      )
    }

    return {
      inject: ['slots'],
      apply(ctx) {
        const locale = ctx.get('locale')
        if (locale && typeof locale.register === 'function') {
          Object.keys(DICTS).forEach(function (id) {
            ctx.effect(function () { return locale.register(NS, id, DICTS[id]) }, 'quota-hub: ' + id)
          })
        }
        const translate = locale && typeof locale.bind === 'function' ? locale.bind(NS) : fallback
        const Panel = function (props) {
          return h(QuotaHubPanel, Object.assign({}, props, { t: translate }))
        }
        ctx.slots.inject('sidebar.panellist', function () {
          return ctx.slots.register({
            name: 'sidebar.panellist', id: 'quota-hub', order: 25,
            label: function () { return translate('title') },
          }, function (props) {
            const size = props && typeof props.size === 'number' ? props.size : 20
            return h('svg', {
              viewBox: '0 0 24 24', width: size, height: size, fill: 'none', stroke: 'currentColor',
              strokeWidth: 1.7, strokeLinecap: 'round', 'aria-hidden': true, style: { display: 'block' },
            },
              h('path', { d: 'M4 19h16' }),
              h('path', { d: 'M6 19V9m6 10V5m6 14v-8' }),
            )
          })
        })
        ctx.slots.inject('main', function () {
          return ctx.slots.register({ name: 'main', key: 'quota-hub' }, Panel)
        })
      },
    }
  },
})
