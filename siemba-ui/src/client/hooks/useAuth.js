import { useState, useEffect, createContext, useContext } from 'react'
import { api } from '../utils/api.js'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [token, setToken] = useState(() => localStorage.getItem('siemba_token'))
  const [user,  setUser]  = useState(() => {
    try { return JSON.parse(localStorage.getItem('siemba_user')) } catch { return null }
  })

  const login = async (username, password) => {
    const data = await api.post('/auth/login', { username, password })
    localStorage.setItem('siemba_token', data.token)
    localStorage.setItem('siemba_user',  JSON.stringify(data.user))
    setToken(data.token)
    setUser(data.user)
    return data
  }

  const logout = () => {
    localStorage.removeItem('siemba_token')
    localStorage.removeItem('siemba_user')
    setToken(null)
    setUser(null)
  }

  return <AuthContext.Provider value={{ token, user, login, logout }}>{children}</AuthContext.Provider>
}

export const useAuth = () => {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be inside AuthProvider')
  return ctx
}
