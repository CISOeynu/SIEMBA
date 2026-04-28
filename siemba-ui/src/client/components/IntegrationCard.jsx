import { useState } from 'react'
import { api } from '../utils/api.js'

export default function IntegrationCard({ type, label, icon, config, enabled, lastTestResult, onSave, onToggle }) {
  const [testing,  setTesting]  = useState(false)
  const [testRes,  setTestRes]  = useState(lastTestResult)
  const [expanded, setExpanded] = useState(false)
  const [form,     setForm]     = useState(config || {})
  const [saving,   setSaving]   = useState(false)

  const test = async () => {
    setTesting(true)
    try {
      const res = await api.post(`/integrations/${type}/test`, form)
      setTestRes(res)
    } catch (e) {
      setTestRes({ success: false, message: e.message })
    } finally { setTesting(false) }
  }

  const save = async () => {
    setSaving(true)
    try {
      await api.put(`/integrations/${type}`, { ...form, enabled })
      onSave?.(type, form)
    } catch (e) { alert(e.message) }
    finally { setSaving(false) }
  }

  const statusColor = testRes?.success ? 'var(--green)' : testRes ? 'var(--red)' : enabled ? 'var(--amber)' : 'var(--text3)'
  const statusText  = testRes?.success ? 'CONNECTED' : testRes ? 'ERROR' : enabled ? 'ENABLED' : 'DISABLED'

  return (
    <div style={{ background: 'var(--panel)', border: `1px solid ${expanded ? 'var(--cyan)' : 'var(--border)'}`,
      borderRadius: 6, overflow: 'hidden', transition: 'border-color .2s' }}>

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 16px', cursor: 'pointer' }}
           onClick={() => setExpanded(e => !e)}>
        <span style={{ fontSize: 20 }}>{icon}</span>
        <div style={{ flex: 1 }}>
          <div style={{ fontWeight: 700, fontSize: 13, color: 'var(--text)' }}>{label}</div>
          <div style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--text2)', marginTop: 2 }}>{type}</div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ width: 7, height: 7, borderRadius: '50%', background: statusColor, display: 'inline-block',
            boxShadow: testRes?.success ? `0 0 5px ${statusColor}` : 'none' }} />
          <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: statusColor }}>{statusText}</span>
          <button onClick={e => { e.stopPropagation(); onToggle?.(type, !enabled) }}
            style={{ background: enabled ? 'rgba(16,185,129,.1)' : 'rgba(255,255,255,.05)',
              border: `1px solid ${enabled ? 'var(--green)' : 'var(--border2)'}`,
              color: enabled ? 'var(--green)' : 'var(--text2)', borderRadius: 3,
              padding: '2px 8px', fontSize: 10, fontFamily: 'var(--mono)' }}>
            {enabled ? 'ON' : 'OFF'}
          </button>
          <span style={{ color: 'var(--text2)', fontSize: 14 }}>{expanded ? '▲' : '▼'}</span>
        </div>
      </div>

      {/* Expanded config form */}
      {expanded && (
        <div style={{ padding: '0 16px 16px', borderTop: '1px solid var(--border)' }}>
          <ConfigForm type={type} form={form} onChange={setForm} />

          {testRes && (
            <div style={{ marginTop: 10, padding: '8px 10px', borderRadius: 4, fontFamily: 'var(--mono)', fontSize: 11,
              background: testRes.success ? 'rgba(16,185,129,.1)' : 'rgba(239,68,68,.1)',
              color: testRes.success ? 'var(--green)' : 'var(--red)',
              border: `1px solid ${testRes.success ? 'var(--green)' : 'var(--red)'}40`
            }}>
              {testRes.success ? '✓' : '✗'} {testRes.message}
            </div>
          )}

          <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
            <button onClick={save} disabled={saving} className="btn-primary" style={{ flex: 1 }}>
              {saving ? 'Saving...' : 'Save Config'}
            </button>
            <button onClick={test} disabled={testing} style={{
              background: 'transparent', border: '1px solid var(--border2)',
              color: 'var(--text2)', borderRadius: 4, padding: '6px 14px', fontSize: 13
            }}>
              {testing ? 'Testing...' : 'Test Connection'}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

function ConfigForm({ type, form, onChange }) {
  const set = (key, val) => onChange(f => ({ ...f, [key]: val }))
  const F = ({ label, k, placeholder, secret, help }) => (
    <div style={{ marginTop: 10 }}>
      <label style={{ display: 'block', fontSize: 10, color: 'var(--text2)', marginBottom: 4, letterSpacing: 1, textTransform: 'uppercase' }}>{label}</label>
      <input type={secret ? 'password' : 'text'} value={form[k] || ''}
        onChange={e => set(k, e.target.value)} placeholder={placeholder}
        style={{ width: '100%' }} />
      {help && <div style={{ fontSize: 10, color: 'var(--text3)', marginTop: 3 }}>{help}</div>}
    </div>
  )

  if (type === 'syslog') return (
    <>
      <F label="Listen Host" k="host" placeholder="0.0.0.0" />
      <F label="UDP Port"    k="udpPort" placeholder="5514" />
      <F label="TCP Port"    k="tcpPort" placeholder="5514" />
      <F label="Description" k="description" placeholder="e.g. Firewall logs" />
    </>
  )
  if (type === 'm365') return (
    <>
      <F label="Tenant ID"     k="tenantId"     placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" />
      <F label="Client ID"     k="clientId"     placeholder="Azure App Registration Client ID" />
      <F label="Client Secret" k="clientSecret" placeholder="App Registration Client Secret" secret />
      <F label="Poll Interval (seconds)" k="pollInterval" placeholder="300" help="How often to fetch new audit logs" />
    </>
  )
  if (type === 'google') return (
    <>
      <F label="Workspace Domain"      k="domain"         placeholder="yourcompany.com" />
      <F label="Service Account JSON"  k="serviceAccountJson" placeholder='{"type":"service_account",...}' secret />
      <F label="Poll Interval (seconds)" k="pollInterval" placeholder="300" />
    </>
  )
  if (type === 'jira') return (
    <>
      <F label="Jira URL"     k="url"        placeholder="https://yourcompany.atlassian.net" />
      <F label="Email"        k="email"      placeholder="security@yourcompany.com" />
      <F label="API Token"    k="apiToken"   placeholder="Jira API token" secret />
      <F label="Project Key"  k="projectKey" placeholder="SEC" />
      <F label="Issue Type"   k="issueType"  placeholder="Task" />
    </>
  )
  if (type === 'teams') return (
    <>
      <F label="Webhook URL"         k="webhookUrl"     placeholder="https://yourcompany.webhook.office.com/..." secret />
      <F label="Min Severity"        k="minSeverity"    placeholder="high" help="Minimum severity to notify: critical, high, medium, low" />
    </>
  )
  if (type === 'slack') return (
    <>
      <F label="Webhook URL"         k="webhookUrl"      placeholder="https://hooks.slack.com/services/..." secret />
      <F label="Default Channel"     k="channel"         placeholder="#security-alerts" />
      <F label="Critical Channel"    k="criticalChannel" placeholder="#security-critical" />
      <F label="Min Severity"        k="minSeverity"     placeholder="high" />
    </>
  )
  if (type === 'custom-api') return (
    <>
      <F label="Name"        k="name"    placeholder="My Tool Name" />
      <F label="Base URL"    k="baseUrl" placeholder="https://api.example.com" />
      <F label="API Token"   k="token"   placeholder="Bearer token or API key" secret />
      <F label="Notes"       k="notes"   placeholder="What this token is used for" />
    </>
  )
  return <div style={{ color: 'var(--text2)', fontSize: 12, marginTop: 10 }}>No config form for type: {type}</div>
}
