import { useRef, useEffect, useState } from 'react'

export default function ToolTerminal({ lines = [], running = false, onClear, title = 'OUTPUT' }) {
  const bottomRef = useRef(null)
  const [wrap, setWrap] = useState(false)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [lines])

  const lineColor = (type) => ({
    stdout:  'var(--text)',
    stderr:  'var(--amber)',
    error:   'var(--red)',
    info:    'var(--cyan)',
    exit:    'var(--text2)',
    result:  'var(--green)'
  }[type] || 'var(--text)')

  const download = () => {
    const text = lines.map(l => l.data).join('\n')
    const blob = new Blob([text], { type: 'text/plain' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `siemba-output-${Date.now()}.txt`
    a.click()
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 300 }}>
      {/* Terminal header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 12px',
        background: 'var(--navy2)', borderBottom: '1px solid var(--border)', flexShrink: 0 }}>
        <div style={{ display: 'flex', gap: 5 }}>
          <span style={{ width: 10, height: 10, borderRadius: '50%', background: '#ff5f56' }} />
          <span style={{ width: 10, height: 10, borderRadius: '50%', background: '#ffbd2e' }} />
          <span style={{ width: 10, height: 10, borderRadius: '50%', background: '#27c93f' }} />
        </div>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--text2)', flex: 1, marginLeft: 4 }}>
          SIEMBA — {title}
        </span>
        {running && <span className="spinner" />}
        <div style={{ display: 'flex', gap: 6 }}>
          <button onClick={() => setWrap(w => !w)} style={{
            background: 'transparent', border: '1px solid var(--border2)', color: 'var(--text2)',
            borderRadius: 3, padding: '2px 7px', fontSize: 10, fontFamily: 'var(--mono)' }}>
            {wrap ? 'NOWRAP' : 'WRAP'}
          </button>
          <button onClick={download} disabled={!lines.length} style={{
            background: 'transparent', border: '1px solid var(--border2)', color: 'var(--text2)',
            borderRadius: 3, padding: '2px 7px', fontSize: 10, fontFamily: 'var(--mono)' }}>
            ↓ SAVE
          </button>
          <button onClick={onClear} disabled={!lines.length} style={{
            background: 'transparent', border: '1px solid var(--border2)', color: 'var(--text2)',
            borderRadius: 3, padding: '2px 7px', fontSize: 10, fontFamily: 'var(--mono)' }}>
            CLEAR
          </button>
        </div>
      </div>

      {/* Output area */}
      <div style={{ flex: 1, overflowY: 'auto', background: '#020a14', padding: '10px 14px',
        fontFamily: 'var(--mono)', fontSize: 12, lineHeight: 1.6 }}>
        {!lines.length && !running && (
          <div style={{ color: 'var(--text3)', marginTop: 10 }}>
            $ <span style={{ animation: 'blink 1s step-end infinite', display: 'inline-block' }}>▋</span>
            <style>{`@keyframes blink{0%,100%{opacity:1}50%{opacity:0}}`}</style>
          </div>
        )}
        {lines.map((line, i) => (
          <div key={i} style={{
            color: lineColor(line.type),
            whiteSpace: wrap ? 'pre-wrap' : 'pre',
            wordBreak: wrap ? 'break-all' : 'normal'
          }}>
            {line.type === 'exit'
              ? `\n[Process exited with code ${line.data?.code ?? line.data}]`
              : typeof line.data === 'object'
                ? JSON.stringify(line.data, null, 2)
                : line.data}
          </div>
        ))}
        <div ref={bottomRef} />
      </div>
    </div>
  )
}
