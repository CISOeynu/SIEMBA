import { Router } from 'express'
import jwt from 'jsonwebtoken'
import { UserModel } from '../models/user.js'
import { requireRole, verifyToken } from '../middleware/auth.js'
import { logger } from '../server.js'

const router = Router()

router.post('/login', async (req, res) => {
  const { username, password } = req.body
  if (!username || !password) return res.status(400).json({ error: 'Username and password required' })
  const user = await UserModel.verify(username, password)
  if (!user) {
    logger.warn(`Failed login: ${username} from ${req.ip}`)
    return res.status(401).json({ error: 'Invalid credentials' })
  }
  const token = jwt.sign({ id: user.id, username: user.username, role: user.role }, process.env.JWT_SECRET, { expiresIn: '12h' })
  logger.info(`Login: ${username} (${user.role})`)
  res.json({ token, user: { id: user.id, username: user.username, role: user.role } })
})

router.post('/logout', verifyToken, (req, res) => {
  logger.info(`Logout: ${req.user.username}`)
  res.json({ ok: true })
})

router.get('/me', verifyToken, (req, res) => res.json(req.user))

router.get('/users', verifyToken, requireRole('admin'), (_req, res) => {
  res.json(UserModel.list())
})

router.post('/users', verifyToken, requireRole('admin'), async (req, res) => {
  try {
    const user = await UserModel.create(req.body)
    res.json(user)
  } catch (e) { res.status(400).json({ error: e.message }) }
})

router.patch('/users/:username/role', verifyToken, requireRole('admin'), (req, res) => {
  try {
    UserModel.updateRole(req.params.username, req.body.role)
    res.json({ ok: true })
  } catch (e) { res.status(400).json({ error: e.message }) }
})

router.delete('/users/:username', verifyToken, requireRole('admin'), (req, res) => {
  try {
    UserModel.deactivate(req.params.username)
    res.json({ ok: true })
  } catch (e) { res.status(400).json({ error: e.message }) }
})

router.post('/change-password', verifyToken, async (req, res) => {
  try {
    await UserModel.changePassword(req.user.username, req.body.oldPassword, req.body.newPassword)
    res.json({ ok: true })
  } catch (e) { res.status(400).json({ error: e.message }) }
})

export default router
