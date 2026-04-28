import { useLocation } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth.js'
import { useState, useEffect } from 'react'
import { api } from '../utils/api.js'

const PAGE_TITLES = {
  '/':             'SECURITY OVERVIEW',
  '/alerts':       'ALERTS & EVENTS',
  '/integrations': 'INTEGRATIONS',
  '/threat-intel': 'THREAT INTELLIGENCE',
  '/tools':        'SECURITY TOOLS',
  '/cases':        'CASE MANAGEMENT',
  '/settings':     'SYSTEM SETTINGS',
}

export default function Topbar() {
  const { pathname } = useLocation()
  const { user } = useAuth()
  const [health, setHealth] = useState('checking')
  const [time, setTime] = useState(new Date())

  useEffect(() => {
    const check = async () => {
      try { await api.get('/health'); setHealth('ok') }
      catch { setHealth('error') }
    }
    check()
    const hi = setInterval(check, 30000)
    const ti = setInterval(() => setTime(new Date()), 1000)
    return () => { clearInterval(hi); clearInterval(ti) }
  }, [])

  return (
    <header style={{
      height: 44, background: 'var(--navy2)', borderBottom: '1px solid var(--border)',
      display: 'flex', alignItems: 'center', padding: '0 16px', gap: 12, flexShrink: 0
    }}>
      <span style={{ fontFamily: 'var(--display)', fontWeight: 700, fontSize: 15, color: 'var(--cyan)', letterSpacing: 3 }}>
        SIEMBA
      </span>
      <span style={{ color: 'var(--border2)', fontSize: 12 }}>│</span>
      <span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--text2)', letterSpacing: 1.5 }}>
        {PAGE_TITLES[pathname] || 'SIEMBA'}
      </span>

      <div style={{ flex: 1 }} />

      <span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--text3)' }}>
        {time.toUTCString().slice(0, 25)}
      </span>

      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <span style={{
          width: 7, height: 7, borderRadius: '50%',
          background: health === 'ok' ? 'var(--green)' : health === 'error' ? 'var(--red)' : 'var(--amber)',
          boxShadow: health === 'ok' ? '0 0 6px var(--green)' : '0 0 6px var(--red)',
          display: 'inline-block'
        }} className="pulse" />
        <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: health === 'ok' ? 'var(--green)' : 'var(--red)' }}>
          {health === 'ok' ? 'ALL SYSTEMS OK' : health === 'error' ? 'BACKEND ERROR' : 'CHECKING...'}
        </span>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginLeft: 8,
        padding: '4px 10px', background: 'rgba(0,212,255,.06)', border: '1px solid var(--border)',
        borderRadius: 4, fontSize: 11, fontFamily: 'var(--mono)', color: 'var(--text2)'
      }}>
        <span style={{ color: 'var(--cyan)' }}>◈</span>
        <span>{user?.username}</span>
        <span style={{ background: 'rgba(0,212,255,.15)', color: 'var(--cyan)', padding: '1px 5px', borderRadius: 3, fontSize: 10 }}>
          {user?.role?.toUpperCase()}
        </span>
      </div>
    </header>
  )
}
