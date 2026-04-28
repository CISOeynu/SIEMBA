import 'dotenv/config'
import express from 'express'
import helmet from 'helmet'
import cors from 'cors'
import compression from 'compression'
import rateLimit from 'express-rate-limit'
import { createServer } from 'http'
import { WebSocketServer } from 'ws'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'
import winston from 'winston'

// Routes
import authRoutes        from './routes/auth.js'
import integrationsRoutes from './routes/integrations.js'
import alertsRoutes      from './routes/alerts.js'
import toolsRoutes       from './routes/tools.js'
import threatintelRoutes from './routes/threatintel.js'
import updatesRoutes     from './routes/updates.js'
import { verifyToken }   from './middleware/auth.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const app  = express()
const PORT = process.env.PORT || 3000

// Logger
export const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
  transports: [
    new winston.transports.Console({ format: winston.format.simple() }),
    new winston.transports.File({ filename: '/tmp/siemba-ui.log' })
  ]
})

// Middleware
app.use(helmet({ contentSecurityPolicy: false }))
app.use(cors({ origin: process.env.SIEMBA_DOMAIN || true, credentials: true }))
app.use(compression())
app.use(express.json({ limit: '50mb' }))
app.use(express.urlencoded({ extended: true, limit: '50mb' }))

// Rate limiting
app.use('/api/auth', rateLimit({ windowMs: 15 * 60 * 1000, max: 20, message: 'Too many auth attempts' }))
app.use('/api',      rateLimit({ windowMs: 60 * 1000, max: 500 }))

// Public routes
app.use('/api/auth', authRoutes)

// Health check (unauthenticated)
app.get('/api/health', (_req, res) => res.json({ status: 'ok', version: '1.0.0', ts: Date.now() }))

// Protected routes
app.use('/api/integrations', verifyToken, integrationsRoutes)
app.use('/api/alerts',       verifyToken, alertsRoutes)
app.use('/api/tools',        verifyToken, toolsRoutes)
app.use('/api/threatintel',  verifyToken, threatintelRoutes)
app.use('/api/updates',      verifyToken, updatesRoutes)

// Serve React build in production
if (process.env.NODE_ENV === 'production') {
  const staticPath = join(__dirname, '../../dist/client')
  app.use(express.static(staticPath))
  app.get('*', (_req, res) => res.sendFile(join(staticPath, 'index.html')))
}

// HTTP + WebSocket server
const server = createServer(app)
const wss = new WebSocketServer({ server, path: '/ws' })

wss.on('connection', (ws, req) => {
  logger.info(`WS connected: ${req.socket.remoteAddress}`)
  ws.on('error', (e) => logger.error('WS error', e))
})

// Export for tool streaming
export { wss }

server.listen(PORT, () => logger.info(`SIEMBA UI listening on :${PORT}`))
export default app
