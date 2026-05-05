#  SIEMBA — Security Intelligence & Event Management Battle Armor

> One-stop SIEM + SOC platform for CISOs and Security Engineers  
> Elasticsearch · Kibana · Grafana · TheHive · Logstash · Open Source · Self-Hosted

---

## What is SIEMBA?

SIEMBA combines enterprise SIEM log collection with active SOC tooling in a single self-hosted web dashboard. Think Splunk + Kali Linux, fully open-source, installed with one command.

**Core capabilities:**
- Collect logs from Syslog, Microsoft 365, Azure AD, Google Workspace, and custom APIs
- Correlate events across all sources into unified security incidents
- Match events live against threat intelligence feeds (upload your own URL/JSON lists)
- Run Nuclei, Metasploit, Sn1per, and DMARC checker from the browser
- Auto-open Jira tickets and route alerts to Teams/Slack
- Role-based login: Admin, SOC Analyst, Read-Only
- Update every component with one UI button

---

## Quick Install

### Ubuntu 22.04 / 24.04 — Full Native
```bash
curl -fsSL https://raw.githubusercontent.com/CISOeynu/siemba/main/scripts/install.sh | sudo bash -s -- --mode=full
```

### Ubuntu / macOS — Docker
```bash
curl -fsSL https://raw.githubusercontent.com/CISOeynu/siemba/main/scripts/install.sh | sudo bash -s -- --mode=docker
```

### macOS — Full Native
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/CISOeynu/siemba/main/scripts/install.sh)" -- --mode=full
```

After install open: **https://your-domain-or-ip**

---

## Stack

| Component | Role | Version |
|-----------|------|---------|
| Elasticsearch | Log storage & search | 8.13 |
| Kibana | Log visualization | 8.13 |
| Logstash | Ingestion pipelines | 8.13 |
| Grafana OSS | Metrics & correlation dashboards | latest |
| TheHive 5 | SOC case management | 5.x |
| Nginx | Reverse proxy + TLS | 1.25 |
| Certbot | Let's Encrypt automation | latest |
| Node.js | SIEMBA UI & API bridge | 20 LTS |

---

## Integrations

| Source | Type |
|--------|------|
| Syslog (UDP/TCP) | Fully configurable, add/edit/delete in UI |
| Microsoft 365 | Graph API — app registration |
| Azure AD | Graph API — same app registration |
| Google Workspace | Admin SDK — service account |
| Jira | REST API — ticket auto-creation |
| Microsoft Teams | Incoming webhook — severity-based routing |
| Slack | Incoming webhook — severity-based routing |
| Threat Intelligence | Upload URL/JSON feeds, auto-match events |
| Custom API Vault | Store any token/key for future tools |

---

## Security Tools Tab

- **Nuclei** — vuln scanner, templates auto-updated
- **Metasploit** — scanner modules (no auto-exploit without double-confirm)
- **Sn1per** — automated recon
- **DMARC Checker** — SPF, DKIM, DMARC, MX, rDNS, blacklists on IP/domain/subnet/URL

---

## File Structure

```
siemba/
├── README.md
├── docker-compose.yml
├── .env.example
├── .gitignore
├── LICENSE
├── scripts/
│   ├── install.sh
│   ├── update.sh
│   ├── backup.sh
│   └── uninstall.sh
├── config/
│   ├── elasticsearch/elasticsearch.yml
│   ├── kibana/kibana.yml
│   ├── logstash/
│   │   ├── logstash.yml
│   │   └── pipelines/
│   │       ├── 01-syslog.conf
│   │       ├── 02-m365.conf
│   │       ├── 03-google.conf
│   │       ├── 04-azure.conf
│   │       └── 05-threatintel.conf
│   ├── grafana/
│   │   ├── provisioning/datasources/elasticsearch.yml
│   │   ├── provisioning/dashboards/dashboards.yml
│   │   └── dashboards/ (6 dashboard JSON files)
│   ├── nginx/siemba.conf
│   └── thehive/application.conf
├── siemba-ui/
│   ├── package.json
│   ├── Dockerfile
│   ├── vite.config.js
│   ├── index.html
│   └── src/
│       ├── server/
│       │   ├── server.js
│       │   ├── routes/ (auth, integrations, alerts, tools, threatintel, updates)
│       │   ├── middleware/auth.js
│       │   └── models/ (user, integration, alert)
│       └── client/
│           ├── App.jsx + main.jsx
│           ├── pages/ (Login, Dashboard, Alerts, Integrations, ThreatIntel, SecurityTools, Cases, Settings)
│           ├── components/ (Sidebar, Topbar, AlertTable, IntegrationCard, CorrelationTimeline, ToolTerminal, UpdateModal)
│           ├── hooks/ (useAlerts, useAuth)
│           └── utils/ (api, severity)
└── docs/
    ├── SETUP_GUIDE.md
    ├── ARCHITECTURE.md
    └── integrations/ (syslog, m365, google, jira, teams, slack, threat-intel)
```

---

## Documentation

- [Step-by-Step Setup Guide](docs/SETUP_GUIDE.md)
- [Architecture Overview](docs/ARCHITECTURE.md)
- [Syslog Integration](docs/integrations/syslog.md)
- [Microsoft 365 / Azure](docs/integrations/m365.md)
- [Google Workspace](docs/integrations/google.md)
- [Jira Ticketing](docs/integrations/jira.md)
- [Teams & Slack Alerts](docs/integrations/teams.md)
- [Threat Intelligence](docs/integrations/threat-intel.md)

---

## License

MIT — see [LICENSE](LICENSE)

> For authorized security use only. All bundled tools must only run on systems you own or have written permission to test.
