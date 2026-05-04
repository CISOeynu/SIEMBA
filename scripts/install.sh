#!/usr/bin/env bash
# =============================================================================
# SIEMBA Installer v1.0.6-hotfix
# Supported: Ubuntu/Debian systemd hosts
# Focus: robust Elasticsearch bring-up on 12GB hosts + status reporting
# =============================================================================

set -Eeuo pipefail
shopt -s lastpipe

SIEMBA_VERSION="1.0.6-hotfix"
INSTALL_DIR="/opt/siemba"
LOG_FILE="/tmp/siemba-install.log"
MODE="full"
DOMAIN="localhost"
EMAIL="admin@example.com"
ADMIN_PASS=""
PLATFORM=""
ES_VERSION_SERIES="8.x"
ES_HEAP_GB=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

# Section status tracking
SECTIONS=()
declare -A STATUS

ts() { date '+%F %T'; }
log()  { echo -e "$(ts) ${GREEN}[SIEMBA]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "$(ts) ${YELLOW}[WARN ]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "$(ts) ${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
q()    { "$@" >> "$LOG_FILE" 2>&1; }

register_section() { local s="$1"; SECTIONS+=("$s"); STATUS["$s"]="PENDING"; }
status_ok() { local s="$1"; STATUS["$s"]="OK"; echo -e "${GREEN}[OK]${NC} ${s}" | tee -a "$LOG_FILE"; }
status_fail() { local s="$1"; shift || true; STATUS["$s"]="FAILED${*:+ - $*}"; echo -e "${RED}[FAILURE]${NC} ${s}${*:+ - $*}" | tee -a "$LOG_FILE"; }
status_error() { local s="$1"; shift || true; STATUS["$s"]="ERROR${*:+ - $*}"; echo -e "${RED}[ERROR]${NC} ${s}${*:+ - $*}" | tee -a "$LOG_FILE"; }

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
  echo -e "   By Roy Coren (Cisoeynu.com)"
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

require_root() { [[ "${EUID}" -eq 0 ]] || err "Run as root: sudo bash install.sh --mode=full"; }

ram_gb() { awk '/MemTotal/{printf "%d", ($2/1024/1024)+0.5}' /proc/meminfo; }

print_status_summary() {
  echo -e "\n${BOLD}Installation status summary${NC}" | tee -a "$LOG_FILE"
  for s in "${SECTIONS[@]}"; do
    printf '  - %-24s : %s\n' "$s" "${STATUS[$s]}" | tee -a "$LOG_FILE"
  done
}

show_es_diagnostics() {
  echo -e "\n${BOLD}Elasticsearch diagnostics${NC}" | tee -a "$LOG_FILE"
  {
    echo "----- systemctl status elasticsearch -----"
    systemctl status elasticsearch --no-pager || true
    echo
    echo "----- journalctl -u elasticsearch (last 200) -----"
    journalctl -u elasticsearch -n 200 --no-pager || true
    echo
    echo "----- /var/log/elasticsearch/siemba-cluster.log (last 200) -----"
    tail -n 200 /var/log/elasticsearch/siemba-cluster.log || true
    echo
    echo "----- /var/log/elasticsearch/* (listing) -----"
    ls -lah /var/log/elasticsearch || true
    echo
    echo "----- effective ES files -----"
    echo "cat /etc/elasticsearch/elasticsearch.yml"
    sed -n '1,220p' /etc/elasticsearch/elasticsearch.yml || true
    echo
    echo "cat /etc/elasticsearch/jvm.options.d/siemba.options"
    sed -n '1,80p' /etc/elasticsearch/jvm.options.d/siemba.options || true
    echo
    echo "sysctl vm.max_map_count"
    sysctl vm.max_map_count || true
    echo
    echo "ulimit -n"
    su -s /bin/bash -c 'ulimit -n' elasticsearch || true
  } | tee -a "$LOG_FILE"
}

detect_platform() {
  register_section "Platform"
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    PLATFORM="linux"
    log "Platform: Linux (${ID:-unknown} ${VERSION_ID:-})"
    case "${ID:-}" in
      ubuntu|debian) status_ok "Platform" ;;
      *) status_error "Platform" "Unsupported OS: ${ID:-unknown}"; err "Requires Ubuntu/Debian. Detected: ${ID:-unknown}" ;;
    esac
  else
    status_error "Platform" "Cannot detect OS"
    err "Cannot detect OS. This installer expects Ubuntu/Debian with systemd."
  fi
  command -v systemctl >/dev/null 2>&1 || { status_error "Platform" "systemd/systemctl missing"; err "systemd/systemctl is required."; }
}

