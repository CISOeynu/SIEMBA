const BASE = '/api'

function getToken() { return localStorage.getItem('siemba_token') }

async function request(method, path, body, opts = {}) {
  const headers = { 'Content-Type': 'application/json' }
  const token = getToken()
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
    ...opts
  })

  if (res.status === 401) {
    localStorage.removeItem('siemba_token')
    localStorage.removeItem('siemba_user')
    window.location.href = '/login'
    return
  }

  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
  return data
}

export const api = {
  get:    (path)        => request('GET',    path),
  post:   (path, body)  => request('POST',   path, body),
  put:    (path, body)  => request('PUT',    path, body),
  patch:  (path, body)  => request('PATCH',  path, body),
  delete: (path)        => request('DELETE', path),

  // Multipart upload
  upload: async (path, formData) => {
    const token = getToken()
    const res = await fetch(`${BASE}${path}`, {
      method: 'POST',
      headers: token ? { Authorization: `Bearer ${token}` } : {},
      body: formData
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
    return data
  },

  // Server-Sent Events stream
  stream: (path, body, onData, onDone) => {
    const token = getToken()
    fetch(`${BASE}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(body)
    }).then(res => {
      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      let buf = ''
      const read = () => reader.read().then(({ done, value }) => {
        if (done) { onDone?.(); return }
        buf += decoder.decode(value, { stream: true })
        const lines = buf.split('\n')
        buf = lines.pop()
        for (const line of lines) {
          if (line.startsWith('data: ')) {
            try { onData(JSON.parse(line.slice(6))) } catch { /* skip */ }
          }
        }
        read()
      })
      read()
    }).catch(e => onDone?.(e))
  }
}
