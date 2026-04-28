export const SEVERITIES = ['critical', 'high', 'medium', 'low']

export const severityColor = (s) => ({
  critical: 'var(--red)',
  high:     'var(--amber)',
  medium:   'var(--purple)',
  low:      'var(--green)'
}[s] || 'var(--text2)')

export const severityBg = (s) => ({
  critical: 'rgba(239,68,68,0.15)',
  high:     'rgba(245,158,11,0.15)',
  medium:   'rgba(139,92,246,0.15)',
  low:      'rgba(16,185,129,0.15)'
}[s] || 'transparent')

export const severityEmoji = (s) => ({
  critical: '🔴', high: '🟠', medium: '🟡', low: '🟢'
}[s] || '⚪')

export const severityOrder = (s) => ({ critical:0, high:1, medium:2, low:3 }[s] ?? 4)

export const sortBySeverity = (arr, key = 'siemba_severity') =>
  [...arr].sort((a, b) => severityOrder(a[key]) - severityOrder(b[key]))
