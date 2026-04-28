import { useState, useEffect } from 'react'
import { api } from '../utils/api.js'

export default function ThreatIntel() {
  const [feeds,    setFeeds]    = useState([])
  const [loading,  setLoading]  = useState(true)
  const [adding,   setAdding]   = useState(false)
  const [urlForm,  setUrlForm]  = useState({ name: '', url: '', type: 'ip', description: '' })
  const [uploading,setUploading]= useState(false)
  const [refreshing,setRefreshing]=useState(false)
  const [lookupVal,setLookupVal]=useState('')
  const [lookupRes,setLookupRes]=useState(null)
  const [activeTab,setActiveTab]=useState('feeds')

  const loadFeeds = () => {
    api.get('/threatintel/feeds').then(setFeeds).catch(()=>{}).finally(()=>setLoading(false))
  }
  useEffect(loadFeeds, [])

  const addUrl = async (e) => {
    e.preventDefault()
    setAdding(true)
    try {
      const feed = await api.post('/threatintel/feeds/url', urlForm)
      setFeeds(f => [...f, feed])
      setUrlForm({ name: '', url: '', type: 'ip', description: '' })
    } catch(e) { alert(e.message) }
    finally { setAdding(false) }
  }

  const uploadFile = async (e) => {
    const file = e.target.files[0]
    if (!file) return
    const name = window.prompt('Feed name:', file.name.replace(/\.[^.]+$/,''))
    if (!name) return
    setUploading(true)
    const fd = new FormData()
    fd.append('file', file)
    fd.append('name', name)
    fd.append('type', file.name.endsWith('.json') ? 'url' : 'ip')
    try {
      const feed = await api.upload('/threatintel/feeds/upload', fd)
      setFeeds(f => [...f, feed])
    } catch(e) { alert(e.message) }
    finally { setUploading(false); e.target.value = '' }
  }

  const removeFeed = async (id) => {
    if (!confirm('Remove this feed?')) return
    await api.delete(`/threatintel/feeds/${id}`)
    setFeeds(f => f.filter(x => x.id !== id))
  }

  const refreshAll = async () => {
    setRefreshing(true)
    try {
      const res = await api.post('/threatintel/feeds/refresh', {})
      alert(`Refreshed ${res.filter(r=>r.ok).length}/${res.length} feeds`)
      loadFeeds()
    } catch(e) { alert(e.message) }
    finally { setRefreshing(false) }
  }

  const lookup = async (e) => {
    e.preventDefault()
    if (!lookupVal) return
    const res = await api.post('/threatintel/lookup', { value: lookupVal })
    setLookupRes(res)
  }

  const TYPE_LABELS = { ip: 'IP Address', domain: 'Domain', url: 'URL', hash: 'File Hash' }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* Tabs */}
      <div style={{ display: 'flex', gap: 0, borderBottom: '1px solid var(--border)' }}>
        {['feeds','add-url','upload','lookup'].map(t => (
          <button key={t} onClick={() => setActiveTab(t)} style={{
            background: activeTab === t ? 'rgba(0,212,255,.08)' : 'transparent',
            border: 'none', borderBottom: activeTab === t ? '2px solid var(--cyan)' : '2px solid transparent',
            color: activeTab === t ? 'var(--cyan)' : 'var(--text2)',
            padding: '8px 16px', fontSize: 12, fontWeight: 600, letterSpacing: 0.5
          }}>{t.replace('-',' ').toUpperCase()}</button>
        ))}
        <div style={{ flex: 1 }} />
        <button onClick={refreshAll} disabled={refreshing} className="btn-primary" style={{ margin: '4px 0', fontSize: 11 }}>
          {refreshing ? 'Refreshing...' : '↻ Refresh All URL Feeds'}
        </button>
      </div>

      {/* Feed list */}
      {activeTab === 'feeds' && (
        <div className="card" style={{ padding: 0 }}>
          <div style={{ padding: '12px 16px', borderBottom: '1px solid var(--border)', display: 'flex', alignItems: 'center' }}>
            <span className="section-title" style={{ margin: 0 }}>THREAT INTELLIGENCE FEEDS</span>
            <span style={{ marginLeft: 10, fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--text2)' }}>
              {feeds.reduce((s,f)=>s+(f.lineCount||0),0).toLocaleString()} total indicators across {feeds.length} feeds
            </span>
          </div>
          {loading ? (
            <div style={{ padding: 30, textAlign: 'center', color: 'var(--text2)' }}><span className="spinner" /></div>
          ) : !feeds.length ? (
            <div style={{ padding: 30, textAlign: 'center', color: 'var(--text2)', fontFamily: 'var(--mono)', fontSize: 12 }}>
              No feeds configured yet. Add a URL feed or upload a file.
            </div>
          ) : (
            <table style={{ width: '100%', borderCollapse: 'collapse', fontFamily: 'var(--mono)', fontSize: 12 }}>
              <thead><tr style={{ borderBottom: '1px solid var(--border)' }}>
                {['Name','Type','Source','Indicators','Last Updated',''].map(h =>
                  <th key={h} style={{ padding: '8px 14px', textAlign: 'left', fontSize: 10, color: 'var(--text2)',
                    fontWeight: 600, letterSpacing: 1.2, textTransform: 'uppercase' }}>{h}</th>)}
              </tr></thead>
              <tbody>
                {feeds.map(f => (
                  <tr key={f.id} style={{ borderBottom: '1px solid var(--border)' }}>
                    <td style={{ padding: '9px 14px', color: 'var(--text)' }}>{f.name}</td>
                    <td style={{ padding: '9px 14px' }}>
                      <span style={{ background: 'rgba(0,212,255,.08)', color: 'var(--cyan)', padding: '2px 7px', borderRadius: 3, fontSize: 10 }}>
                        {TYPE_LABELS[f.type] || f.type}
                      </span>
                    </td>
                    <td style={{ padding: '9px 14px', color: 'var(--text2)' }}>{f.source === 'url' ? '🌐 URL' : '📁 Upload'}</td>
                    <td style={{ padding: '9px 14px', color: 'var(--green)' }}>{(f.lineCount||0).toLocaleString()}</td>
                    <td style={{ padding: '9px 14px', color: 'var(--text2)' }}>
                      {f.lastUpdated ? new Date(f.lastUpdated).toLocaleString() : '—'}
                    </td>
                    <td style={{ padding: '9px 14px' }}>
                      <button onClick={() => removeFeed(f.id)} className="btn-danger" style={{ fontSize: 10, padding: '2px 8px' }}>
                        Remove
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* Add URL feed */}
      {activeTab === 'add-url' && (
        <div className="card" style={{ maxWidth: 560 }}>
          <div className="section-title">Add URL Feed</div>
          <form onSubmit={addUrl} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div><label style={{ display:'block', fontSize:10, color:'var(--text2)', marginBottom:4 }}>FEED NAME</label>
              <input value={urlForm.name} onChange={e=>setUrlForm(f=>({...f,name:e.target.value}))} placeholder="e.g. Emerging Threats IPs" required style={{width:'100%'}} /></div>
            <div><label style={{ display:'block', fontSize:10, color:'var(--text2)', marginBottom:4 }}>URL</label>
              <input value={urlForm.url} onChange={e=>setUrlForm(f=>({...f,url:e.target.value}))} placeholder="https://..." required style={{width:'100%'}} /></div>
            <div><label style={{ display:'block', fontSize:10, color:'var(--text2)', marginBottom:4 }}>TYPE</label>
              <select value={urlForm.type} onChange={e=>setUrlForm(f=>({...f,type:e.target.value}))} style={{width:'100%'}}>
                {Object.entries(TYPE_LABELS).map(([k,v])=><option key={k} value={k}>{v}</option>)}
              </select></div>
            <div><label style={{ display:'block', fontSize:10, color:'var(--text2)', marginBottom:4 }}>DESCRIPTION (optional)</label>
              <input value={urlForm.description} onChange={e=>setUrlForm(f=>({...f,description:e.target.value}))} placeholder="Where this feed comes from" style={{width:'100%'}} /></div>
            <button type="submit" disabled={adding} className="btn-primary">{adding ? 'Adding...' : 'Add Feed'}</button>
          </form>
        </div>
      )}

      {/* Upload file */}
      {activeTab === 'upload' && (
        <div className="card" style={{ maxWidth: 560 }}>
          <div className="section-title">Upload Feed File</div>
          <p style={{ color: 'var(--text2)', fontFamily: 'var(--mono)', fontSize: 12, marginBottom: 16, lineHeight: 1.7 }}>
            Upload a plain text file (one IP/domain per line) or a JSON file.<br/>
            Supported JSON formats: plain array, STIX2, or <code style={{color:'var(--cyan)'}}>{'{"indicators":[...]}'}</code>
          </p>
          <label style={{ display:'block', padding:'30px', border:'2px dashed var(--border2)', borderRadius:6,
            textAlign:'center', cursor:'pointer', color:'var(--text2)', fontFamily:'var(--mono)', fontSize:12 }}>
            {uploading ? 'Uploading...' : '📁 Click to select .txt or .json file'}
            <input type="file" accept=".txt,.json,.csv" onChange={uploadFile} style={{display:'none'}} disabled={uploading} />
          </label>
        </div>
      )}

      {/* IoC Lookup */}
      {activeTab === 'lookup' && (
        <div className="card" style={{ maxWidth: 560 }}>
          <div className="section-title">IoC Lookup</div>
          <form onSubmit={lookup} style={{ display:'flex', gap:8 }}>
            <input value={lookupVal} onChange={e=>setLookupVal(e.target.value)} placeholder="IP, domain, or URL to check..." style={{flex:1}} />
            <button type="submit" className="btn-primary">Check</button>
          </form>
          {lookupRes && (
            <div style={{ marginTop:16, padding:14, background:'var(--navy)', borderRadius:6,
              border:`1px solid ${lookupRes.isMalicious ? 'var(--red)' : 'var(--green)'}` }}>
              <div style={{ fontFamily:'var(--mono)', fontSize:12, marginBottom:8,
                color: lookupRes.isMalicious ? 'var(--red)' : 'var(--green)', fontWeight:700 }}>
                {lookupRes.isMalicious ? '⚠ MALICIOUS — Found in threat intel' : '✓ CLEAN — Not found in any feed'}
              </div>
              {lookupRes.matches.map((m,i)=>(
                <div key={i} style={{ fontFamily:'var(--mono)', fontSize:11, color:'var(--text2)', paddingLeft:10 }}>
                  • {m.feed} ({m.type})
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
