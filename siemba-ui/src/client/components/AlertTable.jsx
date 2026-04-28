import { severityColor, severityBg } from '../utils/severity.js'
import { api } from '../utils/api.js'
import { useState } from 'react'

export default function AlertTable({ alerts, loading, onRefresh }) {
  const [escalating, setEscalating] = useState(null)

  const escalate = async (alert) => {
    setEscalating(alert.id)
    try {
      const res = await api.post(`/alerts/${alert.id}/escalate`, {
        alertData: alert,
        severity: alert.siemba_severity
      })
      const results = Object.entries(res).filter(([, v]) => v?.ok).map(([k]) => k).join(', ')
      alert(`Escalated to: ${results || 'none configured'}`)
    } catch (e) {
      alert('Escalation failed: ' + e.message)
    } finally {
      setEscalating(null)
    }
  }

  if (loading) return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: 200, gap: 10, color: 'var(--text2)' }}>
      <span className="spinner" /> Loading alerts...
    </div>
  )

  if (!alerts.length) return (
    <div style={{ textAlign: 'center', padding: 40, color: 'var(--text2)', fontFamily: 'var(--mono)', fontSize: 13 }}>
      No alerts found for current filters.
    </div>
  )

  return (
    <div style={{ overflowX: 'auto' }}>
      <table style={{ width: '100%', borderCollapse: 'collapse', fontFamily: 'var(--mono)', fontSize: 12 }}>
        <thead>
          <tr style={{ borderBottom: '1px solid var(--border)' }}>
            {['Severity','Time','Source','Message','Host/IP','Actions'].map(h => (
              <th key={h} style={{ padding: '8px 10px', textAlign: 'left', color: 'var(--text2)',
                fontSize: 10, fontWeight: 600, letterSpacing: 1.2, textTransform: 'uppercase' }}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {alerts.map((alert, i) => (
            <tr key={alert.id || i} style={{
              borderBottom: '1px solid var(--border)',
              background: i % 2 === 0 ? 'transparent' : 'rgba(255,255,255,.01)',
              transition: 'background .1s'
            }}
            onMouseEnter={e => e.currentTarget.style.background = 'rgba(0,212,255,.04)'}
            onMouseLeave={e => e.currentTarget.style.background = i % 2 === 0 ? 'transparent' : 'rgba(255,255,255,.01)'}
            >
              <td style={{ padding: '7px 10px' }}>
                <span style={{
                  display: 'inline-block', padding: '2px 8px', borderRadius: 3, fontSize: 10,
                  fontWeight: 700, letterSpacing: 0.5,
                  background: severityBg(alert.siemba_severity),
                  color: severityColor(alert.siemba_severity),
                  border: `1px solid ${severityColor(alert.siemba_severity)}40`
                }}>
                  {(alert.siemba_severity || 'unknown').toUpperCase()}
                </span>
              </td>
              <td style={{ padding: '7px 10px', color: 'var(--text2)', whiteSpace: 'nowrap' }}>
                {alert['@timestamp'] ? new Date(alert['@timestamp']).toLocaleString() : '—'}
              </td>
              <td style={{ padding: '7px 10px' }}>
                <span style={{ background: 'rgba(0,212,255,.08)', color: 'var(--cyan)', padding: '2px 7px',
                  borderRadius: 3, fontSize: 10 }}>
                  {alert.source_integration || 'unknown'}
                </span>
              </td>
              <td style={{ padding: '7px 10px', maxWidth: 360, color: 'var(--text)' }}>
                <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
                     title={alert.message || alert.syslog_message || JSON.stringify(alert)}>
                  {alert.message || alert.syslog_message || alert.Operation || '—'}
                </div>
                {alert.ti_matched === 'true' && (
                  <span style={{ fontSize: 9, color: 'var(--red)', marginTop: 2, display: 'block' }}>
                    ⚠ THREAT INTEL MATCH
                  </span>
                )}
              </td>
              <td style={{ padding: '7px 10px', color: 'var(--text2)' }}>
                {alert.host || alert.ClientIP || alert['source.ip'] || '—'}
              </td>
              <td style={{ padding: '7px 10px' }}>
                <button
                  onClick={() => escalate(alert)}
                  disabled={escalating === alert.id}
                  style={{
                    background: 'rgba(239,68,68,.1)', border: '1px solid var(--red)',
                    color: 'var(--red)', borderRadius: 3, padding: '3px 8px',
                    fontSize: 10, cursor: 'pointer', fontFamily: 'var(--mono)'
                  }}
                >
                  {escalating === alert.id ? '...' : 'ESCALATE'}
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
