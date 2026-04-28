import { useState } from 'react'
import { api } from '../utils/api.js'
import ToolTerminal from '../components/ToolTerminal.jsx'

const TOOLS = [
  { id: 'nuclei',     label: 'Nuclei',        icon: '🔍', desc: 'Vulnerability scanner with community templates' },
  { id: 'sniper',     label: 'Sn1per',        icon: '🕵️',  desc: 'Automated recon and penetration testing' },
  { id: 'metasploit', label: 'Metasploit',    icon: '⚔️',  desc: 'Scanner modules only — no auto-exploit without confirmation' },
  { id: 'dmarc',      label: 'DMARC Checker', icon: '📧', desc: 'Email security audit: SPF, DKIM, DMARC, MX, blacklists' },
]

function NucleiForm({ onRun, running }) {
  const [target, setTarget]    = useState('')
  const [templates, setTpl]   = useState('cves,exposures,misconfiguration')
  const [severity, setSev]    = useState('')
  const [rateLimit, setRate]  = useState('100')
  const submit = (e) => { e.preventDefault(); onRun({ target, templates, severity, rateLimit }) }
  return (
    <form onSubmit={submit} style={{ display:'flex', flexDirection:'column', gap:10 }}>
      <div><label className="field-label">TARGET (IP, domain, URL, CIDR)</label>
        <input value={target} onChange={e=>setTarget(e.target.value)} placeholder="192.168.1.0/24" required style={{width:'100%'}} /></div>
      <div><label className="field-label">TEMPLATES</label>
        <input value={templates} onChange={e=>setTpl(e.target.value)} placeholder="cves,exposures,misconfiguration" style={{width:'100%'}} /></div>
      <div style={{display:'flex', gap:10}}>
        <div style={{flex:1}}><label className="field-label">MIN SEVERITY</label>
          <select value={severity} onChange={e=>setSev(e.target.value)} style={{width:'100%'}}>
            <option value="">All</option>
            <option value="critical">Critical</option>
            <option value="high">High</option>
            <option value="medium">Medium</option>
          </select></div>
        <div style={{flex:1}}><label className="field-label">RATE LIMIT (req/s)</label>
          <input value={rateLimit} onChange={e=>setRate(e.target.value)} placeholder="100" style={{width:'100%'}} /></div>
      </div>
      <button type="submit" disabled={running} className="btn-primary">▶ Run Nuclei Scan</button>
    </form>
  )
}

function SniperForm({ onRun, running }) {
  const [target, setTarget] = useState('')
  const [mode, setMode]     = useState('normal')
  const submit = (e) => { e.preventDefault(); onRun({ target, mode }) }
  return (
    <form onSubmit={submit} style={{ display:'flex', flexDirection:'column', gap:10 }}>
      <div><label className="field-label">TARGET</label>
        <input value={target} onChange={e=>setTarget(e.target.value)} placeholder="domain.com or 192.168.1.1" required style={{width:'100%'}} /></div>
      <div><label className="field-label">SCAN MODE</label>
        <select value={mode} onChange={e=>setMode(e.target.value)} style={{width:'100%'}}>
          <option value="normal">Normal — full recon</option>
          <option value="stealth">Stealth — quiet scan</option>
          <option value="flyover">Flyover — fast overview</option>
          <option value="discover">Discover — host discovery</option>
        </select></div>
      <button type="submit" disabled={running} className="btn-primary">▶ Run Sn1per</button>
    </form>
  )
}

