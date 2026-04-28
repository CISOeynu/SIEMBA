# SIEMBA Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        SIEMBA Platform                          │
│                                                                 │
│  ┌──────────┐   HTTPS/443    ┌─────────────────────────────┐   │
│  │  Browser │ ─────────────► │  Nginx Reverse Proxy        │   │
│  └──────────┘                │  TLS termination            │   │
│                              └──────┬──────┬───────┬───────┘   │
│                                     │      │       │           │
│                              :3000  │ :5601│ :3001 │ :9000     │
│                    ┌──────────┘      │      │       └────────┐  │
│                    ▼                 ▼      ▼                ▼  │
│             ┌────────────┐  ┌──────────┐ ┌────────┐ ┌──────────┐│
│             │ SIEMBA UI  │  │  Kibana  │ │Grafana │ │ TheHive  ││
│             │ Node.js    │  │ 8.13     │ │ OSS    │ │    5     ││
│             │ React SPA  │  └────┬─────┘ └───┬────┘ └──────────┘│
│             └─────┬──────┘       │            │                  │
│                   │              └─────┬───────┘                 │
│                   │                   ▼                          │
│                   │          ┌──────────────────┐               │
│                   └─────────►│  Elasticsearch   │               │
│                              │  8.13  :9200     │               │
│                              └──────────────────┘               │
│                                       ▲                         │
│                              ┌────────┴──────┐                  │
│                              │   Logstash    │                  │
│                              │   Pipelines   │                  │
│                              └───────────────┘                  │
│                   ▲            ▲   ▲   ▲   ▲                   │
└───────────────────┼────────────┼───┼───┼───┼───────────────────┘
                    │            │   │   │   │
              Syslog UDP/TCP  M365 Azure Google Custom
              :5514           Graph API    HTTP :8080
```

## Data Flow

1. **Log Ingestion** — Logstash receives logs from syslog (UDP/TCP :5514), cloud APIs polled by the SIEMBA UI (M365, Azure, Google), and HTTP inputs (:8080). Each pipeline enriches, tags, and forwards events to Elasticsearch.

2. **Threat Intel Enrichment** — Pipeline `05-threatintel.conf` runs every minute, scanning new Elasticsearch documents against YAML blocklists generated from your uploaded feeds. Matched events get tagged `ti_matched=true` and re-indexed into `siemba-ti-hits-*`.

3. **Storage** — All events land in daily Elasticsearch indices: `siemba-{source}-YYYY.MM.dd`. The SIEMBA UI and Grafana query these via Elasticsearch's REST API and Elasticsearch datasource respectively.

4. **Correlation** — The `/api/alerts/correlated` endpoint groups high/critical events from the last N minutes by source IP across all integrations, surfacing multi-source attack chains.

5. **Alerting** — When an analyst escalates an alert, the SIEMBA UI calls the Jira REST API to create a ticket and/or posts to Teams/Slack webhooks with severity-based routing.

6. **Security Tools** — The tools API spawns `nuclei`, `sniper`, or `msfconsole` as child processes and streams stdout/stderr back to the browser via Server-Sent Events.

## Index Pattern Reference

| Index pattern | Source |
|---------------|--------|
| `siemba-syslog-*` | Syslog UDP/TCP |
| `siemba-m365-*` | Microsoft 365 audit logs |
| `siemba-azure-*` | Azure AD sign-ins & audit |
| `siemba-google-*` | Google Workspace activity |
| `siemba-generic-*` | Custom HTTP inputs |
| `siemba-ti-hits-*` | Threat intel matches |

## Port Reference

| Port | Protocol | Service |
|------|----------|---------|
| 80 | TCP | Nginx (redirects to 443) |
| 443 | TCP | Nginx HTTPS — main entry |
| 3000 | TCP | SIEMBA UI (internal) |
| 3001 | TCP | Grafana (internal) |
| 5514 | UDP+TCP | Syslog ingestion |
| 5601 | TCP | Kibana (internal) |
| 8080 | TCP | Logstash HTTP input (internal) |
| 9000 | TCP | TheHive (internal) |
| 9200 | TCP | Elasticsearch (internal) |
