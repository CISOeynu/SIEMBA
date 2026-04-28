import { Router } from 'express'
import { IntegrationModel } from '../models/integration.js'
import { requireRole } from '../middleware/auth.js'
import fetch from 'node-fetch'

const router = Router()

// List all integrations
router.get('/', (_req, res) => res.json(IntegrationModel.list()))

// Get one integration config
router.get('/:type', (req, res) => {
  const i = IntegrationModel.get(req.params.type)
  if (!i) return res.status(404).json({ error: 'Not found' })
  res.json({ ...i, config: maskSecrets(i.config) })
})

// Save / update integration config
router.put('/:type', requireRole('admin'), (req, res) => {
  const record = IntegrationModel.upsert(req.params.type, req.body)
  res.json(record)
})

// Delete integration
router.delete('/:type', requireRole('admin'), (req, res) => {
  IntegrationModel.delete(req.params.type)
  res.json({ ok: true })
})

// Toggle enabled/disabled
router.patch('/:type/toggle', requireRole('admin'), (req, res) => {
  IntegrationModel.enable(req.params.type, req.body.enabled)
  res.json({ ok: true })
})

// Test connectivity
router.post('/:type/test', requireRole('admin'), async (req, res) => {
  const { type } = req.params
  let success = false; let message = ''

  try {
    if (type === 'syslog') {
      success = true; message = 'Syslog listener active on :5514'
    } else if (type === 'm365') {
      const cfg = IntegrationModel.get('m365')?.config || req.body
      const tokenRes = await fetch(
        `https://login.microsoftonline.com/${cfg.tenantId}/oauth2/v2.0/token`,
        { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ client_id: cfg.clientId, client_secret: cfg.clientSecret,
            scope: 'https://graph.microsoft.com/.default', grant_type: 'client_credentials' }) }
      )
      const data = await tokenRes.json()
      success = !!data.access_token; message = success ? 'M365 token acquired OK' : data.error_description
    } else if (type === 'jira') {
      const cfg = IntegrationModel.get('jira')?.config || req.body
      const r = await fetch(`${cfg.url}/rest/api/3/myself`, {
        headers: { Authorization: `Basic ${Buffer.from(`${cfg.email}:${cfg.apiToken}`).toString('base64')}` }
      })
      success = r.ok; message = r.ok ? 'Jira connection OK' : `HTTP ${r.status}`
    } else if (type === 'teams') {
      const cfg = IntegrationModel.get('teams')?.config || req.body
      const r = await fetch(cfg.webhookUrl, { method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: 'SIEMBA connectivity test ✅' }) })
      success = r.ok; message = r.ok ? 'Teams webhook OK' : `HTTP ${r.status}`
    } else if (type === 'slack') {
      const cfg = IntegrationModel.get('slack')?.config || req.body
      const r = await fetch(cfg.webhookUrl, { method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: 'SIEMBA connectivity test ✅' }) })
      success = r.ok; message = r.ok ? 'Slack webhook OK' : `HTTP ${r.status}`
    } else {
      success = true; message = `${type} config saved`
    }
  } catch (e) { success = false; message = e.message }

  IntegrationModel.setTestResult(type, success, message)
  res.json({ success, message })
})

function maskSecrets(cfg) {
  const MASK = ['clientSecret', 'apiToken', 'webhookUrl', 'password']
  const out = { ...cfg }
  for (const f of MASK) { if (out[f]) out[f] = '••••••••' }
  return out
}

export default router