ensure_swap() {
  register_section "Swap"
  local swap_mb desired_gb
  swap_mb="$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo)"
  [[ "$MODE" == "full" ]] && desired_gb=8 || desired_gb=4

  if (( swap_mb >= 2048 )); then
    log "Swap already present: ${swap_mb}MB"
    status_ok "Swap"
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
  status_ok "Swap"
}

prereqs_linux() {
  register_section "Prerequisites"
  step "Installing prerequisites"
  export DEBIAN_FRONTEND=noninteractive
  if q apt-get update && q apt-get install -y curl wget git jq unzip gnupg lsb-release ca-certificates software-properties-common apt-transport-https nginx ufw openssl python3 python3-pip build-essential; then
    status_ok "Prerequisites"
  else
    status_fail "Prerequisites" "apt install failed"
    err "Prerequisites installation failed"
  fi
}

setup_java() {
  register_section "Java"
  step "Java runtime"
  # Elastic bundles a JDK, but OpenJDK is useful for other components/tools.
  if q apt-get install -y openjdk-17-jre-headless; then
    java -version 2>&1 | tee -a "$LOG_FILE" >/dev/null || true
    status_ok "Java"
  else
    status_fail "Java" "openjdk-17-jre-headless install failed"
    err "Java installation failed"
  fi
}

setup_system_tuning() {
  register_section "System tuning"
  step "System tuning for Elasticsearch"
  mkdir -p /etc/sysctl.d /etc/systemd/system/elasticsearch.service.d

  cat > /etc/sysctl.d/99-siemba-elasticsearch.conf <<'EOF'
vm.max_map_count=1048576
fs.file-max=65535
EOF

  if ! sysctl --system >> "$LOG_FILE" 2>&1; then
    status_fail "System tuning" "sysctl apply failed"
    err "System tuning failed"
  fi

  cat > /etc/systemd/system/elasticsearch.service.d/override.conf <<'EOF'
[Service]
Environment=ES_PATH_CONF=/etc/elasticsearch
Environment=ES_TMPDIR=/var/lib/elasticsearch/tmp
LimitNOFILE=65535
LimitNPROC=4096
LimitMEMLOCK=infinity
TimeoutStartSec=300
EOF

  status_ok "System tuning"
}

add_elastic_repo() {
  if [[ ! -f /usr/share/keyrings/elasticsearch-keyring.gpg ]]; then
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
  fi
  echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/${ES_VERSION_SERIES}/apt stable main" > /etc/apt/sources.list.d/elastic-${ES_VERSION_SERIES}.list
  q apt-get update
}

calc_es_heap_gb() {
  local ram heap
  ram="$(ram_gb)"
  if (( ram < 8 )); then heap=2
  elif (( ram < 16 )); then heap=3
  elif (( ram < 32 )); then heap=4
  else heap=$(( ram / 2 )); (( heap > 30 )) && heap=30
  fi
  echo "$heap"
}

repair_elasticsearch_dirs() {
  mkdir -p /var/lib/elasticsearch /var/lib/elasticsearch/tmp /var/log/elasticsearch /etc/elasticsearch/jvm.options.d
  chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch /etc/elasticsearch
  chmod 750 /var/lib/elasticsearch /var/lib/elasticsearch/tmp /var/log/elasticsearch /etc/elasticsearch
}

