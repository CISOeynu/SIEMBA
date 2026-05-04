#!/usr/bin/env bash
# =============================================================================
# SIEMBA Installer v1.0.4-hotfix
# Supported: Ubuntu/Debian systemd hosts
# Purpose: Safer full install for 12GB RAM systems; avoids ES memory-lock failure
# =============================================================================

set -Eeuo pipefail

SIEMBA_VERSION="1.0.4-hotfix"
INSTALL_DIR="/opt/siemba"
LOG_FILE="/tmp/siemba-install.log"

MODE="full"
DOMAIN="localhost"
EMAIL="admin@example.com"
ADMIN_PASS=""
PLATFORM=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[SIEMBA]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN ]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
q()    { "$@" >> "$LOG_FILE" 2>&1; }

step() {
  echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
  echo -e "${BOLD}  $*${NC}" | tee -a "$LOG_FILE"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n" | tee -a "$LOG_FILE"
}

banner() {
  cat <<'BANNER'
   ███████╗██╗███████╗███╗   ███╗██████╗  █████╗
   ██╔════╝██║██╔════╝████╗ ████║██╔══██╗██╔══██╗
   ███████╗██║█████╗  ██╔████╔██║██████╔╝███████║
   ╚════██║██║██╔══╝  ██║╚██╔╝██║██╔══██╗██╔══██║
   ███████║██║███████╗██║ ╚═╝ ██║██████╔╝██║  ██║
   ╚══════╝╚═╝╚══════╝╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝
BANNER
  echo -e "   Security Intelligence & Event Management Battle Armor"
  echo -e "   By Roy Coren (Cisoeynu.com) & Claude Code"
  echo -e "   v${SIEMBA_VERSION}  |  log: ${LOG_FILE}\n"
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --mode=*) MODE="${arg#--mode=}" ;;
      --domain=*) DOMAIN="${arg#--domain=}" ;;
      --email=*) EMAIL="${arg#--email=}" ;;
      --help|-h)
        banner
        echo "Usage: sudo bash install.sh --mode=full --domain=IP_OR_DOMAIN --email=MAIL"
        echo "Modes: full, elastic-only"
        exit 0
        ;;
      *) warn "Ignoring unknown argument: $arg" ;;
    esac
  done
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || err "Run as root: sudo bash install.sh --mode=full"
}

detect_platform() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    PLATFORM="linux"
    log "Platform: Linux (${ID:-unknown} ${VERSION_ID:-})"
    case "${ID:-}" in
      ubuntu|debian) ;;
      *) err "Requires Ubuntu/Debian. Detected: ${ID:-unknown}" ;;
    esac
  else
    err "Cannot detect OS. This installer expects Ubuntu/Debian with systemd."
  fi

  command -v systemctl >/dev/null 2>&1 || err "systemd/systemctl is required."
}

ram_gb() {
  awk '/MemTotal/{printf "%d", ($2/1024/1024)+0.5}' /proc/meminfo
}

ensure_swap() {
  local ram swap_mb desired_gb
  ram="$(ram_gb)"
  swap_mb="$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo)"

  # Full mode on 12GB benefits from swap because ES+Kibana+Logstash+Cassandra can spike.
  if [[ "$MODE" == "full" ]]; then
    desired_gb=8
  else
    desired_gb=4
  fi

  if (( swap_mb >= 2048 )); then
    log "Swap already present: ${swap_mb}MB"
    return 0
  fi

  warn "Low/no swap detected. Creating ${desired_gb}GB /swapfile for install stability..."
  if [[ ! -f /swapfile ]]; then
    q fallocate -l "${desired_gb}G" /swapfile || q dd if=/dev/zero of=/swapfile bs=1M count=$((desired_gb*1024))
    chmod 600 /swapfile
    q mkswap /swapfile
  fi
  swapon /swapfile 2>/dev/null || true
  grep -qE '^/swapfile\s+' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  log "Swap enabled."
}

prereqs_linux() {
  step "Installing prerequisites"
  export DEBIAN_FRONTEND=noninteractive
  q apt-get update
  q apt-get install -y \
    curl wget git jq unzip gnupg lsb-release ca-certificates \
    software-properties-common apt-transport-https \
    nginx ufw openssl python3 python3-pip build-essential openjdk-17-jdk

  if ! command -v node >/dev/null 2>&1 || ! node --version 2>/dev/null | grep -q '^v20'; then
    log "Installing Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> "$LOG_FILE" 2>&1
    q apt-get install -y nodejs
  fi
}

