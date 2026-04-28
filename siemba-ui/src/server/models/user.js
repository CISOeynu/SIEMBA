import bcrypt from 'bcryptjs'
import { randomUUID } from 'crypto'

// In-memory store — swap for a real DB (SQLite/Postgres) in production
const users = new Map()

const ROLES = ['admin', 'analyst', 'readonly']

export const UserModel = {
  async create({ username, password, role = 'analyst', email = '' }) {
    if (!ROLES.includes(role)) throw new Error(`Invalid role: ${role}`)
    if (users.has(username)) throw new Error('Username already exists')
    const hash = await bcrypt.hash(password, 12)
    const user = { id: randomUUID(), username, hash, role, email, createdAt: new Date().toISOString(), active: true }
    users.set(username, user)
    return { id: user.id, username, role, email, createdAt: user.createdAt }
  },

  async verify(username, password) {
    const user = users.get(username)
    if (!user || !user.active) return null
    const ok = await bcrypt.compare(password, user.hash)
    return ok ? { id: user.id, username, role: user.role, email: user.email } : null
  },

  list() {
    return [...users.values()].map(u => ({ id: u.id, username: u.username, role: u.role, email: u.email, active: u.active }))
  },

  updateRole(username, role) {
    const u = users.get(username)
    if (!u) throw new Error('User not found')
    if (!ROLES.includes(role)) throw new Error('Invalid role')
    u.role = role
    return true
  },

  deactivate(username) {
    const u = users.get(username)
    if (!u) throw new Error('User not found')
    u.active = false
    return true
  },

  async changePassword(username, oldPassword, newPassword) {
    const user = users.get(username)
    if (!user) throw new Error('User not found')
    const ok = await bcrypt.compare(oldPassword, user.hash)
    if (!ok) throw new Error('Wrong password')
    user.hash = await bcrypt.hash(newPassword, 12)
    return true
  },

  // Seed admin on first start
  async seedAdmin(password) {
    if (!users.has('admin')) {
      await UserModel.create({ username: 'admin', password, role: 'admin', email: 'admin@siemba.local' })
    }
  }
}

// Seed default admin
const adminPass = process.env.ADMIN_INITIAL_PASSWORD || 'ChangeMe2024!'
UserModel.seedAdmin(adminPass).catch(() => {})
