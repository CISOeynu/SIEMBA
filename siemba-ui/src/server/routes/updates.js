import { Router } from 'express'
import { exec } from 'child_process'
import { readFileSync } from 'fs'
import { requireRole } from '../middleware/auth.js'
import { logger } from '../server.js'

const router = Router()
const RESULT_FILE = '/tmp/siemba-update-result.json'

// Check current versions of all components
router.get('/versions', async (_req, res) => {
  const versions = {}

  const run = (cmd) => new Promise((resolve) => {
    exec(cmd, { timeout: 5000 }, (err, stdout) => resolve(err ? null : stdout.trim()))
  })

  const [es, kibana, logstash, grafana, nuclei, node] = await Promise.all([
    run("curl -sf http://localhost:9200 | node -e \"const d=require('fs').readFileSync('/dev/stdin','utf8'); console.log(JSON.parse(d).version.number)\" 2>/dev/null"),
    run('dpkg -l kibana 2>/dev/null | grep "^ii" | awk \'{print $3}\''),
    run('dpkg -l logstash 2>/dev/null | grep "^ii" | awk \'{print $3}\''),
    run('grafana-cli --version 2>/dev/null | head -1'),
    run('nuclei -version 2>/dev/null | head -1'),
    run('node --version 2>/dev/null')
  ])

  versions.elasticsearch = es      || 'unknown'
  versions.kibana        = kibana   || 'unknown'
  versions.logstash      = logstash || 'unknown'
  versions.grafana       = grafana  || 'unknown'
  versions.nuclei        = nuclei   || 'unknown'
  versions.node          = node     || 'unknown'
  versions.siemba        = '1.0.0'

  res.json(versions)
})

// Trigger update — runs scripts/update.sh and streams progress
router.post('/run', requireRole('admin'), (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream')
  res.setHeader('Cache-Control', 'no-cache')
  res.flushHeaders()

  const send = (type, data) => res.write(`data: ${JSON.stringify({ type, data, ts: Date.now() })}\n\n`)

  logger.info(`Update triggered by ${req.user.username}`)
  send('info', 'Starting SIEMBA component update...')

  const proc = exec('sudo bash /opt/siemba/scripts/update.sh', { timeout: 600000 })

  proc.stdout?.on('data', d => send('stdout', d.toString()))
  proc.stderr?.on('data', d => send('stderr', d.toString()))
  proc.on('close', (code) => {
    try {
      const result = JSON.parse(readFileSync(RESULT_FILE, 'utf-8'))
      send('result', result)
    } catch {
      send('result', { status: code === 0 ? 'success' : 'error', items: [] })
    }
    send('exit', { code })
    res.end()
  })
  proc.on('error', (e) => { send('error', e.message); res.end() })
})

// Get last update result
router.get('/last-result', (_req, res) => {
  try {
    const result = JSON.parse(readFileSync(RESULT_FILE, 'utf-8'))
    res.json(result)
  } catch {
    res.json({ status: 'no_data', items: [] })
  }
})

export default router
