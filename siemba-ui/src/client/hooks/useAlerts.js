import { useState, useEffect, useCallback } from 'react'
import { api } from '../utils/api.js'

export function useAlerts({ severity, source, hours = 24, q = '*', autoRefresh = 30 } = {}) {
  const [alerts, setAlerts]   = useState([])
  const [stats,  setStats]    = useState(null)
  const [total,  setTotal]    = useState(0)
  const [loading, setLoading] = useState(true)
  const [error,  setError]    = useState(null)

  const fetch = useCallback(async () => {
    try {
      setLoading(true)
      const params = new URLSearchParams({ hours, q, size: 100 })
      if (severity) params.set('severity', severity)
      if (source)   params.set('source', source)
      const [alertData, statsData] = await Promise.all([
        api.get(`/alerts?${params}`),
        api.get('/alerts/stats')
      ])
      setAlerts(alertData.hits)
      setTotal(alertData.total)
      setStats(statsData)
      setError(null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }, [severity, source, hours, q])

  useEffect(() => {
    fetch()
    if (!autoRefresh) return
    const id = setInterval(fetch, autoRefresh * 1000)
    return () => clearInterval(id)
  }, [fetch, autoRefresh])

  return { alerts, stats, total, loading, error, refresh: fetch }
}

export function useCorrelatedAlerts(minutes = 60) {
  const [data,    setData]    = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const load = async () => {
      try {
        const result = await api.get(`/alerts/correlated?minutes=${minutes}`)
        setData(result)
      } catch { setData(null) }
      finally { setLoading(false) }
    }
    load()
    const id = setInterval(load, 60000)
    return () => clearInterval(id)
  }, [minutes])

  return { data, loading }
}
