import { Router } from 'express'
import { spawn } from 'child_process'
import { requireRole } from '../middleware/auth.js'
import { logger } from '../server.js'

const router = Router()

// Validate targets — prevent shell injection
const SAFE_TARGET = /^[a-zA-Z0-9._/:\-\[\]]+$/
function validateTarget(target) {
  if (!target || !SAFE_TARGET.test(target)) throw new Error('Invalid target: only alphanumeric, dots, slashes, colons, hyphens allowed')
  if (target.length > 255) throw new Error('Target too long')
}

// ─── Streaming helper — sends tool output line by line via SSE ────────────────
function streamTool(res, cmd, args, env = {}) {
  res.setHeader('Content-Type', 'text/event-stream')
  res.setHeader('Cache-Control', 'no-cache')
  res.setHeader('X-Accel-Buffering', 'no')
  res.flushHeaders()

  const proc = spawn(cmd, args, {
    env: { ...process.env, ...env },
    stdio: ['ignore', 'pipe', 'pipe']
  })

  const send = (type, data) => res.write(`data: ${JSON.stringify({ type, data, ts: Date.now() })}\n\n`)

  proc.stdout.on('data', d => send('stdout', d.toString()))
  proc.stderr.on('data', d => send('stderr', d.toString()))
  proc.on('close', code => { send('exit', { code }); res.end() })
  proc.on('error', e  => { send('error', e.message); res.end() })

  req?.on('close', () => proc.kill('SIGTERM'))
}

// ─── Nuclei ───────────────────────────────────────────────────────────────────
router.post('/nuclei', requireRole('admin', 'analyst'), (req, res) => {
  const { target, templates = 'cves,exposures,misconfiguration', rateLimit = '100', severity = '' } = req.body
  try { validateTarget(target) } catch (e) { return res.status(400).json({ error: e.message }) }

  const args = ['-target', target, '-t', templates, '-rate-limit', rateLimit, '-json', '-silent']
  if (severity) args.push('-severity', severity)
  logger.info(`Nuclei scan: ${target} by ${req.user.username}`)
  streamTool(res, 'nuclei', args)
})

// ─── Sn1per ───────────────────────────────────────────────────────────────────
router.post('/sniper', requireRole('admin', 'analyst'), (req, res) => {
  const { target, mode = 'normal' } = req.body
  try { validateTarget(target) } catch (e) { return res.status(400).json({ error: e.message }) }
  const ALLOWED_MODES = ['normal', 'stealth', 'flyover', 'airstrike', 'discover']
  if (!ALLOWED_MODES.includes(mode)) return res.status(400).json({ error: 'Invalid mode' })

  logger.info(`Sn1per scan: ${target} mode=${mode} by ${req.user.username}`)
  streamTool(res, 'sniper', ['-t', target, '-m', mode])
})

// ─── Metasploit (scanner modules only) ───────────────────────────────────────
router.post('/metasploit', requireRole('admin'), (req, res) => {
  const { target, module, options = {} } = req.body
  try { validateTarget(target) } catch (e) { return res.status(400).json({ error: e.message }) }

  // Only allow scanner/auxiliary modules — no exploit modules
  if (!module?.startsWith('auxiliary/scanner/') && !module?.startsWith('auxiliary/gather/')) {
    return res.status(400).json({ error: 'Only auxiliary/scanner/ and auxiliary/gather/ modules allowed' })
  }

  // Build RC script
  const optLines = Object.entries(options).map(([k, v]) => `set ${k} ${v}`).join('\n')
  const rcScript = `use ${module}\nset RHOSTS ${target}\n${optLines}\nrun\nexit\n`
  logger.info(`Metasploit: ${module} on ${target} by ${req.user.username}`)
  streamTool(res, 'msfconsole', ['-q', '-x', rcScript])
})

// ─── DMARC / Email Security Checker ──────────────────────────────────────────
router.post('/dmarc', requireRole('admin', 'analyst'), async (req, res) => {
  const { target } = req.body
  try { validateTarget(target) } catch (e) { return res.status(400).json({ error: e.message }) }

  const results = { target, checks: [], timestamp: new Date().toISOString() }
  const domain = target.replace(/^https?:\/\//, '').split('/')[0]

  const digQuery = async (type, name) => {
    return new Promise((resolve) => {
      const proc = spawn('dig', ['+short', type, name])
      let out = ''
      proc.stdout.on('data', d => out += d)
      proc.on('close', () => resolve(out.trim()))
      proc.on('error', () => resolve(''))
    })
  }

  // SPF
  const spf = await digQuery('TXT', domain)
  const spfRecord = spf.split('\n').find(l => l.includes('v=spf1'))
  results.checks.push({ name: 'SPF', status: spfRecord ? 'pass' : 'fail', value: spfRecord || 'Not found' })

  // DMARC
  const dmarc = await digQuery('TXT', `_dmarc.${domain}`)
  const dmarcRecord = dmarc.split('\n').find(l => l.includes('v=DMARC1'))
  const dmarcPolicy = dmarcRecord?.match(/p=(\w+)/)?.[1]
  results.checks.push({
    name: 'DMARC', value: dmarcRecord || 'Not found',
    status: !dmarcRecord ? 'fail' : dmarcPolicy === 'reject' ? 'pass' : dmarcPolicy === 'quarantine' ? 'warn' : 'warn',
    note: dmarcPolicy ? `Policy: ${dmarcPolicy}` : 'No DMARC record'
  })

  // DKIM (check common selectors)
  for (const sel of ['default', 'google', 'k1', 'selector1', 'selector2']) {
    const dkim = await digQuery('TXT', `${sel}._domainkey.${domain}`)
    if (dkim && dkim.includes('v=DKIM1')) {
      results.checks.push({ name: `DKIM (${sel})`, status: 'pass', value: dkim.slice(0, 60) + '...' })
      break
    }
  }
  if (!results.checks.find(c => c.name.startsWith('DKIM'))) {
    results.checks.push({ name: 'DKIM', status: 'warn', value: 'No common DKIM selector found' })
  }

  // MX records
  const mx = await digQuery('MX', domain)
  results.checks.push({ name: 'MX Records', status: mx ? 'pass' : 'warn', value: mx || 'No MX records' })

  // Reverse DNS
  if (/^\d+\.\d+\.\d+\.\d+$/.test(target)) {
    const rdns = await digQuery('PTR', target.split('.').reverse().join('.') + '.in-addr.arpa')
    results.checks.push({ name: 'Reverse DNS (PTR)', status: rdns ? 'pass' : 'warn', value: rdns || 'No PTR record' })
  }

  // Summary
  const failCount = results.checks.filter(c => c.status === 'fail').length
  results.summary = { total: results.checks.length, passed: results.checks.filter(c => c.status === 'pass').length,
    warned: results.checks.filter(c => c.status === 'warn').length, failed: failCount,
    score: Math.round(((results.checks.length - failCount) / results.checks.length) * 100) }

  logger.info(`DMARC check: ${target} by ${req.user.username}`)
  res.json(results)
})

export default router
