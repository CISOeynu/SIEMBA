import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth.js'

export default function Login() {
  const { login } = useAuth()
  const navigate  = useNavigate()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error,    setError]    = useState('')
  const [loading,  setLoading]  = useState(false)

  const submit = async (e) => {
    e.preventDefault()
    setError(''); setLoading(true)
    try {
      await login(username, password)
      navigate('/')
    } catch (err) {
      setError(err.message || 'Login failed')
    } finally { setLoading(false) }
  }

  return (
    <div style={{ minHeight: '100vh', background: 'var(--navy)', display: 'flex',
      alignItems: 'center', justifyContent: 'center', flexDirection: 'column' }}>

      {/* Griffin SVG */}
      <svg width="72" height="72" viewBox="0 0 38 38" fill="none" style={{ marginBottom: 16 }}>
        <circle cx="19" cy="19" r="18" fill="#0a1525" stroke="#00d4ff" strokeWidth="1.2"/>
        <ellipse cx="19" cy="23" rx="8" ry="6" fill="#00d4ff" opacity=".12"/>
        <path d="M11 19 Q5 12 9 8 Q13 14 11 19Z" fill="#00d4ff" opacity=".3"/>
        <path d="M27 19 Q33 12 29 8 Q25 14 27 19Z" fill="#00d4ff" opacity=".3"/>
        <circle cx="19" cy="14" r="5.5" fill="#00d4ff" opacity=".15" stroke="#00d4ff" strokeWidth=".8"/>
        <path d="M13 14 Q12 10 14.5 9 Q16 13 13 14Z" fill="#00d4ff" opacity=".5"/>
        <path d="M25 14 Q26 10 23.5 9 Q22 13 25 14Z" fill="#00d4ff" opacity=".5"/>
        <circle cx="16.5" cy="13" r="1.3" fill="#00d4ff"/>
        <circle cx="21.5" cy="13" r="1.3" fill="#00d4ff"/>
        <path d="M16.5 16 L19 18 L21.5 16" stroke="#00d4ff" strokeWidth=".8" fill="none"/>
        <path d="M13 27L11 30M15 28L14 31M23 28L24 31M25 27L27 30" stroke="#00d4ff" strokeWidth=".8" strokeLinecap="round"/>
        <path d="M15 10.5L17 7.5L19 9.5L21 7.5L23 10.5" stroke="#f59e0b" strokeWidth="1.1" fill="none" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>

      <div style={{ fontFamily: 'var(--display)', fontWeight: 700, fontSize: 28,
        color: 'var(--cyan)', letterSpacing: 5, marginBottom: 4 }}>SIEMBA</div>
      <div style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--text2)',
        letterSpacing: 2, marginBottom: 36 }}>SECURITY OPERATIONS CENTER</div>

      <form onSubmit={submit} style={{ width: 320, display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ background: 'var(--panel)', border: '1px solid var(--border)', borderRadius: 8, padding: 24 }}>
          <div style={{ marginBottom: 14 }}>
            <label style={{ display: 'block', fontSize: 10, color: 'var(--text2)',
              letterSpacing: 1.5, marginBottom: 6, fontWeight: 600 }}>USERNAME</label>
            <input value={username} onChange={e => setUsername(e.target.value)}
              autoFocus autoComplete="username" placeholder="admin"
              style={{ width: '100%' }} />
          </div>
          <div style={{ marginBottom: 18 }}>
            <label style={{ display: 'block', fontSize: 10, color: 'var(--text2)',
              letterSpacing: 1.5, marginBottom: 6, fontWeight: 600 }}>PASSWORD</label>
            <input type="password" value={password} onChange={e => setPassword(e.target.value)}
              autoComplete="current-password" placeholder="••••••••"
              style={{ width: '100%' }} />
          </div>

          {error && (
            <div style={{ padding: '8px 12px', background: 'rgba(239,68,68,.1)',
              border: '1px solid rgba(239,68,68,.3)', borderRadius: 4,
              color: 'var(--red)', fontFamily: 'var(--mono)', fontSize: 12, marginBottom: 14 }}>
              {error}
            </div>
          )}

          <button type="submit" disabled={loading} style={{
            width: '100%', padding: '10px', background: 'rgba(0,212,255,.1)',
            border: '1px solid var(--cyan)', color: 'var(--cyan)',
            borderRadius: 4, fontSize: 13, fontWeight: 700,
            fontFamily: 'var(--display)', letterSpacing: 2,
            cursor: loading ? 'not-allowed' : 'pointer'
          }}>
            {loading ? 'AUTHENTICATING...' : 'LOGIN →'}
          </button>
        </div>
        <div style={{ textAlign: 'center', fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--text3)' }}>
          SIEMBA v1.0 · Authorized use only
        </div>
      </form>
    </div>
  )
}
