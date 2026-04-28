#!/usr/bin/env bash
# SIEMBA Uninstaller — removes all components
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
echo -e "${RED}━━━ SIEMBA Uninstaller ━━━${NC}"
echo -e "${YELLOW}This will remove Elasticsearch, Kibana, Logstash, Grafana, TheHive, and SIEMBA UI.${NC}"
read -rp "Type YES to confirm: " confirm
[[ "$confirm" != "YES" ]] && echo "Aborted." && exit 0

log() { echo -e "${GREEN}[REMOVE]${NC} $*"; }

# Stop and disable services
for svc in siemba-ui elasticsearch kibana logstash grafana-server thehive; do
  systemctl stop    "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
  log "Stopped $svc"
done

# Remove packages
apt-get remove -y --purge elasticsearch kibana logstash grafana thehive 2>/dev/null || true
log "Packages removed"

# Remove files
rm -rf /opt/siemba /etc/elasticsearch /etc/kibana /etc/logstash /etc/grafana \
       /var/lib/elasticsearch /var/lib/kibana /var/log/elasticsearch \
       /var/log/kibana /var/log/logstash /var/lib/grafana \
       /etc/systemd/system/siemba-ui.service \
       /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/siemba \
       /etc/apt/sources.list.d/elastic-8.x.list \
       /etc/apt/sources.list.d/grafana.list \
       /etc/apt/sources.list.d/strangebee.list 2>/dev/null || true

systemctl daemon-reload
systemctl reload nginx 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
log "SIEMBA fully removed."