install_elasticsearch() {
  register_section "Elasticsearch"
  step "Elasticsearch ${ES_VERSION_SERIES}"

  add_elastic_repo || { status_fail "Elasticsearch" "repo setup failed"; err "Elastic repo setup failed"; }
  q apt-get install -y elasticsearch || { status_fail "Elasticsearch" "package install failed"; err "Elasticsearch package install failed"; }

  repair_elasticsearch_dirs
  log "Repairing Elasticsearch directories and ownership..."

  ES_HEAP_GB="$(calc_es_heap_gb)"
  log "Setting Elasticsearch heap to ${ES_HEAP_GB}g"
  cat > /etc/elasticsearch/jvm.options.d/siemba.options <<EOF
-Xms${ES_HEAP_GB}g
-Xmx${ES_HEAP_GB}g
-Djava.io.tmpdir=/var/lib/elasticsearch/tmp
EOF
  chown elasticsearch:elasticsearch /etc/elasticsearch/jvm.options.d/siemba.options
  chmod 640 /etc/elasticsearch/jvm.options.d/siemba.options

  # Some package revisions leave /etc/default/elasticsearch influencing startup;
  # keep it aligned with our explicit paths.
  cat > /etc/default/elasticsearch <<'EOF'
ES_HOME=/usr/share/elasticsearch
ES_PATH_CONF=/etc/elasticsearch
ES_JAVA_HOME=
ES_JAVA_OPTS=
RESTART_ON_UPGRADE=false
EOF

  cp -a /etc/elasticsearch/elasticsearch.yml "/etc/elasticsearch/elasticsearch.yml.bak.$(date +%F-%H%M%S)" 2>/dev/null || true
  cat > /etc/elasticsearch/elasticsearch.yml <<'EOF'
cluster.name: siemba-cluster
node.name: siemba-node-1
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node
xpack.security.enabled: false
bootstrap.memory_lock: false
EOF
  chown elasticsearch:elasticsearch /etc/elasticsearch/elasticsearch.yml
  chmod 660 /etc/elasticsearch/elasticsearch.yml

  # Clean stale dirs inside ES_HOME that sometimes break startup diagnostics.
  rm -rf /usr/share/elasticsearch/logs 2>/dev/null || true
  install -d -o elasticsearch -g elasticsearch -m 0750 /usr/share/elasticsearch/logs || true

  systemctl daemon-reload
  systemctl reset-failed elasticsearch >/dev/null 2>&1 || true
  systemctl enable elasticsearch >> "$LOG_FILE" 2>&1

  log "Starting Elasticsearch..."
  if ! systemctl restart elasticsearch >> "$LOG_FILE" 2>&1; then
    status_fail "Elasticsearch" "service failed to start"
    show_es_diagnostics
    err "Elasticsearch failed to start. Full log: $LOG_FILE"
  fi

  for _ in {1..90}; do
    if curl -fsS http://127.0.0.1:9200 >/dev/null 2>&1; then
      status_ok "Elasticsearch"
      log "Elasticsearch: UP ✓"
      return 0
    fi
    sleep 2
  done

  status_fail "Elasticsearch" "HTTP API did not become ready"
  show_es_diagnostics
  err "Elasticsearch service started but HTTP API did not become ready."
}

install_kibana() {
  register_section "Kibana"
  step "Kibana ${ES_VERSION_SERIES}"
  if ! q apt-get install -y kibana; then
    status_fail "Kibana" "package install failed"
    return 1
  fi
  cp -a /etc/kibana/kibana.yml "/etc/kibana/kibana.yml.bak.$(date +%F-%H%M%S)" 2>/dev/null || true
  cat > /etc/kibana/kibana.yml <<'EOF'
server.host: "127.0.0.1"
server.port: 5601
server.basePath: "/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://127.0.0.1:9200"]
EOF
  systemctl enable kibana >> "$LOG_FILE" 2>&1 || true
  if systemctl restart kibana >> "$LOG_FILE" 2>&1; then status_ok "Kibana"; else status_fail "Kibana" "service failed"; fi
}

install_logstash() {
  register_section "Logstash"
  step "Logstash ${ES_VERSION_SERIES}"
  if ! q apt-get install -y logstash; then
    status_fail "Logstash" "package install failed"
    return 1
  fi
  mkdir -p /etc/logstash/conf.d
  cat > /etc/logstash/conf.d/01-syslog.conf <<'EOF'
input { syslog { port => 5514 } }
output { elasticsearch { hosts => ["http://localhost:9200"] index => "siemba-syslog-%{+YYYY.MM.dd}" } }
EOF
  systemctl enable logstash >> "$LOG_FILE" 2>&1 || true
  if systemctl restart logstash >> "$LOG_FILE" 2>&1; then status_ok "Logstash"; else status_fail "Logstash" "service failed"; fi
}

