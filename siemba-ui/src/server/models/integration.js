import { randomUUID } from 'crypto'

// In-memory integration config store
const integrations = new Map()

export const IntegrationModel = {
  upsert(type, config) {
    const existing = integrations.get(type)
    const record = {
      id: existing?.id || randomUUID(),
      type,
      config,
      enabled: config.enabled !== false,
      lastTest: null,
      lastTestResult: null,
      updatedAt: new Date().toISOString()
    }
    integrations.set(type, record)
    return record
  },

  get(type) { return integrations.get(type) || null },

  list() { return [...integrations.values()].map(i => ({ ...i, config: maskSecrets(i.config) })) },

  delete(type) { return integrations.delete(type) },

  setTestResult(type, success, message) {
    const i = integrations.get(type)
    if (!i) return
    i.lastTest = new Date().toISOString()
    i.lastTestResult = { success, message }
  },

  enable(type, enabled) {
    const i = integrations.get(type)
    if (i) { i.enabled = enabled; i.updatedAt = new Date().toISOString() }
  }
}

// Mask sensitive fields in responses
function maskSecrets(config) {
  const MASKED_FIELDS = ['clientSecret', 'apiToken', 'webhookUrl', 'password', 'privateKey']
  const out = { ...config }
  for (const f of MASKED_FIELDS) {
    if (out[f]) out[f] = '••••••••'
  }
  return out
}
