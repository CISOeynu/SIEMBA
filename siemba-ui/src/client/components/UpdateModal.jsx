import { useState, useEffect } from 'react'
import { api } from '../utils/api.js'

export default function UpdateModal({ onClose }) {
  const [versions, setVersions] = useState(null)
  const [lines,    setLines]    = useState([])
  const [running,  setRunning]  = useState(false)
  const [done,     setDone]     = useState(false)

  useEffect(() => {
    api.get('/updates/versions').then(setVersions).catch(() => {})
  }, [])

  const runUpdate = () => {
    setRunning(true)
    setLines([])
    api.stream('/updates/run', {}, (msg) => {
      setLines(l => [...l, msg])
    }, () => {
      setRunning(false)
      setDone(true)
      api.get('/updates/versions').then(setVersions).catch(() => {})
    })
  }

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,.75)',
      display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000 }}>
      <div style={{ background: 'var(--navy2)', border: '1px solid var(--cyan)', borderRadius: 8,
        width: 640, maxHeight: '85vh', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>

        {/* Header */}
        <div style={{ display: 'flex', alignItems: 'center', padding: '14px 20px',
          borderBottom: '1px solid var(--border)' }}>
          <span style={{ fontFamily: 'var(--display)', fontWeight: 700, fontSize: 15, color: 'var(--cyan)', letterSpacing: 2 }}>
            ⟳ COMPONENT UPDATES
          </span>
          <div style={{ flex: 1 }} />
          <button onClick={onClose} style={{ background: 'transparent', border: 'none', color: 'var(--text2)', fontSize: 18 }}>✕</button>
        </div>

        {/* Current versions */}
        <div style={{ padding: '14px 20px', borderBottom: '1px solid var(--border)' }}>
          <div style={{ fontSize: 10, letterSpacing: 1.5, color: 'var(--text2)', marginBottom: 10, fontWeight: 600 }}>
            INSTALLED VERSIONS
          </div>
          {versions ? (
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 6 }}>
              {Object.entries(versions).map(([k, v]) => (
                <div key={k} style={{ display: 'flex', justifyContent: 'space-between', padding: '5px 10px',
                  background: 'var(--panel)', borderRadius: 4, border: '1px solid var(--border)' }}>
                  <span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--text2)', textTransform: 'capitalize' }}>{k}</span>
                  <span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--cyan)' }}>{v}</span>
                </div>
              ))}
            </div>
          ) : (
            <div style={{ display: 'flex', gap: 8, color: 'var(--text2)', fontFamily: 'var(--mono)', fontSize: 12 }}>
              <span className="spinner" /> Checking versions...
            </div>
          )}
        </div>

        {/* Output */}
        <div style={{ flex: 1, overflowY: 'auto', background: '#020a14', padding: '10px 14px',
          fontFamily: 'var(--mono)', fontSize: 11, lineHeight: 1.7, minHeight: 120 }}>
          {!lines.length && !running && (
            <div style={{ color: 'var(--text3)' }}>Click "Run Update" to check and update all components.</div>
          )}
          {lines.map((l, i) => (
            <div key={i} style={{ color: l.type === 'result' ? 'var(--green)' : l.type === 'error' ? 'var(--red)' : 'var(--text)' }}>
              {typeof l.data === 'object' ? JSON.stringify(l.data, null, 2) : l.data}
            </div>
          ))}
          {done && <div style={{ color: 'var(--green)', marginTop: 8 }}>✓ Update process complete.</div>}
        </div>

        {/* Actions */}
        <div style={{ display: 'flex', gap: 10, padding: '14px 20px', borderTop: '1px solid var(--border)' }}>
          <button onClick={runUpdate} disabled={running} className="btn-primary" style={{ flex: 1 }}>
            {running ? <><span className="spinner" style={{ marginRight: 8 }} /> Updating...</> : '⟳ Run Update'}
          </button>
          <button onClick={onClose} style={{ background: 'transparent', border: '1px solid var(--border2)',
            color: 'var(--text2)', borderRadius: 4, padding: '6px 18px' }}>
            Close
          </button>
        </div>
      </div>
    </div>
  )
}