install_grafana() {
  register_section "Grafana"
  step "Grafana OSS"
  if [[ ! -f /usr/share/keyrings/grafana.key ]]; then
    wget -qO - https://packages.grafana.com/gpg.key | gpg --dearmor > /usr/share/keyrings/grafana.key
  fi
  echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list
  q apt-get update
  if ! q apt-get install -y grafana; then
    status_fail "Grafana" "package install failed"
    return 1
  fi
  sed -i 's/^;*http_port = .*/http_port = 3001/' /etc/grafana/grafana.ini
  sed -i 's/^;*serve_from_sub_path = .*/serve_from_sub_path = true/' /etc/grafana/grafana.ini
  sed -i 's#^;*root_url = .*#root_url = %(protocol)s://%(domain)s:%(http_port)s/grafana/#' /etc/grafana/grafana.ini
  systemctl enable grafana-server >> "$LOG_FILE" 2>&1 || true
  if systemctl restart grafana-server >> "$LOG_FILE" 2>&1; then status_ok "Grafana"; else status_fail "Grafana" "service failed"; fi
}

install_thehive() {
  register_section "TheHive"
  step "TheHive 5 optional install"
  warn "TheHive/Cassandra is heavy for 12GB RAM. Failure here will not stop SIEMBA."
  if ! q apt-get install -y cassandra; then
    status_fail "TheHive" "Cassandra install failed/skipped"
    return 0
  fi
  wget -qO /etc/apt/trusted.gpg.d/strangebee.gpg https://raw.githubusercontent.com/StrangeBee/packages/main/strangebee.gpg || true
  echo "deb https://deb.strangebee.com thehive-5.x main" > /etc/apt/sources.list.d/strangebee.list
  q apt-get update || true
  if ! q apt-get install -y thehive; then
    status_fail "TheHive" "TheHive repo/package failed"
    return 0
  fi
  systemctl enable cassandra >> "$LOG_FILE" 2>&1 || true
  systemctl restart cassandra >> "$LOG_FILE" 2>&1 || true
  systemctl enable thehive >> "$LOG_FILE" 2>&1 || true
  if systemctl restart thehive >> "$LOG_FILE" 2>&1; then status_ok "TheHive"; else status_fail "TheHive" "service failed"; fi
}

install_siemba_ui() {
  register_section "SIEMBA UI"
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
  status_ok "SIEMBA UI"
}

setup_nginx() {
  register_section "Nginx"
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
        proxy_pass http://127.0.0.1:3001/;
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
  if ! nginx -t >> "$LOG_FILE" 2>&1; then
    status_fail "Nginx" "config test failed"
    return 1
  fi
  systemctl enable nginx >> "$LOG_FILE" 2>&1 || true
  if systemctl reload nginx >> "$LOG_FILE" 2>&1 || systemctl restart nginx >> "$LOG_FILE" 2>&1; then status_ok "Nginx"; else status_fail "Nginx" "service failed"; fi
}

print_summary() {
  print_status_summary
  echo -e "\n${GREEN}✅ SIEMBA INSTALL COMPLETE / ATTEMPTED${NC}" | tee -a "$LOG_FILE"
  echo "Version: ${SIEMBA_VERSION}" | tee -a "$LOG_FILE"
  echo "Mode: ${MODE}" | tee -a "$LOG_FILE"
  echo "URL: http://${DOMAIN}" | tee -a "$LOG_FILE"
  echo "Kibana: http://${DOMAIN}/kibana/" | tee -a "$LOG_FILE"
  echo "Grafana: http://${DOMAIN}/grafana/" | tee -a "$LOG_FILE"
  echo "Elasticsearch heap: ${ES_HEAP_GB:-n/a}g" | tee -a "$LOG_FILE"
  echo "Admin Password: ${ADMIN_PASS:-see ${INSTALL_DIR}/.env}" | tee -a "$LOG_FILE"
  echo "Log file: ${LOG_FILE}" | tee -a "$LOG_FILE"
}

main() {
  : > "$LOG_FILE"
  banner
  parse_args "$@"
  require_root
  detect_platform
  ensure_swap
  prereqs_linux
  setup_java
  setup_system_tuning
  install_elasticsearch

  if [[ "$MODE" == "elastic-only" ]]; then
    print_summary
    exit 0
  fi

  install_kibana || true
  install_logstash || true
  install_grafana || true
  install_thehive || true
  install_siemba_ui || true
  setup_nginx || true
  print_summary
}

main "$@"
