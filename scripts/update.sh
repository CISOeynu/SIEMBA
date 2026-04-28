#!/usr/bin/env bash
# SIEMBA Component Updater
# Called by the UI "Check for Updates" button OR: sudo bash update.sh
set -euo pipefail

LOG="/tmp/siemba-update.log"
RESULT_FILE="/tmp/siemba-update-result.json"
REPORT=()
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[UPDATE]${NC} $*" | tee -a "$LOG"; }
warn() { echo -e "${YELLOW}[SKIP]${NC}   $*" | tee -a "$LOG"; }

check_apt() {
  local pkg=$1 name=$2
  dpkg -l "$pkg" &>/dev/null || { warn "$name not installed via apt"; return; }
  local cur avail
  cur=$(dpkg -l "$pkg" 2>/dev/null | grep "^ii" | awk '{print $3}')
  avail=$(apt-cache policy "$pkg" 2>/dev/null | grep Candidate | awk '{print $2}')
  if [[ "$cur" != "$avail" && -n "$avail" ]]; then
    log "Updating $name: $cur → $avail"
    apt-get install -y --only-upgrade "$pkg" >> "$LOG" 2>&1
    REPORT+=("{\"name\":\"$name\",\"status\":\"updated\",\"version\":\"$avail\"}")
  else
    REPORT+=("{\"name\":\"$name\",\"status\":\"current\",\"version\":\"$cur\"}")
  fi
}

check_docker_image() {
  local name=$1 image=$2
  log "Pulling $name ($image)..."
  local output
  output=$(docker pull "$image" 2>&1 | tail -1)
  if echo "$output" | grep -q "up to date"; then
    REPORT+=("{\"name\":\"$name\",\"status\":\"current\"}")
  else
    REPORT+=("{\"name\":\"$name\",\"status\":\"updated\"}")
  fi
}

update_nuclei_templates() {
  command -v nuclei &>/dev/null || return
  log "Updating Nuclei templates..."
  nuclei -update-templates -silent 2>/dev/null
  local ver; ver=$(nuclei -version 2>&1 | head -1)
  REPORT+=("{\"name\":\"Nuclei Templates\",\"status\":\"updated\",\"version\":\"$ver\"}")
}

update_metasploit() {
  command -v msfupdate &>/dev/null || return
  log "Updating Metasploit..."
  msfupdate >> "$LOG" 2>&1 || warn "Metasploit update failed"
  REPORT+=("{\"name\":\"Metasploit\",\"status\":\"updated\"}")
}

update_sniper() {
  [[ -d /opt/sniper ]] || return
  log "Updating Sn1per..."
  cd /opt/sniper && git pull >> "$LOG" 2>&1 || warn "Sn1per git pull failed"
  REPORT+=("{\"name\":\"Sn1per\",\"status\":\"updated\"}")
}

update_siemba_ui() {
  [[ -d /opt/siemba/siemba-ui ]] || return
  log "Updating SIEMBA UI..."
  cd /opt/siemba
  git pull >> "$LOG" 2>&1 || warn "git pull failed"
  cd siemba-ui
  npm install --omit=dev --silent >> "$LOG" 2>&1
  npm run build --silent >> "$LOG" 2>&1 || true
  systemctl restart siemba-ui 2>/dev/null || true
  REPORT+=("{\"name\":\"SIEMBA UI\",\"status\":\"updated\"}")
}

# Detect docker vs native
if [[ -f /opt/siemba/docker-compose.yml ]] && command -v docker &>/dev/null; then
  MODE="docker"
else
  MODE="native"
fi

log "SIEMBA update starting (mode: $MODE)"
apt-get update -qq 2>/dev/null || true

if [[ "$MODE" == "native" ]]; then
  check_apt "elasticsearch" "Elasticsearch"
  check_apt "kibana"         "Kibana"
  check_apt "logstash"       "Logstash"
  check_apt "grafana"        "Grafana"
  check_apt "thehive"        "TheHive"
  update_siemba_ui
else
  check_docker_image "Elasticsearch" "docker.elastic.co/elasticsearch/elasticsearch:8.13.0"
  check_docker_image "Kibana"        "docker.elastic.co/kibana/kibana:8.13.0"
  check_docker_image "Logstash"      "docker.elastic.co/logstash/logstash:8.13.0"
  check_docker_image "Grafana"       "grafana/grafana-oss:latest"
  check_docker_image "TheHive"       "strangebee/thehive:5"
  cd /opt/siemba && docker compose up -d --remove-orphans >> "$LOG" 2>&1
  REPORT+=("{\"name\":\"Docker Stack\",\"status\":\"restarted\"}")
fi

update_nuclei_templates
update_metasploit
update_sniper

# Write JSON result for UI to read
printf '{"status":"success","items":[' > "$RESULT_FILE"
for i in "${!REPORT[@]}"; do
  printf '%s' "${REPORT[$i]}" >> "$RESULT_FILE"
  [[ $i -lt $((${#REPORT[@]}-1)) ]] && printf ',' >> "$RESULT_FILE"
done
printf ']}\n' >> "$RESULT_FILE"

log "Update complete. Result: $RESULT_FILE"
cat "$RESULT_FILE"