add_elastic_repo() {
  if [[ ! -f /usr/share/keyrings/elasticsearch-keyring.gpg ]]; then
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
  fi
  echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
  q apt-get update
}

calc_es_heap_gb() {
  local ram heap
  ram="$(ram_gb)"

  # Conservative full-stack sizing. On 12GB: 3g.
  if (( ram < 8 )); then
    heap=2
  elif (( ram < 16 )); then
    heap=3
  elif (( ram < 32 )); then
    heap=4
  else
    heap=$(( ram / 2 ))
    (( heap > 30 )) && heap=30
  fi
  echo "$heap"
}

install_elasticsearch() {
  step "Elasticsearch 8.x"
  add_elastic_repo
  q apt-get install -y elasticsearch

  local heap
  heap="$(calc_es_heap_gb)"
  log "Setting Elasticsearch heap to ${heap}g"
  mkdir -p /etc/elasticsearch/jvm.options.d
  cat > /etc/elasticsearch/jvm.options.d/siemba.options <<EOF
-Xms${heap}g
-Xmx${heap}g
EOF

  mkdir -p /etc/systemd/system/elasticsearch.service.d
  cat > /etc/systemd/system/elasticsearch.service.d/override.conf <<'EOF'
[Service]
LimitMEMLOCK=infinity
TimeoutStartSec=300
EOF

  cp -a /etc/elasticsearch/elasticsearch.yml "/etc/elasticsearch/elasticsearch.yml.bak.$(date +%F-%H%M%S)" 2>/dev/null || true
  cat > /etc/elasticsearch/elasticsearch.yml <<'EOF'
cluster.name: siemba-cluster
node.name: siemba-node-1
network.host: 127.0.0.1
http.port: 9200
xpack.security.enabled: false
bootstrap.memory_lock: false
discovery.type: single-node
EOF

  systemctl daemon-reload
  systemctl enable elasticsearch >> "$LOG_FILE" 2>&1
  log "Starting Elasticsearch..."
  if ! systemctl restart elasticsearch >> "$LOG_FILE" 2>&1; then
    journalctl -u elasticsearch -n 120 --no-pager | tee -a "$LOG_FILE" || true
    err "Elasticsearch failed to start. Full log: $LOG_FILE"
  fi

  for i in {1..60}; do
    if curl -fsS http://127.0.0.1:9200 >/dev/null 2>&1; then
      log "Elasticsearch: UP ✓"
      return 0
    fi
    sleep 2
  done

  journalctl -u elasticsearch -n 120 --no-pager | tee -a "$LOG_FILE" || true
  err "Elasticsearch service started but HTTP API did not become ready."
}

install_kibana() {
  step "Kibana 8.x"
  q apt-get install -y kibana
  cp -a /etc/kibana/kibana.yml "/etc/kibana/kibana.yml.bak.$(date +%F-%H%M%S)" 2>/dev/null || true
  cat > /etc/kibana/kibana.yml <<'EOF'
server.host: "127.0.0.1"
server.port: 5601
server.basePath: "/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://127.0.0.1:9200"]
EOF
  systemctl enable kibana >> "$LOG_FILE" 2>&1
  systemctl restart kibana >> "$LOG_FILE" 2>&1 || warn "Kibana did not start yet. Check: journalctl -u kibana -n 100 --no-pager"
  log "Kibana: installed ✓"
}

install_logstash() {
  step "Logstash 8.x"
  q apt-get install -y logstash
  mkdir -p /etc/logstash/conf.d
  cat > /etc/logstash/conf.d/01-syslog.conf <<'EOF'
input { syslog { port => 5514 } }
output { elasticsearch { hosts => ["http://localhost:9200"] index => "siemba-syslog-%{+YYYY.MM.dd}" } }
EOF
  systemctl enable logstash >> "$LOG_FILE" 2>&1
  systemctl restart logstash >> "$LOG_FILE" 2>&1 || warn "Logstash did not start yet. Check: journalctl -u logstash -n 100 --no-pager"
  log "Logstash: installed ✓"
}