function MetasploitForm({ onRun, running }) {
  const [target,  setTarget]  = useState('')
  const [module,  setModule]  = useState('')
  const [options, setOptions] = useState('')
  const [confirmed, setConf]  = useState(false)
  const submit = (e) => {
    e.preventDefault()
    if (!confirmed) { setConf(true); return }
    const opts = {}
    options.split('\n').forEach(line => {
      const [k, ...v] = line.split(' ')
      if (k && v.length) opts[k.toUpperCase()] = v.join(' ')
    })
    onRun({ target, module, options: opts })
    setConf(false)
  }
  return (
    <form onSubmit={submit} style={{ display:'flex', flexDirection:'column', gap:10 }}>
      <div style={{ padding:'10px', background:'rgba(245,158,11,.08)', border:'1px solid var(--amber)', borderRadius:4,
        fontSize:11, color:'var(--amber)', fontFamily:'var(--mono)' }}>
        ⚠ Only auxiliary/scanner/ and auxiliary/gather/ modules are permitted.
      </div>
      <div><label className="field-label">TARGET (RHOSTS)</label>
        <input value={target} onChange={e=>setTarget(e.target.value)} placeholder="192.168.1.1" required style={{width:'100%'}} /></div>
      <div><label className="field-label">MODULE PATH</label>
        <input value={module} onChange={e=>setModule(e.target.value)} placeholder="auxiliary/scanner/smb/smb_version" required style={{width:'100%'}} /></div>
      <div><label className="field-label">OPTIONS (one per line: KEY value)</label>
        <textarea value={options} onChange={e=>setOptions(e.target.value)} placeholder="THREADS 10" rows={3} style={{width:'100%'}} /></div>
      {confirmed && (
        <div style={{ padding:'10px', background:'rgba(239,68,68,.1)', border:'1px solid var(--red)', borderRadius:4,
          fontSize:11, color:'var(--red)', fontFamily:'var(--mono)' }}>
          CONFIRM: You are about to run {module} on {target}. Click Run again to confirm.
        </div>
      )}
      <button type="submit" disabled={running} style={{
        background: confirmed ? 'rgba(239,68,68,.15)' : undefined,
        border: confirmed ? '1px solid var(--red)' : undefined,
        color: confirmed ? 'var(--red)' : undefined
      }} className={!confirmed ? 'btn-primary' : undefined}>
        {running ? '▶ Running...' : confirmed ? '⚠ Confirm & Run' : '▶ Run Module'}
      </button>
    </form>
  )
}

function DmarcForm({ onRun, running }) {
  const [target, setTarget] = useState('')
  const submit = (e) => { e.preventDefault(); onRun({ target }) }
  return (
    <form onSubmit={submit} style={{ display:'flex', flexDirection:'column', gap:10 }}>
      <div><label className="field-label">DOMAIN, IP, SUBNET, OR URL</label>
        <input value={target} onChange={e=>setTarget(e.target.value)} placeholder="example.com or 93.184.216.34" required style={{width:'100%'}} /></div>
      <p style={{ fontSize:11, color:'var(--text2)', fontFamily:'var(--mono)', margin:0 }}>
        Checks: SPF · DKIM · DMARC policy · MX records · Reverse DNS · Common blacklists
      </p>
      <button type="submit" disabled={running} className="btn-primary">▶ Run DMARC Check</button>
    </form>
  )
}

function DmarcResults({ result }) {
  if (!result) return null
  const statusIcon = s => ({ pass:'✓', warn:'⚠', fail:'✗' }[s] || '?')
  const statusColor = s => ({ pass:'var(--green)', warn:'var(--amber)', fail:'var(--red)' }[s] || 'var(--text2)')
  return (
    <div style={{ display:'flex', flexDirection:'column', gap:8, marginTop:12 }}>
      <div style={{ display:'flex', alignItems:'center', gap:10 }}>
        <span style={{ fontFamily:'var(--mono)', fontSize:14, fontWeight:700, color:'var(--cyan)' }}>{result.target}</span>
        <span style={{ fontFamily:'var(--mono)', fontSize:12, color:'var(--text2)' }}>Score: {result.summary?.score}%</span>
      </div>
      {result.checks.map((c,i) => (
        <div key={i} style={{ display:'flex', gap:10, padding:'8px 12px', background:'var(--navy)',
          borderRadius:4, border:`1px solid ${statusColor(c.status)}30` }}>
          <span style={{ color: statusColor(c.status), width:14, textAlign:'center', flexShrink:0 }}>{statusIcon(c.status)}</span>
          <div style={{ flex:1 }}>
            <div style={{ fontFamily:'var(--mono)', fontSize:12, color:'var(--text)', fontWeight:600 }}>{c.name}</div>
            <div style={{ fontFamily:'var(--mono)', fontSize:11, color:'var(--text2)', marginTop:2, wordBreak:'break-all' }}>{c.value}</div>
            {c.note && <div style={{ fontFamily:'var(--mono)', fontSize:10, color:'var(--amber)', marginTop:2 }}>{c.note}</div>}
          </div>
        </div>
      ))}
    </div>
  )
}

