import { Router } from 'express'
import { Client } from '@elastic/elasticsearch'
import fetch from 'node-fetch'
import { IntegrationModel } from '../models/integration.js'
import { logger } from '../server.js'

const router = Router()
const es = new Client({ node: process.env.ES_HOST || 'http://127.0.0.1:9200' })

// List / search alerts from Elasticsearch
router.get('/', async (req, res) => {
  const { severity, source, from = 0, size = 50, q = '*', hours = 24 } = req.query
  const must = [{ range: { '@timestamp': { gte: `now-${hours}h`, lte: 'now' } } }]
  if (severity) must.push({ term: { siemba_severity: severity } })
  if (source)   must.push({ term: { source_integration: source } })
  if (q !== '*') must.push({ query_string: { query: q } })

  try {
    const result = await es.search({
      index: 'siemba-*',
      from: parseInt(from), size: parseInt(size),
      sort: [{ '@timestamp': { order: 'desc' } }],
      query: { bool: { must } }
    })
    res.json({
      total: result.hits.total.value,
      hits:  result.hits.hits.map(h => ({ id: h._id, index: h._index, ...h._source }))
    })
  } catch (e) {
    logger.error('ES query failed', e.message)
    res.status(500).json({ error: e.message })
  }
})

// Severity aggregation
router.get('/stats', async (_req, res) => {
  try {
    const result = await es.search({
      index: 'siemba-*', size: 0,
      query: { range: { '@timestamp': { gte: 'now-24h' } } },
      aggs: {
        by_severity:    { terms: { field: 'siemba_severity', size: 10 } },
        by_integration: { terms: { field: 'source_integration', size: 10 } },
        by_hour:        { date_histogram: { field: '@timestamp', calendar_interval: 'hour', min_doc_count: 0 } },
        ti_hits:        { filter: { term: { ti_matched: 'true' } } }
      }
    })
    res.json(result.aggregations)
  } catch (e) { res.status(500).json({ error: e.message }) }
})

// Correlation — cross-platform events in a time window
router.get('/correlated', async (req, res) => {
  const { minutes = 60 } = req.query
  try {
    const result = await es.search({
      index: 'siemba-*', size: 200,
      query: { bool: {
        must: [
          { range: { '@timestamp': { gte: `now-${minutes}m` } } },
          { terms: { siemba_severity: ['critical', 'high'] } }
        ]
      }},
      sort: [{ '@timestamp': { order: 'desc' } }]
    })
    // Group by source IP if available
    const events = result.hits.hits.map(h => ({ id: h._id, ...h._source }))
    const byIp = {}
    for (const ev of events) {
      const ip = ev.ClientIP || ev.host || ev['source.ip'] || 'unknown'
      if (!byIp[ip]) byIp[ip] = []
      byIp[ip].push(ev)
    }
    const correlated = Object.entries(byIp)
      .filter(([, evs]) => evs.length > 1)
      .map(([ip, evs]) => ({ ip, count: evs.length, sources: [...new Set(evs.map(e => e.source_integration))], events: evs.slice(0, 5) }))
      .sort((a, b) => b.count - a.count)
    res.json({ correlated, all: events })
  } catch (e) { res.status(500).json({ error: e.message }) }
})

// Escalate alert — create Jira ticket + notify Teams/Slack
router.post('/:id/escalate', async (req, res) => {
  const { alertData, severity } = req.body
  const results = { jira: null, teams: null, slack: null }

  // Jira
  const jira = IntegrationModel.get('jira')
  if (jira?.enabled && jira.config.url) {
    try {
      const priority = { critical:'Highest', high:'High', medium:'Medium', low:'Low' }[severity] || 'Medium'
      const r = await fetch(`${jira.config.url}/rest/api/3/issue`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Basic ${Buffer.from(`${jira.config.email}:${jira.config.apiToken}`).toString('base64')}`
        },
        body: JSON.stringify({
          fields: {
            project:   { key: jira.config.projectKey || 'SEC' },
            issuetype: { name: jira.config.issueType || 'Task' },
            summary:   `[SIEMBA] ${severity?.toUpperCase()} - ${alertData?.message?.slice(0,100) || 'Security Alert'}`,
            description: { type: 'doc', version: 1, content: [{ type: 'paragraph', content: [{ type: 'text', text: JSON.stringify(alertData, null, 2) }] }] },
            priority:  { name: priority }
          }
        })
      })
      const d = await r.json()
      results.jira = r.ok ? { ok: true, key: d.key } : { ok: false, error: d.errorMessages?.join(', ') }
    } catch (e) { results.jira = { ok: false, error: e.message } }
  }

  // Teams
  const teams = IntegrationModel.get('teams')
  if (teams?.enabled && teams.config.webhookUrl) {
    try {
      const color = severity === 'critical' ? 'attention' : 'warning'
      const r = await fetch(teams.config.webhookUrl, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          type: 'message', attachments: [{ contentType: 'application/vnd.microsoft.card.adaptive', content: {
            type: 'AdaptiveCard', version: '1.4',
            body: [
              { type: 'TextBlock', text: `🚨 SIEMBA ${severity?.toUpperCase()} Alert`, weight: 'Bolder', color },
              { type: 'TextBlock', text: alertData?.message || 'Security event detected', wrap: true }
            ]
          }}]
        })
      })
      results.teams = { ok: r.ok }
    } catch (e) { results.teams = { ok: false, error: e.message } }
  }

  // Slack
  const slack = IntegrationModel.get('slack')
  if (slack?.enabled && slack.config.webhookUrl) {
    try {
      const emoji = { critical: '🔴', high: '🟠', medium: '🟡', low: '🟢' }[severity] || '⚪'
      const r = await fetch(slack.config.webhookUrl, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          channel: severity === 'critical' ? (slack.config.criticalChannel || slack.config.channel) : slack.config.channel,
          text: `${emoji} *SIEMBA ${severity?.toUpperCase()}*: ${alertData?.message || 'Security event'}`
        })
      })
      results.slack = { ok: r.ok }
    } catch (e) { results.slack = { ok: false, error: e.message } }
  }

  res.json(results)
})

export default router
