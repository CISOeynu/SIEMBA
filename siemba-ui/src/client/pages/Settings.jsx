import { useState, useEffect } from 'react'
import { api } from '../utils/api.js'
import { useAuth } from '../hooks/useAuth.js'
import UpdateModal from '../components/UpdateModal.jsx'

export default function Settings() {
  const { user } = useAuth()
  const [users,       setUsers]       = useState([])
  const [newUser,     setNewUser]     = useState({ username:'', password:'', role:'analyst', email:'' })
  const [creating,    setCreating]    = useState(false)
  const [showUpdate,  setShowUpdate]  = useState(false)
  const [oldPw,       setOldPw]       = useState('')
  const [newPw,       setNewPw]       = useState('')
  const [pwMsg,       setPwMsg]       = useState('')
  const [activeTab,   setActiveTab]   = useState('users')

  useEffect(() => {
    api.get('/auth/users').then(setUsers).catch(() => {})
  }, [])

  const createUser = async (e) => {
    e.preventDefault()
    setCreating(true)
    try {
      const u = await api.post('/auth/users', newUser)
      setUsers(us => [...us, u])
      setNewUser({ username:'', password:'', role:'analyst', email:'' })
    } catch(e) { alert(e.message) }
    finally { setCreating(false) }
  }

  const deleteUser = async (username) => {
    if (username === user.username) return alert("Can't delete yourself")
    if (!confirm(`Deactivate user: ${username}?`)) return
    await api.delete(`/auth/users/${username}`)
    setUsers(us => us.filter(u => u.username !== username))
  }

  const changeRole = async (username, role) => {
    await api.patch(`/auth/users/${username}/role`, { role })
    setUsers(us => us.map(u => u.username === username ? {...u, role} : u))
  }

  const changePw = async (e) => {
    e.preventDefault()
    try {
      await api.post('/auth/change-password', { oldPassword: oldPw, newPassword: newPw })
      setPwMsg('✓ Password changed')
      setOldPw(''); setNewPw('')
    } catch(e) { setPwMsg('✗ ' + e.message) }
  }

  const TABS = ['users','password','system']

  return (
    <div style={{ display:'flex', flexDirection:'column', gap:16 }}>
      <div style={{ display:'flex', borderBottom:'1px solid var(--border)' }}>
        {TABS.map(t => (
          <button key={t} onClick={() => setActiveTab(t)} style={{
            background: activeTab === t ? 'rgba(0,212,255,.08)' : 'transparent',
            border:'none', borderBottom: activeTab === t ? '2px solid var(--cyan)' : '2px solid transparent',
            color: activeTab === t ? 'var(--cyan)' : 'var(--text2)',
            padding:'8px 16px', fontSize:12, fontWeight:600, letterSpacing:0.5, cursor:'pointer'
          }}>{t.toUpperCase()}</button>
        ))}
      </div>

      {/* Users */}
      {activeTab === 'users' && (
        <div style={{ display:'flex', flexDirection:'column', gap:16 }}>
          <div className="card">
            <div className="section-title">USER ACCOUNTS</div>
            <table style={{ width:'100%', borderCollapse:'collapse', fontFamily:'var(--mono)', fontSize:12 }}>
              <thead><tr style={{ borderBottom:'1px solid var(--border)' }}>
                {['Username','Email','Role','Status','Actions'].map(h =>
                  <th key={h} style={{ padding:'7px 10px', textAlign:'left', fontSize:10, color:'var(--text2)',
                    fontWeight:600, letterSpacing:1 }}>{h}</th>)}
              </tr></thead>
              <tbody>
                {users.map(u => (
                  <tr key={u.username} style={{ borderBottom:'1px solid var(--border)' }}>
                    <td style={{ padding:'8px 10px', color:'var(--text)', fontWeight:600 }}>{u.username}</td>
                    <td style={{ padding:'8px 10px', color:'var(--text2)' }}>{u.email || '—'}</td>
                    <td style={{ padding:'8px 10px' }}>
                      <select value={u.role}
                        onChange={e => changeRole(u.username, e.target.value)}
                        disabled={u.username === user.username}
                        style={{ background:'var(--navy3)', border:'1px solid var(--border2)', color:'var(--text)', borderRadius:3, padding:'2px 6px', fontSize:11 }}>
                        <option value="admin">Admin</option>
                        <option value="analyst">Analyst</option>
                        <option value="readonly">Read-Only</option>
                      </select>
                    </td>
                    <td style={{ padding:'8px 10px' }}>
                      <span style={{ fontSize:10, color: u.active !== false ? 'var(--green)' : 'var(--text3)' }}>
                        {u.active !== false ? '● Active' : '○ Inactive'}
                      </span>
                    </td>
                    <td style={{ padding:'8px 10px' }}>
                      {u.username !== user.username && (
                        <button onClick={() => deleteUser(u.username)} className="btn-danger"
                          style={{ fontSize:10, padding:'2px 8px' }}>Remove</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="card" style={{ maxWidth:480 }}>
            <div className="section-title">CREATE USER</div>
            <form onSubmit={createUser} style={{ display:'flex', flexDirection:'column', gap:10 }}>
              {[['Username','username','text'],['Email','email','email'],['Password','password','password']].map(([l,k,t])=>(
                <div key={k}><label style={{ display:'block', fontSize:10, color:'var(--text2)', marginBottom:4, letterSpacing:1 }}>{l.toUpperCase()}</label>
                  <input type={t} value={newUser[k]} onChange={e=>setNewUser(u=>({...u,[k]:e.target.value}))} required={k!=='email'} style={{width:'100%'}} /></div>
              ))}
              <div><label style={{ display:'block', fontSize:10, color:'var(--text2)', marginBottom:4, letterSpacing:1 }}>ROLE</label>
                <select value={newUser.role} onChange={e=>setNewUser(u=>({...u,role:e.target.value}))} style={{width:'100%'}}>
                  <option value="admin">Admin</option>
                  <option value="analyst">SOC Analyst</option>
                  <option value="readonly">Read-Only</option>
                </select></div>
              <button type="submit" disabled={creating} className="btn-primary">{creating ? 'Creating...' : 'Create User'}</button>
            </form>
          </div>
        </div>
      )}

      {/* Password */}
      {activeTab === 'password' && (
        <div className="card" style={{ maxWidth:400 }}>
          <div className="section-title">CHANGE PASSWORD</div>
          <form onSubmit={changePw} style={{ display:'flex', flexDirection:'column', gap:10 }}>
            <div><label style={{ display:'block', fontSize:10, color:'var(--text2)', marginBottom:4 }}>CURRENT PASSWORD</label>
              <input type="password" value={oldPw} onChange={e=>setOldPw(e.target.value)} required style={{width:'100%'}} /></div>
            <div><label style={{ display:'block', fontSize:10, color:'var(--text2)', marginBottom:4 }}>NEW PASSWORD</label>
              <input type="password" value={newPw} onChange={e=>setNewPw(e.target.value)} required style={{width:'100%'}} /></div>
            {pwMsg && <div style={{ fontFamily:'var(--mono)', fontSize:12,
              color: pwMsg.startsWith('✓') ? 'var(--green)' : 'var(--red)' }}>{pwMsg}</div>}
            <button type="submit" className="btn-primary">Change Password</button>
          </form>
        </div>
      )}

      {/* System */}
      {activeTab === 'system' && (
        <div style={{ display:'flex', flexDirection:'column', gap:12 }}>
          <div className="card">
            <div className="section-title">COMPONENT UPDATES</div>
            <p style={{ fontFamily:'var(--mono)', fontSize:12, color:'var(--text2)', marginBottom:14, lineHeight:1.7 }}>
              Check and update all SIEMBA components: Elasticsearch, Kibana, Logstash, Grafana, TheHive, Nuclei templates, Metasploit, and Sn1per.
            </p>
            <button onClick={() => setShowUpdate(true)} style={{
              background:'rgba(245,158,11,.08)', border:'1px solid var(--amber)',
              color:'var(--amber)', borderRadius:4, padding:'8px 20px', fontSize:13, fontWeight:700
            }}>⟳ Check for Updates</button>
          </div>

          <div className="card">
            <div className="section-title">EXTERNAL DASHBOARDS</div>
            <div style={{ display:'flex', gap:10, flexWrap:'wrap' }}>
              {[['Kibana', '/kibana/'], ['Grafana', '/grafana/'], ['TheHive', '/cases/']].map(([name, url]) => (
                <a key={name} href={url} target="_blank" rel="noopener noreferrer" className="btn-primary"
                  style={{ padding:'7px 16px', display:'inline-block' }}>{name} ↗</a>
              ))}
            </div>
          </div>

          <div className="card">
            <div className="section-title">ABOUT SIEMBA</div>
            <div style={{ fontFamily:'var(--mono)', fontSize:12, color:'var(--text2)', lineHeight:2 }}>
              <div>Version: <span style={{ color:'var(--cyan)' }}>1.0.0</span></div>
              <div>Stack: Elasticsearch 8.13 · Kibana · Logstash · Grafana · TheHive 5</div>
              <div>License: MIT — For authorized security use only</div>
            </div>
          </div>
        </div>
      )}

      {showUpdate && <UpdateModal onClose={() => setShowUpdate(false)} />}
    </div>
  )
}
