import { NavLink } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth.js'

const NAV = [
  { to: '/',            icon: '⊞', label: 'Dashboard'     },
  { to: '/alerts',      icon: '⚡', label: 'Alerts'        },
  { to: '/integrations',icon: '⬡', label: 'Integrations'  },
  { to: '/threat-intel',icon: '◈', label: 'Threat Intel'  },
  { to: '/tools',       icon: '⚔', label: 'Security Tools'},
  { to: '/cases',       icon: '📋', label: 'Cases'         },
]

const GriffinLogo = () => (
  <svg width="38" height="38" viewBox="0 0 38 38" fill="none" xmlns="http://www.w3.org/2000/svg">
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
)

export default function Sidebar() {
  const { user, logout } = useAuth()

  return (
    <aside style={{
      width: 56, background: 'var(--navy2)', borderRight: '1px solid var(--border)',
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      padding: '10px 0', gap: 2, flexShrink: 0
    }}>
      <div style={{ marginBottom: 10 }} title="SIEMBA">
        <GriffinLogo />
      </div>

      {NAV.map(({ to, icon, label }) => (
        <NavLink key={to} to={to} end={to === '/'} title={label} style={({ isActive }) => ({
          width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center',
          borderRadius: 6, fontSize: 18, textDecoration: 'none', transition: 'all .15s',
          background: isActive ? 'rgba(0,212,255,.12)' : 'transparent',
          color: isActive ? 'var(--cyan)' : 'var(--text2)',
          border: isActive ? '1px solid rgba(0,212,255,.25)' : '1px solid transparent'
        })}>
          {icon}
        </NavLink>
      ))}

      <div style={{ marginTop: 'auto', display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'center' }}>
        {user?.role === 'admin' && (
          <NavLink to="/settings" title="Settings" style={({ isActive }) => ({
            width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center',
            borderRadius: 6, fontSize: 18, textDecoration: 'none',
            background: isActive ? 'rgba(0,212,255,.12)' : 'transparent',
            color: isActive ? 'var(--cyan)' : 'var(--text2)',
            border: isActive ? '1px solid rgba(0,212,255,.25)' : '1px solid transparent'
          })}>⚙</NavLink>
        )}
        <button onClick={logout} title="Logout" style={{
          width: 40, height: 40, background: 'transparent', border: '1px solid transparent',
          borderRadius: 6, fontSize: 16, color: 'var(--text2)', display: 'flex',
          alignItems: 'center', justifyContent: 'center'
        }}>⏻</button>
      </div>
    </aside>
  )
}
