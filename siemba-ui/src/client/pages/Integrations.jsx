import { useState, useEffect } from 'react'
import { api } from '../utils/api.js'
import IntegrationCard from '../components/IntegrationCard.jsx'

const INTEGRATION_DEFS = [
  { type: 'syslog',     label: 'Syslog',             icon: '📡', desc: 'Receive UDP/TCP syslog from routers, firewalls, servers' },
  { type: 'm365',       label: 'Microsoft 365',       icon: '🔵', desc: 'Audit logs, sign-ins, and security alerts via Graph API' },
  { type: 'azure',      label: 'Azure AD',            icon: '☁️',  desc: 'Sign-in logs, conditional access, risk detections' },
  { type: 'google',     label: 'Google Workspace',    icon: '🟢', desc: 'Admin activity, login events, Drive access via Admin SDK' },
  { type: 'jira',       label: 'Jira',                icon: '🎫', desc: 'Auto-create tickets for alerts and incidents' },
  { type: 'teams',      label: 'Microsoft Teams',     icon: '💬', desc: 'Send critical notifications to Teams channels' },
  { type: 'slack',      label: 'Slack',               icon: '⚡', desc: 'Route alerts to Slack channels by severity' },
  { type: 'custom-api', label: 'Custom API / Tokens', icon: '🔑', desc: 'Store API keys and tokens for future integrations' },
]

export default function Integrations() {
  const [configs, setConfigs] = useState({})
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    api.get('/integrations').then(list => {
      const map = {}
      list.forEach(i => { map[i.type] = i })
      setConfigs(map)
    }).catch(() => {}).finally(() => setLoading(false))
  }, [])

  const handleSave   = (type, cfg) => setConfigs(c => ({ ...c, [type]: { ...c[type], config: cfg } }))
  const handleToggle = async (type, enabled) => {
    await api.patch(`/integrations/${type}/toggle`, { enabled })
    setConfigs(c => ({ ...c, [type]: { ...c[type], enabled } }))
  }

  if (loading) return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: 40, color: 'var(--text2)' }}>
      <span className="spinner" /> Loading integrations...
    </div>
  )

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
        <div>
          <div style={{ fontWeight: 700, fontSize: 16, color: 'var(--text)' }}>Integrations</div>
          <div style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--text2)', marginTop: 2 }}>
            Configure log sources, alerting, and ticketing. Click any card to expand and configure.
          </div>
        </div>
        <div style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--text2)' }}>
          {Object.values(configs).filter(c => c.enabled).length} / {INTEGRATION_DEFS.length} enabled
        </div>
      </div>

      {INTEGRATION_DEFS.map(def => (
        <IntegrationCard
          key={def.type}
          type={def.type}
          label={def.label}
          icon={def.icon}
          config={configs[def.type]?.config}
          enabled={configs[def.type]?.enabled ?? false}
          lastTestResult={configs[def.type]?.lastTestResult}
          onSave={handleSave}
          onToggle={handleToggle}
        />
      ))}
    </div>
  )
}