install_grafana() {
  step "Grafana OSS"
  if [[ ! -f /usr/share/keyrings/grafana.key ]]; then
    wget -qO - https://packages.grafana.com/gpg.key | gpg --dearmor > /usr/share/keyrings/grafana.key
  fi
  echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list
  q apt-get update
  q apt-get install -y grafana
  sed -i 's/^;*serve_from_sub_path = .*/serve_from_sub_path = true/' /etc/grafana/grafana.ini
  sed -i 's#^;*root_url = .*#root_url = %(protocol)s://%(domain)s:%(http_port)s/grafana/#' /etc/grafana/grafana.ini
  systemctl enable grafana-server >> "$LOG_FILE" 2>&1
  systemctl restart grafana-server >> "$LOG_FILE" 2>&1 || warn "Grafana did not start yet. Check: journalctl -u grafana-server -n 100 --no-pager"
  log "Grafana: installed ✓"
}

install_thehive() {
  step "TheHive 5 optional install"
  warn "TheHive/Cassandra is heavy for 12GB RAM. Installing packages, but failure will not stop SIEMBA."
  q apt-get install -y cassandra || { warn "Cassandra install failed/skipped"; return 0; }

  wget -qO /etc/apt/trusted.gpg.d/strangebee.gpg https://raw.githubusercontent.com/StrangeBee/packages/main/strangebee.gpg || true
  echo "deb https://deb.strangebee.com thehive-5.x main" > /etc/apt/sources.list.d/strangebee.list
  q apt-get update || true
  q apt-get install -y thehive || { warn "TheHive install skipped/repo issue"; return 0; }
  systemctl enable cassandra >> "$LOG_FILE" 2>&1 || true
  systemctl restart cassandra >> "$LOG_FILE" 2>&1 || true
  systemctl enable thehive >> "$LOG_FILE" 2>&1 || true
  systemctl restart thehive >> "$LOG_FILE" 2>&1 || true
  log "TheHive: attempted ✓"
}

install_siemba_ui() {
  step "SIEMBA UI placeholder"
  mkdir -p "$INSTALL_DIR"
  ADMIN_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 16)"
  cat > "$INSTALL_DIR/.env" <<EOF
PORT=3000
ADMIN_PASS=${ADMIN_PASS}
DOMAIN=${DOMAIN}
EMAIL=${EMAIL}
EOF
  chmod 600 "$INSTALL_DIR/.env"
  log "SIEMBA UI environment written to ${INSTALL_DIR}/.env"
}

setup_nginx() {
  step "Nginx reverse proxy"
  cat > /etc/nginx/sites-available/siemba <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /kibana/ {
        proxy_pass http://127.0.0.1:5601/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /grafana/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/siemba
  rm -f /etc/nginx/sites-enabled/default
  nginx -t >> "$LOG_FILE" 2>&1 || err "Nginx config test failed. Check $LOG_FILE"
  systemctl enable nginx >> "$LOG_FILE" 2>&1
  systemctl reload nginx >> "$LOG_FILE" 2>&1 || systemctl restart nginx >> "$LOG_FILE" 2>&1
  log "Nginx: configured ✓"
}

print_summary() {
  echo -e "\n${GREEN}✅ SIEMBA INSTALL COMPLETE / ATTEMPTED${NC}"
  echo "Version: ${SIEMBA_VERSION}"
  echo "Mode: ${MODE}"
  echo "URL: http://${DOMAIN}"
  echo "Kibana: http://${DOMAIN}/kibana/"
  echo "Grafana: http://${DOMAIN}/grafana/"
  echo "Admin Password: ${ADMIN_PASS:-see ${INSTALL_DIR}/.env}"
  echo "Log file: ${LOG_FILE}"
  echo
  echo "Health checks:"
  echo "  curl http://127.0.0.1:9200"
  echo "  systemctl status elasticsearch --no-pager"
  echo "  journalctl -u elasticsearch -n 120 --no-pager"
}

main() {
  : > "$LOG_FILE"
  banner
  parse_args "$@"
  require_root
  detect_platform
  ensure_swap
  prereqs_linux
  install_elasticsearch

  if [[ "$MODE" == "elastic-only" ]]; then
    print_summary
    exit 0
  fi

  install_kibana
  install_logstash
  install_grafana
  install_thehive
  install_siemba_ui
  setup_nginx
  print_summary
}

main "$@"
