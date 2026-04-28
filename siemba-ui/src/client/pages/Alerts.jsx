import { useState } from 'react'
import { useAlerts } from '../hooks/useAlerts.js'
import AlertTable from '../components/AlertTable.jsx'
import { SEVERITIES } from '../utils/severity.js'

const SOURCES = ['syslog','m365','azure','google','ti-hits']
const HOURS   = [1, 6, 12, 24, 48, 168]

export default function Alerts() {
  const [severity, setSeverity] = useState('')
  const [source,   setSource]   = useState('')
  const [hours,    setHours]    = useState(24)
  const [q,        setQ]        = useState('')
  const [inputQ,   setInputQ]   = useState('')

  const { alerts, total, loading, refresh } = useAlerts({ severity, source, hours, q, autoRefresh: 60 })

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>

      {/* Filters */}
      <div className="card" style={{ display: 'flex', gap: 10, alignItems: 'flex-end', flexWrap: 'wrap' }}>
        <div>
          <label style={{ display: 'block', fontSize: 10, color: 'var(--text2)', marginBottom: 4, letterSpacing: 1 }}>SEVERITY</label>
          <select value={severity} onChange={e => setSeverity(e.target.value)} style={{ width: 130 }}>
            <option value="">All Severities</option>
            {SEVERITIES.map(s => <option key={s} value={s}>{s.charAt(0).toUpperCase()+s.slice(1)}</option>)}
          </select>
        </div>
        <div>
          <label style={{ display: 'block', fontSize: 10, color: 'var(--text2)', marginBottom: 4, letterSpacing: 1 }}>SOURCE</label>
          <select value={source} onChange={e => setSource(e.target.value)} style={{ width: 130 }}>
            <option value="">All Sources</option>
            {SOURCES.map(s => <option key={s} value={s}>{s}</option>)}
          </select>
        </div>
        <div>
          <label style={{ display: 'block', fontSize: 10, color: 'var(--text2)', marginBottom: 4, letterSpacing: 1 }}>TIME RANGE</label>
          <select value={hours} onChange={e => setHours(Number(e.target.value))} style={{ width: 110 }}>
            {HOURS.map(h => <option key={h} value={h}>{h < 24 ? `${h}h` : `${h/24}d`}</option>)}
          </select>
        </div>
        <div style={{ flex: 1, minWidth: 200 }}>
          <label style={{ display: 'block', fontSize: 10, color: 'var(--text2)', marginBottom: 4, letterSpacing: 1 }}>SEARCH</label>
          <div style={{ display: 'flex', gap: 6 }}>
            <input value={inputQ} onChange={e => setInputQ(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && setQ(inputQ)}
              placeholder='e.g. host:192.168.1.1 OR message:"failed login"'
              style={{ flex: 1 }} />
            <button onClick={() => setQ(inputQ)} className="btn-primary">Search</button>
            {q && <button onClick={() => { setQ(''); setInputQ('') }}
              style={{ background: 'transparent', border: '1px solid var(--border2)', color: 'var(--text2)', borderRadius: 4, padding: '6px 10px' }}>✕</button>}
          </div>
        </div>
        <button onClick={refresh} style={{ background: 'transparent', border: '1px solid var(--border2)', color: 'var(--text2)', borderRadius: 4, padding: '6px 12px' }}>
          ↻ Refresh
        </button>
      </div>

      {/* Results */}
      <div className="card" style={{ padding: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', padding: '12px 16px', borderBottom: '1px solid var(--border)' }}>
          <span className="section-title" style={{ margin: 0 }}>ALERTS</span>
          <span style={{ marginLeft: 10, fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--text2)' }}>
            {loading ? 'loading...' : `${total.toLocaleString()} results`}
          </span>
        </div>
        <AlertTable alerts={alerts} loading={loading} onRefresh={refresh} />
      </div>
    </div>
  )
}