export default function SecurityTools() {
  const [activeTool, setActiveTool] = useState('nuclei')
  const [lines,      setLines]      = useState([])
  const [running,    setRunning]    = useState(false)
  const [dmarcRes,   setDmarcRes]   = useState(null)

  const run = async (body) => {
    setLines([])
    setDmarcRes(null)
    setRunning(true)

    if (activeTool === 'dmarc') {
      try {
        const res = await api.post('/tools/dmarc', body)
        setDmarcRes(res)
        setLines([{ type: 'result', data: `DMARC check complete — score: ${res.summary?.score}%` }])
      } catch (e) {
        setLines([{ type: 'error', data: e.message }])
      } finally { setRunning(false) }
      return
    }

    const endpoint = { nuclei: '/tools/nuclei', sniper: '/tools/sniper', metasploit: '/tools/metasploit' }[activeTool]
    api.stream(endpoint, body,
      (msg) => setLines(l => [...l, msg]),
      () => setRunning(false)
    )
  }

  return (
    <div style={{ display:'flex', flexDirection:'column', gap:0, height:'calc(100vh - 120px)' }}>
      {/* Tool tabs */}
      <div style={{ display:'flex', borderBottom:'1px solid var(--border)', flexShrink:0 }}>
        {TOOLS.map(t => (
          <button key={t.id} onClick={() => { setActiveTool(t.id); setLines([]); setDmarcRes(null) }} style={{
            background: activeTool === t.id ? 'rgba(0,212,255,.08)' : 'transparent',
            border:'none', borderBottom: activeTool === t.id ? '2px solid var(--cyan)' : '2px solid transparent',
            color: activeTool === t.id ? 'var(--cyan)' : 'var(--text2)',
            padding:'10px 16px', fontSize:12, fontWeight:600, letterSpacing:0.5, cursor:'pointer',
            display:'flex', alignItems:'center', gap:6
          }}>
            <span>{t.icon}</span>{t.label}
          </button>
        ))}
      </div>

      <style>{`.field-label{display:block;font-size:10px;color:var(--text2);margin-bottom:4px;letter-spacing:1px;font-weight:600;text-transform:uppercase}`}</style>

      {/* Tool description */}
      <div style={{ padding:'10px 0 4px', fontFamily:'var(--mono)', fontSize:11, color:'var(--text2)', flexShrink:0 }}>
        {TOOLS.find(t => t.id === activeTool)?.desc}
      </div>

      {/* Two-column layout: form + terminal */}
      <div style={{ display:'grid', gridTemplateColumns:'300px 1fr', gap:12, flex:1, minHeight:0 }}>
        <div className="card" style={{ overflow:'auto' }}>
          {activeTool === 'nuclei'     && <NucleiForm     onRun={run} running={running} />}
          {activeTool === 'sniper'     && <SniperForm     onRun={run} running={running} />}
          {activeTool === 'metasploit' && <MetasploitForm onRun={run} running={running} />}
          {activeTool === 'dmarc'      && (
            <>
              <DmarcForm onRun={run} running={running} />
              <DmarcResults result={dmarcRes} />
            </>
          )}
        </div>
        <div className="card" style={{ padding:0, overflow:'hidden', display:'flex', flexDirection:'column' }}>
          <ToolTerminal
            lines={lines}
            running={running}
            onClear={() => setLines([])}
            title={TOOLS.find(t=>t.id===activeTool)?.label.toUpperCase()}
          />
        </div>
      </div>
    </div>
  )
}
