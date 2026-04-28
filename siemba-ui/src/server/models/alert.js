import { Client } from '@elastic/elasticsearch'

const es = new Client({ node: process.env.ES_HOST || 'http://127.0.0.1:9200' })

export const AlertModel = {
  async search({ severity, source, from = 0, size = 50, q = '*', hours = 24 }) {
    const must = [{ range: { '@timestamp': { gte: `now-${hours}h` } } }]
    if (severity) must.push({ term: { siemba_severity: severity } })
    if (source)   must.push({ term: { source_integration: source } })
    if (q !== '*') must.push({ query_string: { query: q, default_operator: 'AND' } })

    const result = await es.search({
      index: 'siemba-*',
      from, size,
      sort: [{ '@timestamp': { order: 'desc' } }],
      query: { bool: { must } }
    })
    return {
      total: result.hits.total.value,
      hits: result.hits.hits.map(h => ({ id: h._id, index: h._index, ...h._source }))
    }
  },

  async stats() {
    const result = await es.search({
      index: 'siemba-*', size: 0,
      query: { range: { '@timestamp': { gte: 'now-24h' } } },
      aggs: {
        by_severity:    { terms: { field: 'siemba_severity.keyword', size: 10 } },
        by_integration: { terms: { field: 'source_integration.keyword', size: 10 } },
        by_hour:        { date_histogram: { field: '@timestamp', calendar_interval: 'hour' } },
        ti_hits:        { filter: { term: { ti_matched: 'true' } } }
      }
    })
    return result.aggregations
  }
}
