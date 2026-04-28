import { useState } from 'react'
import { useAlerts, useCorrelatedAlerts } from '../hooks/useAlerts.js'
import { severityColor } from '../utils/severity.js'
import CorrelationTimeline from '../components/CorrelationTimeline.jsx'
import AlertTable from '../components/AlertTable.jsx'
import UpdateModal from '../components/UpdateModal.jsx'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts'

function StatCard({ label, value, color, sub }) {
  return (
    <div className="card" style={{ textAlign: 'center' }}>
      <div style={{ fontSize: 10, color: 'var(--text2)', letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 8 }}>{label}</div>
      <div style={{ fontSize: 38, fontWeight: 700, fontFamily: 'var(--display)', color: color || 'var(--cyan)', lineHeight: 1 }}>{value}</div>
      {sub && <div style={{ fontSize: 11, color: 'var(--text2)', marginTop: 6, fontFamily: 'var(--mono)' }}>{sub}</div>}
    </div>
  )
}

export default function Dashboard() {
  const { alerts, stats, total, loading, refresh } = useAlerts({ hours: 24, autoRefresh: 30 })
  const { data: corrData, loading: corrLoading } = useCorrelatedAlerts(60)
  const [showUpdate, setShowUpdate] = useState(false)

  const bySev    = stats?.by_severity?.buckets  || []
  const byInteg  = stats?.by_integration?.buckets || []
  const byHour   = stats?.by_hour?.buckets       || []
  const tiHits   = stats?.ti_hits?.doc_count     || 0

  const sevCount = (s) => bySev.find(b => b.key === s)?.doc_count || 0

  const hourData = byHour.slice(-12).map(b => ({
    time: new Date(b.key_as_string || b.key).getHours() + ':00',
    count: b.doc_count
  }))

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>

      {/* Top action bar */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--text2)' }}>
          Security overview · last 24h · {total.toLocaleString()} total events
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button onClick={refresh} className="btn-primary" style={{ fontSize: 12 }}>↻ Refresh</button>
          <button onClick={() => setShowUpdate(true)} style={{
            background: 'rgba(245,158,11,.08)', border: '1px solid var(--amber)',
            color: 'var(--amber)', borderRadius: 4, padding: '6px 14px', fontSize: 12, fontFamily: 'var(--display)'
          }}>⟳ Check Updates</button>
        </div>
      </div>

      {/* Stat cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12 }}>
        <StatCard label="Critical Alerts"   value={sevCount('critical')} color="var(--red)"   sub="last 24h" />
        <StatCard label="High Alerts"       value={sevCount('high')}     color="var(--amber)" sub="last 24h" />
        <StatCard label="Threat Intel Hits" value={tiHits}               color="var(--red)"   sub="matched feeds" />
        <StatCard label="Total Events"      value={total.toLocaleString()} color="var(--cyan)" sub={`${byInteg.length} sources`} />
      </div>

      {/* Event volume chart + integration breakdown */}
      <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 12 }}>
        <div className="card">
          <div className="section-title">Event Volume — Last 12 Hours</div>
          <ResponsiveContainer width="100%" height={120}>
            <BarChart data={hourData} margin={{ top: 0, right: 0, left: -20, bottom: 0 }}>
              <XAxis dataKey="time" tick={{ fill: 'var(--text2)', fontSize: 10, fontFamily: 'var(--mono)' }} />
              <YAxis tick={{ fill: 'var(--text2)', fontSize: 10, fontFamily: 'var(--mono)' }} />
              <Tooltip contentStyle={{ background: 'var(--navy2)', border: '1px solid var(--border)', fontFamily: 'var(--mono)', fontSize: 11 }} />
              <Bar dataKey="count" radius={[2,2,0,0]}>
                {hourData.map((h, i) => (
                  <Cell key={i} fill={h.count > 500 ? 'var(--red)' : h.count > 200 ? 'var(--amber)' : 'var(--cyan)'} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="card">
          <div className="section-title">By Integration</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            {byInteg.length ? byInteg.map(b => (
              <div key={b.key} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--text)', flex: 1 }}>{b.key}</span>
                <div style={{ width: 80, height: 6, background: 'var(--border)', borderRadius: 3, overflow: 'hidden' }}>
                  <div style={{ width: `${Math.min(100, (b.doc_count / Math.max(...byInteg.map(x=>x.doc_count))) * 100)}%`,
                    height: '100%', background: 'var(--cyan)', borderRadius: 3 }} />
                </div>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--text2)', width: 40, textAlign: 'right' }}>
                  {b.doc_count.toLocaleString()}
                </span>
              </div>
            )) : <div style={{ color: 'var(--text2)', fontFamily: 'var(--mono)', fontSize: 12 }}>No data yet</div>}
          </div>
        </div>
      </div>

      {/* Correlation timeline + latest alerts */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
        <div className="card">
          <div className="section-title">Correlated Incidents — Last 60 min</div>
          <CorrelationTimeline events={corrData?.all?.slice(0, 20) || []} loading={corrLoading} />
        </div>
        <div className="card">
          <div className="section-title">Latest Critical &amp; High</div>
          <AlertTable alerts={alerts.filter(a => ['critical','high'].includes(a.siemba_severity)).slice(0,10)}
            loading={loading} onRefresh={refresh} />
        </div>
      </div>

      {showUpdate && <UpdateModal onClose={() => setShowUpdate(false)} />}
    </div>
  )
}
