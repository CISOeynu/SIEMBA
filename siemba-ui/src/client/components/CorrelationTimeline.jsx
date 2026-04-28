import { severityColor } from '../utils/severity.js'

export default function CorrelationTimeline({ events = [], loading }) {
  if (loading) return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, color: 'var(--text2)', padding: 20, fontFamily: 'var(--mono)', fontSize: 12 }}>
      <span className="spinner" /> Correlating events...
    </div>
  )

  if (!events.length) return (
    <div style={{ color: 'var(--text2)', fontFamily: 'var(--mono)', fontSize: 12, padding: 16 }}>
      No correlated events in the last 60 minutes.
    </div>
  )

  const SOURCE_COLORS = {
    syslog:  '#00d4ff',
    m365:    '#0078d4',
    azure:   '#5c2d91',
    google:  '#34a853',
    default: '#7090a8'
  }

  return (
    <div style={{ overflowX: 'auto' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 500 }}>
        {events.map((ev, i) => {
          const sev   = ev.siemba_severity || 'low'
          const color = severityColor(sev)
          const srcColor = SOURCE_COLORS[ev.source_integration] || SOURCE_COLORS.default
          const time  = ev['@timestamp'] ? new Date(ev['@timestamp']) : null

          return (
            <div key={ev.id || i} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              {/* Time */}
              <div style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--text2)',
                width: 44, flexShrink: 0, textAlign: 'right' }}>
                {time ? `${String(time.getHours()).padStart(2,'0')}:${String(time.getMinutes()).padStart(2,'0')}` : '??:??'}
              </div>

              {/* Dot + line */}
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', flexShrink: 0 }}>
                <div style={{ width: 8, height: 8, borderRadius: '50%', background: color,
                  boxShadow: sev === 'critical' ? `0 0 6px ${color}` : 'none' }} />
                {i < events.length - 1 && (
                  <div style={{ width: 1, height: 14, background: 'var(--border)' }} />
                )}
              </div>

              {/* Event bar */}
              <div style={{ flex: 1, height: 22, borderRadius: 3, display: 'flex', alignItems: 'center',
                padding: '0 10px', gap: 8, fontSize: 10, fontFamily: 'var(--mono)',
                background: `${color}18`, border: `1px solid ${color}30`,
                overflow: 'hidden', whiteSpace: 'nowrap' }}>
                <span style={{ background: srcColor, color: '#fff', padding: '1px 5px',
                  borderRadius: 2, fontSize: 9, flexShrink: 0 }}>
                  {(ev.source_integration || 'unknown').toUpperCase()}
                </span>
                <span style={{ color: 'var(--text)', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {ev.message || ev.syslog_message || ev.Operation || 'Event'}
                </span>
                {ev.ti_matched === 'true' && (
                  <span style={{ color: 'var(--red)', marginLeft: 'auto', flexShrink: 0 }}>⚠ TI HIT</span>
                )}
                {(ev.host || ev.ClientIP) && (
                  <span style={{ color: 'var(--text2)', marginLeft: 'auto', flexShrink: 0 }}>
                    {ev.host || ev.ClientIP}
                  </span>
                )}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
