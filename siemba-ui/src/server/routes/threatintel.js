import { Router } from 'express'
import { readFileSync, writeFileSync, mkdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import multer from 'multer'
import fetch from 'node-fetch'
import yaml from 'yaml'
import { requireRole } from '../middleware/auth.js'
import { logger } from '../server.js'

const router = Router()
const __dirname = dirname(fileURLToPath(import.meta.url))
const TI_DIR = process.env.THREAT_INTEL_DIR || join(__dirname, '../../../../config/threat-intel')
mkdirSync(TI_DIR, { recursive: true })

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } })

// In-memory feed registry
const feeds = new Map()

// List all feeds
router.get('/feeds', (_req, res) => res.json([...feeds.values()]))

// Add URL feed
router.post('/feeds/url', requireRole('admin'), async (req, res) => {
  const { name, url, type = 'ip', description = '' } = req.body
  if (!name || !url) return res.status(400).json({ error: 'Name and URL required' })

  try {
    const r = await fetch(url)
    if (!r.ok) throw new Error(`HTTP ${r.status}`)
    const text = await r.text()
    const lines = text.split('\n').filter(l => l.trim() && !l.startsWith('#'))

    const feed = { id: Date.now().toString(), name, url, type, description, lineCount: lines.length,
      lastUpdated: new Date().toISOString(), source: 'url' }
    feeds.set(feed.id, feed)
    await saveFeedToLogstash(type, lines, name)

    logger.info(`TI feed added: ${name} (${lines.length} entries)`)
    res.json(feed)
  } catch (e) { res.status(400).json({ error: e.message }) }
})

// Upload file feed
router.post('/feeds/upload', requireRole('admin'), upload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' })
  const { name, type = 'ip', description = '' } = req.body
  if (!name) return res.status(400).json({ error: 'Name required' })

  const text = req.file.buffer.toString('utf-8')
  let entries = []

  if (req.file.originalname.endsWith('.json')) {
    try {
      const parsed = JSON.parse(text)
      entries = Array.isArray(parsed) ? parsed.map(e => e.indicator || e.value || e.ip || e) :
        (parsed.indicators || parsed.data || []).map(e => e.indicator || e)
    } catch { return res.status(400).json({ error: 'Invalid JSON' }) }
  } else {
    entries = text.split('\n').filter(l => l.trim() && !l.startsWith('#'))
  }

  const feed = { id: Date.now().toString(), name, type, description, lineCount: entries.length,
    lastUpdated: new Date().toISOString(), source: 'upload', filename: req.file.originalname }
  feeds.set(feed.id, feed)
  await saveFeedToLogstash(type, entries.map(String), name)

  logger.info(`TI feed uploaded: ${name} (${entries.length} entries)`)
  res.json(feed)
})

// Delete feed
router.delete('/feeds/:id', requireRole('admin'), (req, res) => {
  feeds.delete(req.params.id)
  res.json({ ok: true })
})

// Refresh all URL feeds
router.post('/feeds/refresh', requireRole('admin'), async (_req, res) => {
  const results = []
  for (const [id, feed] of feeds.entries()) {
    if (feed.source !== 'url') continue
    try {
      const r = await fetch(feed.url)
      const text = await r.text()
      const lines = text.split('\n').filter(l => l.trim() && !l.startsWith('#'))
      feed.lineCount = lines.length
      feed.lastUpdated = new Date().toISOString()
      feeds.set(id, feed)
      await saveFeedToLogstash(feed.type, lines, feed.name)
      results.push({ name: feed.name, ok: true, count: lines.length })
    } catch (e) { results.push({ name: feed.name, ok: false, error: e.message }) }
  }
  res.json(results)
})

// Manual IoC lookup
router.post('/lookup', async (req, res) => {
  const { value } = req.body
  if (!value) return res.status(400).json({ error: 'Value required' })

  const matches = []
  for (const feed of feeds.values()) {
    try {
      const filePath = join(TI_DIR, `${feed.type}-blocklist.yml`)
      const content = readFileSync(filePath, 'utf-8')
      if (content.includes(value)) matches.push({ feed: feed.name, type: feed.type })
    } catch { /* file may not exist yet */ }
  }
  res.json({ value, matches, isMalicious: matches.length > 0 })
})

// Write feed to YAML for Logstash translate filter
async function saveFeedToLogstash(type, entries, feedName) {
  const file = join(TI_DIR, `${type}-blocklist.yml`)
  let existing = {}
  try { existing = yaml.parse(readFileSync(file, 'utf-8')) || {} } catch { /* new file */ }
  for (const e of entries) {
    const val = e.trim().replace(/['"]/g, '')
    if (val) existing[val] = feedName
  }
  writeFileSync(file, yaml.stringify(existing))
  logger.info(`Updated Logstash TI file: ${file} (${Object.keys(existing).length} total entries)`)
}

export default router
