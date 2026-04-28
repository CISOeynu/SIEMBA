import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAuth } from './hooks/useAuth.js'
import Sidebar from './components/Sidebar.jsx'
import Topbar from './components/Topbar.jsx'
import Login from './pages/Login.jsx'
import Dashboard from './pages/Dashboard.jsx'
import Alerts from './pages/Alerts.jsx'
import Integrations from './pages/Integrations.jsx'
import ThreatIntel from './pages/ThreatIntel.jsx'
import SecurityTools from './pages/SecurityTools.jsx'
import Cases from './pages/Cases.jsx'
import Settings from './pages/Settings.jsx'

function Layout({ children }) {
  return (
    <div style={{ display:'flex', height:'100vh', overflow:'hidden' }}>
      <Sidebar />
      <div style={{ flex:1, display:'flex', flexDirection:'column', overflow:'hidden' }}>
        <Topbar />
        <main style={{ flex:1, overflowY:'auto', padding:'16px', background:'var(--navy)' }}>
          {children}
        </main>
      </div>
    </div>
  )
}

function ProtectedRoute({ children, roles }) {
  const { user, token } = useAuth()
  if (!token) return <Navigate to="/login" replace />
  if (roles && !roles.includes(user?.role)) return <Navigate to="/" replace />
  return <Layout>{children}</Layout>
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={<ProtectedRoute><Dashboard /></ProtectedRoute>} />
        <Route path="/alerts" element={<ProtectedRoute><Alerts /></ProtectedRoute>} />
        <Route path="/integrations" element={<ProtectedRoute roles={['admin','analyst']}><Integrations /></ProtectedRoute>} />
        <Route path="/threat-intel" element={<ProtectedRoute roles={['admin','analyst']}><ThreatIntel /></ProtectedRoute>} />
        <Route path="/tools" element={<ProtectedRoute roles={['admin','analyst']}><SecurityTools /></ProtectedRoute>} />
        <Route path="/cases" element={<ProtectedRoute><Cases /></ProtectedRoute>} />
        <Route path="/settings" element={<ProtectedRoute roles={['admin']}><Settings /></ProtectedRoute>} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
