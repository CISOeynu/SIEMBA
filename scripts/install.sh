#!/usr/bin/env bash
# =============================================================================
# SIEMBA Installer v2.2.0-production
# Clean production-oriented single-host installer for Ubuntu/Debian
# Components: Elasticsearch, Kibana, Logstash, Grafana, Nginx
# Key design choices:
#   - Elasticsearch security enabled
#   - Manual TLS using PKCS#12 certs (avoids PEM empty-password certutil bug)
#   - Public URLs based on --domain or detected primary IP
#   - Root URL redirects to /kibana/ (no dead :3000 upstream)
#   - Browser TLS via Let's Encrypt when FQDN+email are provided, else self-signed
# =============================================================================

set -Eeuo pipefail
shopt -s lastpipe

VERSION="2.2.0-production"
LOG_FILE="/tmp/siemba-install.log"
BACKUP_DIR="/root/siemba-backups/$(date +%F-%H%M%S)"
INSTALL_DIR="/opt/siemba"
MODE="full"
ELASTIC_SERIES="8.x"
DOMAIN=""
EMAIL=""
ENABLE_UFW="false"
PRIMARY_IP=""
PUBLIC_HOST=""
ES_HEAP_GB=""
TLS_MODE="self-signed"
ELASTIC_PASS=""
KIBANA_SYSTEM_PASS=""
GRAFANA_PASS=""
LOGSTASH_API_KEY=""

ES_CERT_DIR="/etc/elasticsearch/certs"
KIBANA_CERT_DIR="/etc/kibana/certs"
LOGSTASH_CERT_DIR="/etc/logstash/certs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
SECTIONS=(); declare -A STATUS

ts() { date '+%F %T'; }
log()  { echo -e "$(ts) ${GREEN}[SIEMBA]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "$(ts) ${YELLOW}[WARN ]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "$(ts) ${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
q()    { "$@" >> "$LOG_FILE" 2>&1; }
register_section() { local s="$1"; SECTIONS+=("$s"); STATUS["$s"]="PENDING"; }
status_ok()    { local s="$1"; STATUS["$s"]="OK"; echo -e "${GREEN}[OK]${NC} ${s}" | tee -a "$LOG_FILE"; }
status_fail()  { local s="$1"; shift || true; STATUS["$s"]="FAILED${*:+ - $*}"; echo -e "${RED}[FAILURE]${NC} ${s}${*:+ - $*}" | tee -a "$LOG_FILE"; }
status_skip()  { local s="$1"; STATUS["$s"]="SKIPPED"; echo -e "${YELLOW}[WARN ]${NC} ${s} skipped" | tee -a "$LOG_FILE"; }

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
  echo -e "   Production installer"
  echo -e "   By Roy Coren-cisoeynu.com & Claude code"
  echo -e "   v${VERSION}  |  log: ${LOG_FILE}\n"
}

usage() {
  cat <<EOF
Usage: sudo bash install.sh [options]

Options:
  --mode=full|elastic-only    Install full stack or only Elasticsearch
  --domain=FQDN_OR_IP         Public domain or IP for Nginx/public URLs (optional)
  --email=EMAIL               Email for Let's Encrypt (optional)
  --elastic-series=8.x        Elastic series (default: 8.x)
  --enable-ufw=true|false     Apply basic UFW rules (default: false)
  -h, --help                  Show help
EOF
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --mode=*) MODE="${arg#--mode=}" ;;
      --domain=*) DOMAIN="${arg#--domain=}" ;;
      --email=*) EMAIL="${arg#--email=}" ;;
      --elastic-series=*) ELASTIC_SERIES="${arg#--elastic-series=}" ;;
      --enable-ufw=*) ENABLE_UFW="${arg#--enable-ufw=}" ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Ignoring unknown argument: $arg" ;;
    esac
  done
}

step() {
  echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
  echo -e "${BOLD}  $*${NC}" | tee -a "$LOG_FILE"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n" | tee -a "$LOG_FILE"
}

require_root() { [[ "${EUID}" -eq 0 ]] || err "Run as root: sudo bash install.sh"; }
primary_ip() { ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'; }
ram_gb() { awk '/MemTotal/{printf "%d", ($2/1024/1024)+0.5}' /proc/meminfo; }
randpass() { openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 24; }
is_ip() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
backup_file() { local f="$1"; [[ -e "$f" ]] || return 0; mkdir -p "$BACKUP_DIR"; cp -a "$f" "$BACKUP_DIR/" 2>/dev/null || true; }

calc_heap() {
  local ram="$1"
  if (( ram < 8 )); then echo 2
  elif (( ram < 16 )); then echo 3
  else echo 4
  fi
}

wait_http_code() {
  local url="$1" expect1="$2" expect2="$3" retries="${4:-120}"
  local i code
  for ((i=1;i<=retries;i++)); do
    code=$(curl -k -s -o /dev/null -w '%{http_code}' "$url" || true)
    if [[ "$code" == "$expect1" || "$code" == "$expect2" ]]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

wait_https_with_ca() {
  local url="$1" ca="$2" retries="${3:-120}"
  local i code
  for ((i=1;i<=retries;i++)); do
    code=$(curl --cacert "$ca" -s -o /dev/null -w '%{http_code}' "$url" || true)
    if [[ "$code" == "200" || "$code" == "401" ]]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

print_status_summary() {
  echo -e "\n${BOLD}Installation status summary${NC}" | tee -a "$LOG_FILE"
  for s in "${SECTIONS[@]}"; do
    printf '  - %-22s : %s\n' "$s" "${STATUS[$s]}" | tee -a "$LOG_FILE"
  done
}

show_es_diagnostics() {
  {
    echo "----- systemctl status elasticsearch -----"
    systemctl status elasticsearch --no-pager || true
    echo
    echo "----- journalctl -u elasticsearch (last 200) -----"
    journalctl -u elasticsearch -n 200 --no-pager || true
    echo
    echo "----- /var/log/elasticsearch/* -----"
    ls -lah /var/log/elasticsearch || true
    echo
    echo "----- /etc/elasticsearch/elasticsearch.yml -----"
    sed -n '1,240p' /etc/elasticsearch/elasticsearch.yml || true
  } | tee -a "$LOG_FILE"
}

show_kibana_diagnostics() {
  {
    echo "----- systemctl status kibana -----"
    systemctl status kibana --no-pager || true
    echo
    echo "----- journalctl -u kibana (last 200) -----"
    journalctl -u kibana -n 200 --no-pager || true
  } | tee -a "$LOG_FILE"
}

show_logstash_diagnostics() {
  {
    echo "----- systemctl status logstash -----"
    systemctl status logstash --no-pager || true
    echo
    echo "----- journalctl -u logstash (last 200) -----"
    journalctl -u logstash -n 200 --no-pager || true
  } | tee -a "$LOG_FILE"
}

show_grafana_diagnostics() {
  {
    echo "----- systemctl status grafana-server -----"
    systemctl status grafana-server --no-pager || true
    echo
    echo "----- journalctl -u grafana-server (last 200) -----"
    journalctl -u grafana-server -n 200 --no-pager || true
  } | tee -a "$LOG_FILE"
}

detect_platform() {
  register_section "Platform"
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    PRIMARY_IP="$(primary_ip || true)"
    PUBLIC_HOST="${DOMAIN:-${PRIMARY_IP:-127.0.0.1}}"
    log "Platform: Linux (${ID:-unknown} ${VERSION_ID:-})"
    case "${ID:-}" in
      ubuntu|debian) status_ok "Platform" ;;
      *) status_fail "Platform" "unsupported OS"; err "Requires Ubuntu/Debian." ;;
    esac
  else
    status_fail "Platform" "cannot detect OS"
    err "Cannot detect OS."
  fi
  command -v systemctl >/dev/null 2>&1 || err "systemd/systemctl is required."
}

prepare_clean_state() {
  register_section "Prepare state"
  step "Preparing a clean SIEMBA state"

  # Stop services if present
  for s in grafana-server logstash kibana elasticsearch nginx thehive cassandra; do
    systemctl stop "$s" >> "$LOG_FILE" 2>&1 || true
  done

  # Remove old packages if partially installed; ignore failures
  export DEBIAN_FRONTEND=noninteractive
  q apt-get remove -y elasticsearch kibana logstash grafana grafana-enterprise thehive cassandra || true
  q apt-get autoremove -y || true

  # Remove repos created by older runs
  rm -f /etc/apt/sources.list.d/elastic-*.list /etc/apt/sources.list.d/grafana.list /etc/apt/sources.list.d/strangebee.list || true
  rm -f /usr/share/keyrings/elasticsearch-keyring.gpg /etc/apt/keyrings/grafana.asc /etc/apt/keyrings/strangebee.asc || true
  q apt-get update || true

  # Remove stale runtime/config/data/certs from previous failed runs
  rm -rf \
    /var/lib/elasticsearch /var/log/elasticsearch /etc/elasticsearch \
    /etc/kibana /var/lib/kibana \
    /etc/logstash /var/lib/logstash /var/log/logstash \
    /etc/grafana /var/lib/grafana \
    /etc/ssl/siemba /var/www/siemba /opt/siemba \
    /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/siemba || true

  # Remove old SIEMBA runtime files
  rm -f /etc/systemd/system/elasticsearch.service.d/override.conf /etc/security/limits.d/99-elasticsearch.conf /etc/sysctl.d/99-siemba-elasticsearch.conf || true
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  systemctl reset-failed >> "$LOG_FILE" 2>&1 || true

  status_ok "Prepare state"
}

ensure_swap() {
  register_section "Swap"
  local swap_mb desired_gb
  swap_mb="$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo)"
  desired_gb=4
  if (( swap_mb >= 2048 )); then
    log "Swap already present: ${swap_mb}MB"
    status_ok "Swap"
    return 0
  fi
  warn "Low/no swap detected. Creating ${desired_gb}GB /swapfile ..."
  if [[ ! -f /swapfile ]]; then
    q fallocate -l "${desired_gb}G" /swapfile || q dd if=/dev/zero of=/swapfile bs=1M count=$((desired_gb*1024))
    chmod 600 /swapfile
    q mkswap /swapfile
  fi
  swapon /swapfile 2>/dev/null || true
  grep -qE '^/swapfile\s+' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  status_ok "Swap"
}

install_prereqs() {
  register_section "Prerequisites"
  step "Installing prerequisites"
  export DEBIAN_FRONTEND=noninteractive
  if q apt-get update && q apt-get install -y \
    curl wget git jq unzip gnupg lsb-release ca-certificates apt-transport-https software-properties-common \
    nginx openssl python3 python3-pip build-essential certbot python3-certbot-nginx ufw openjdk-17-jre-headless; then
    status_ok "Prerequisites"
  else
    status_fail "Prerequisites" "apt install failed"
    err "Prerequisites installation failed"
  fi
}

setup_system_tuning() {
  register_section "System tuning"
  step "System tuning"
  mkdir -p /etc/sysctl.d /etc/systemd/system/elasticsearch.service.d /etc/security/limits.d
  cat > /etc/sysctl.d/99-siemba-elasticsearch.conf <<'EOF'
vm.max_map_count=1048576
fs.file-max=65535
EOF
  grep -q '^vm.max_map_count=' /etc/sysctl.conf 2>/dev/null && sed -i 's/^vm.max_map_count=.*/vm.max_map_count=1048576/' /etc/sysctl.conf || echo 'vm.max_map_count=1048576' >> /etc/sysctl.conf
  grep -q '^fs.file-max=' /etc/sysctl.conf 2>/dev/null && sed -i 's/^fs.file-max=.*/fs.file-max=65535/' /etc/sysctl.conf || echo 'fs.file-max=65535' >> /etc/sysctl.conf
  sysctl -w vm.max_map_count=1048576 >> "$LOG_FILE" 2>&1 || true
  sysctl -w fs.file-max=65535 >> "$LOG_FILE" 2>&1 || true
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
  cat > /etc/security/limits.d/99-elasticsearch.conf <<'EOF'
elasticsearch soft nofile 65535
elasticsearch hard nofile 65535
elasticsearch soft nproc 4096
elasticsearch hard nproc 4096
EOF
  status_ok "System tuning"
}

add_elastic_repo() {
  [[ -f /usr/share/keyrings/elasticsearch-keyring.gpg ]] || wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/${ELASTIC_SERIES}/apt stable main" > /etc/apt/sources.list.d/elastic-${ELASTIC_SERIES}.list
  q apt-get update
}

install_elastic_packages() {
  register_section "Elastic packages"
  step "Installing Elasticsearch, Kibana and Logstash"
  add_elastic_repo || { status_fail "Elastic packages" "repo setup failed"; err "Elastic repo setup failed"; }
  if q apt-get install -y elasticsearch kibana logstash; then
    status_ok "Elastic packages"
  else
    status_fail "Elastic packages" "package install failed"
    err "Elastic package installation failed"
  fi
}

install_grafana_package() {
  register_section "Grafana package"
  step "Installing Grafana"
  mkdir -p /etc/apt/keyrings
  wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key >> "$LOG_FILE" 2>&1
  chmod 644 /etc/apt/keyrings/grafana.asc
  echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
  q apt-get update
  if q apt-get install -y grafana; then
    status_ok "Grafana package"
  else
    status_fail "Grafana package" "package install failed"
    err "Grafana package installation failed"
  fi
}

cleanup_stale_es_keystore() {
  register_section "ES keystore cleanup"
  step "Cleaning stale Elasticsearch secure settings"
  systemctl stop elasticsearch >/dev/null 2>&1 || true
  if [[ ! -f /etc/elasticsearch/elasticsearch.keystore ]]; then
    su -s /bin/bash -c 'ES_PATH_CONF=/etc/elasticsearch /usr/share/elasticsearch/bin/elasticsearch-keystore create' elasticsearch >> "$LOG_FILE" 2>&1 || true
  fi
  if [[ -x /usr/share/elasticsearch/bin/elasticsearch-keystore ]]; then
    mapfile -t keys < <(su -s /bin/bash -c 'ES_PATH_CONF=/etc/elasticsearch /usr/share/elasticsearch/bin/elasticsearch-keystore list 2>/dev/null' elasticsearch | grep '^xpack\.security\..*ssl\..*secure_')
    if (( ${#keys[@]} > 0 )); then
      for k in "${keys[@]}"; do
        su -s /bin/bash -c "ES_PATH_CONF=/etc/elasticsearch /usr/share/elasticsearch/bin/elasticsearch-keystore remove '${k}'" elasticsearch >> "$LOG_FILE" 2>&1 || true
      done
    fi
  fi
  status_ok "ES keystore cleanup"
}

generate_es_certs() {
  register_section "ES certificates"
  step "Generating Elasticsearch CA and node certificates"
  mkdir -p "$ES_CERT_DIR" /var/lib/elasticsearch/tmp /var/log/elasticsearch /var/lib/elasticsearch
  chown -R elasticsearch:elasticsearch /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
  chmod 750 /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch /var/lib/elasticsearch/tmp

  cat > "$ES_CERT_DIR/instances.yml" <<EOF
instances:
  - name: "$(hostname -s)"
    dns:
      - "localhost"
      - "$(hostname -s)"
      - "$(hostname -f 2>/dev/null || hostname -s)"
EOF
  if [[ -n "$DOMAIN" ]] && ! is_ip "$DOMAIN"; then
    echo "      - \"$DOMAIN\"" >> "$ES_CERT_DIR/instances.yml"
  fi
  cat >> "$ES_CERT_DIR/instances.yml" <<EOF
    ip:
      - "127.0.0.1"
      - "${PRIMARY_IP:-127.0.0.1}"
EOF
  if is_ip "$PUBLIC_HOST"; then
    echo "      - \"$PUBLIC_HOST\"" >> "$ES_CERT_DIR/instances.yml"
  fi

  # PKCS#12 mode works with blank passwords; PEM+blank passwords is a known certutil failure.
  q /usr/share/elasticsearch/bin/elasticsearch-certutil ca --silent --out "$ES_CERT_DIR/ca.p12" --pass ""
  q /usr/share/elasticsearch/bin/elasticsearch-certutil cert --silent --ca "$ES_CERT_DIR/ca.p12" --ca-pass "" --in "$ES_CERT_DIR/instances.yml" --out "$ES_CERT_DIR/elastic-certificates.p12" --pass ""

  # Extract CA cert PEM for Kibana/Logstash trust
  openssl pkcs12 -in "$ES_CERT_DIR/ca.p12" -clcerts -nokeys -out "$ES_CERT_DIR/http_ca.crt" -passin pass: >> "$LOG_FILE" 2>&1 || \
  openssl pkcs12 -in "$ES_CERT_DIR/ca.p12" -nokeys -out "$ES_CERT_DIR/http_ca.crt" -passin pass: >> "$LOG_FILE" 2>&1

  chown -R elasticsearch:elasticsearch "$ES_CERT_DIR"
  chmod 750 "$ES_CERT_DIR"
  chmod 640 "$ES_CERT_DIR/ca.p12" "$ES_CERT_DIR/elastic-certificates.p12"
  chmod 644 "$ES_CERT_DIR/http_ca.crt" "$ES_CERT_DIR/instances.yml"
  status_ok "ES certificates"
}

configure_elasticsearch() {
  register_section "Elasticsearch"
  step "Configuring Elasticsearch"
  backup_file /etc/elasticsearch/elasticsearch.yml
  mkdir -p /etc/elasticsearch/jvm.options.d /var/lib/elasticsearch /var/log/elasticsearch /var/lib/elasticsearch/tmp
  chown -R elasticsearch:elasticsearch /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
  chmod 750 /var/lib/elasticsearch /var/log/elasticsearch /var/lib/elasticsearch/tmp /etc/elasticsearch

  ES_HEAP_GB="$(calc_heap "$(ram_gb)")"
  cat > /etc/elasticsearch/jvm.options.d/siemba.options <<EOF
-Xms${ES_HEAP_GB}g
-Xmx${ES_HEAP_GB}g
-Djava.io.tmpdir=/var/lib/elasticsearch/tmp
EOF
  chown elasticsearch:elasticsearch /etc/elasticsearch/jvm.options.d/siemba.options
  chmod 640 /etc/elasticsearch/jvm.options.d/siemba.options

  cat > /etc/elasticsearch/elasticsearch.yml <<EOF
cluster.name: siemba-cluster
node.name: $(hostname -s)
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node
xpack.security.enabled: true
xpack.security.autoconfiguration.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: ${ES_CERT_DIR}/elastic-certificates.p12
xpack.security.http.ssl.truststore.path: ${ES_CERT_DIR}/elastic-certificates.p12
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: ${ES_CERT_DIR}/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: ${ES_CERT_DIR}/elastic-certificates.p12
bootstrap.memory_lock: false
EOF
  chown elasticsearch:elasticsearch /etc/elasticsearch/elasticsearch.yml
  chmod 660 /etc/elasticsearch/elasticsearch.yml

  systemctl daemon-reload
  systemctl enable elasticsearch >> "$LOG_FILE" 2>&1
  if ! systemctl restart elasticsearch >> "$LOG_FILE" 2>&1; then
    status_fail "Elasticsearch" "service failed to start"
    show_es_diagnostics
    err "Elasticsearch failed to start"
  fi
  if ! wait_https_with_ca "https://127.0.0.1:9200" "$ES_CERT_DIR/http_ca.crt" 120; then
    status_fail "Elasticsearch" "HTTPS endpoint not ready"
    show_es_diagnostics
    err "Elasticsearch HTTPS endpoint did not become ready"
  fi
  status_ok "Elasticsearch"
}

reset_elastic_passwords() {
  register_section "Elastic credentials"
  step "Resetting Elasticsearch built-in credentials"
  local out
  out=$(ES_PATH_CONF=/etc/elasticsearch /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b 2>&1) || { status_fail "Elastic credentials" "failed to reset elastic password"; echo "$out" | tee -a "$LOG_FILE"; err "Failed to reset elastic password"; }
  ELASTIC_PASS="$(echo "$out" | sed -n 's/^New value: //p' | tail -n1)"
  [[ -n "$ELASTIC_PASS" ]] || { status_fail "Elastic credentials" "could not parse elastic password"; echo "$out" | tee -a "$LOG_FILE"; err "Failed to parse elastic password"; }

  out=$(ES_PATH_CONF=/etc/elasticsearch /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -b 2>&1) || { status_fail "Elastic credentials" "failed to reset kibana_system password"; echo "$out" | tee -a "$LOG_FILE"; err "Failed to reset kibana_system password"; }
  KIBANA_SYSTEM_PASS="$(echo "$out" | sed -n 's/^New value: //p' | tail -n1)"
  [[ -n "$KIBANA_SYSTEM_PASS" ]] || { status_fail "Elastic credentials" "could not parse kibana_system password"; echo "$out" | tee -a "$LOG_FILE"; err "Failed to parse kibana_system password"; }
  status_ok "Elastic credentials"
}

configure_kibana() {
  register_section "Kibana"
  step "Configuring Kibana"
  backup_file /etc/kibana/kibana.yml
  mkdir -p "$KIBANA_CERT_DIR" /etc/kibana
  cp -f "$ES_CERT_DIR/http_ca.crt" "$KIBANA_CERT_DIR/http_ca.crt"
  chown -R kibana:kibana /etc/kibana "$KIBANA_CERT_DIR"
  chmod 750 /etc/kibana "$KIBANA_CERT_DIR"
  chmod 640 "$KIBANA_CERT_DIR/http_ca.crt"
  local enc1 enc2 enc3 public_url
  enc1="$(openssl rand -hex 32)"; enc2="$(openssl rand -hex 32)"; enc3="$(openssl rand -hex 32)"
  public_url="https://${PUBLIC_HOST}/kibana"
  cat > /etc/kibana/kibana.yml <<EOF
server.host: "127.0.0.1"
server.port: 5601
server.basePath: "/kibana"
server.rewriteBasePath: true
server.publicBaseUrl: "${public_url}"
elasticsearch.hosts: ["https://127.0.0.1:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.ssl.certificateAuthorities: ["${KIBANA_CERT_DIR}/http_ca.crt"]
elasticsearch.ssl.verificationMode: certificate
xpack.encryptedSavedObjects.encryptionKey: "${enc1}"
xpack.security.encryptionKey: "${enc2}"
xpack.reporting.encryptionKey: "${enc3}"
EOF
  chown kibana:kibana /etc/kibana/kibana.yml
  chmod 660 /etc/kibana/kibana.yml
  sudo -u kibana /usr/share/kibana/bin/kibana-keystore create >/dev/null 2>&1 || true
  printf '%s' "$KIBANA_SYSTEM_PASS" | sudo -u kibana /usr/share/kibana/bin/kibana-keystore add elasticsearch.password --stdin --force >> "$LOG_FILE" 2>&1
  systemctl enable kibana >> "$LOG_FILE" 2>&1 || true
  if ! systemctl restart kibana >> "$LOG_FILE" 2>&1; then
    status_fail "Kibana" "service failed to start"
    show_kibana_diagnostics
    err "Kibana failed to start"
  fi
  if ! wait_http_code "http://127.0.0.1:5601/kibana/login" 200 302 180; then
    status_fail "Kibana" "endpoint not ready"
    show_kibana_diagnostics
    err "Kibana did not become ready"
  fi
  status_ok "Kibana"
}

create_logstash_api_key() {
  register_section "Logstash API key"
  step "Creating API key for Logstash"
  local payload resp id key
  payload='{"name":"siemba-logstash","role_descriptors":{"siemba_logstash_writer":{"cluster":["monitor"],"indices":[{"names":["siemba-syslog-*"],"privileges":["create_index","create_doc","view_index_metadata","write"]}]}}}'
  resp=$(curl --silent --show-error --fail --cacert "$ES_CERT_DIR/http_ca.crt" -u "elastic:${ELASTIC_PASS}" -H 'Content-Type: application/json' -X POST "https://127.0.0.1:9200/_security/api_key" -d "$payload") || { status_fail "Logstash API key" "API call failed"; err "Failed to create Logstash API key"; }
  id=$(echo "$resp" | jq -r '.id'); key=$(echo "$resp" | jq -r '.api_key')
  [[ "$id" != "null" && "$key" != "null" && -n "$id" && -n "$key" ]] || { status_fail "Logstash API key" "invalid API response"; echo "$resp" | tee -a "$LOG_FILE"; err "Failed to parse Logstash API key"; }
  LOGSTASH_API_KEY="${id}:${key}"
  status_ok "Logstash API key"
}

configure_logstash() {
  register_section "Logstash"
  step "Configuring Logstash"
  mkdir -p "$LOGSTASH_CERT_DIR" /etc/logstash/conf.d
  cp -f "$ES_CERT_DIR/http_ca.crt" "$LOGSTASH_CERT_DIR/http_ca.crt"
  chown -R root:logstash /etc/logstash "$LOGSTASH_CERT_DIR"
  chmod 750 /etc/logstash "$LOGSTASH_CERT_DIR"
  chmod 640 "$LOGSTASH_CERT_DIR/http_ca.crt"
  /usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash create >> "$LOG_FILE" 2>&1 || true
  printf '%s' "$LOGSTASH_API_KEY" | /usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash add ES_API_KEY --stdin --force >> "$LOG_FILE" 2>&1
  chown root:logstash /etc/logstash/logstash.keystore || true
  chmod 640 /etc/logstash/logstash.keystore || true
  cat > /etc/logstash/conf.d/01-syslog.conf <<'EOF'
input {
  syslog {
    port => 5514
  }
}
output {
  elasticsearch {
    hosts => ["https://127.0.0.1:9200"]
    api_key => "${ES_API_KEY}"
    ssl_enabled => true
    ssl_certificate_authorities => ["/etc/logstash/certs/http_ca.crt"]
    index => "siemba-syslog-%{+YYYY.MM.dd}"
  }
}
EOF
  chown root:logstash /etc/logstash/conf.d/01-syslog.conf
  chmod 640 /etc/logstash/conf.d/01-syslog.conf
  systemctl enable logstash >> "$LOG_FILE" 2>&1 || true
  if ! systemctl restart logstash >> "$LOG_FILE" 2>&1; then
    status_fail "Logstash" "service failed to start"
    show_logstash_diagnostics
    err "Logstash failed to start"
  fi
  status_ok "Logstash"
}

configure_grafana() {
  register_section "Grafana"
  step "Configuring Grafana"
  GRAFANA_PASS="$(randpass)"
  backup_file /etc/grafana/grafana.ini
  sed -i 's/^;*http_addr = .*/http_addr = 127.0.0.1/' /etc/grafana/grafana.ini
  sed -i 's/^;*http_port = .*/http_port = 3000/' /etc/grafana/grafana.ini
  sed -i 's/^;*serve_from_sub_path = .*/serve_from_sub_path = true/' /etc/grafana/grafana.ini
  sed -i 's#^;*root_url = .*#root_url = https://'"${PUBLIC_HOST}"'/grafana/#' /etc/grafana/grafana.ini
  systemctl enable grafana-server >> "$LOG_FILE" 2>&1 || true
  if ! systemctl restart grafana-server >> "$LOG_FILE" 2>&1; then
    status_fail "Grafana" "service failed to start"
    show_grafana_diagnostics
    err "Grafana failed to start"
  fi
  /usr/sbin/grafana-cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini admin reset-admin-password "$GRAFANA_PASS" >> "$LOG_FILE" 2>&1 || true
  if ! wait_http_code "http://127.0.0.1:3000/login" 200 302 120; then
    status_fail "Grafana" "endpoint not ready"
    show_grafana_diagnostics
    err "Grafana did not become ready"
  fi
  status_ok "Grafana"
}

write_landing_page() {
  mkdir -p /var/www/siemba
  cat > /var/www/siemba/index.html <<EOF
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>SIEMBA</title>
<style>body{font-family:Arial,Helvetica,sans-serif;background:#0b1320;color:#e7eefc;margin:0;padding:40px}.card{background:#121b2b;padding:24px;border-radius:12px;max-width:900px}a{color:#7cc4ff;text-decoration:none}li{margin:10px 0}</style></head>
<body><div class="card"><h1>SIEMBA</h1><ul><li><a href="/kibana/">Open Kibana</a></li><li><a href="/grafana/">Open Grafana</a></li></ul></div></body></html>
EOF
}

setup_nginx() {
  register_section "Nginx"
  step "Configuring Nginx and browser TLS"
  write_landing_page
  backup_file /etc/nginx/sites-available/siemba
  local cert_path key_path host
  host="$PUBLIC_HOST"
  if is_ip "$host" || [[ -z "$EMAIL" ]]; then
    TLS_MODE="self-signed"
    mkdir -p /etc/ssl/siemba
    cert_path="/etc/ssl/siemba/siemba.crt"; key_path="/etc/ssl/siemba/siemba.key"
    openssl req -x509 -nodes -newkey rsa:4096 -days 825 -keyout "$key_path" -out "$cert_path" -subj "/CN=${host}" >> "$LOG_FILE" 2>&1
    cat > /etc/nginx/sites-available/siemba <<EOF
server { listen 80; server_name ${host}; return 301 https://\$host\$request_uri; }
server {
  listen 443 ssl http2; server_name ${host};
  ssl_certificate ${cert_path}; ssl_certificate_key ${key_path};
  root /var/www/siemba; index index.html;
  location = / { return 302 /kibana/; }
  location / { try_files \$uri \$uri/ =404; }
  location /kibana/ {
    proxy_pass http://127.0.0.1:5601;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
  location /grafana/ {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF
  else
    TLS_MODE="letsencrypt"
    cat > /etc/nginx/sites-available/siemba <<EOF
server {
  listen 80; server_name ${host}; root /var/www/siemba; index index.html;
  location = / { return 302 /kibana/; }
  location / { try_files \$uri \$uri/ =404; }
  location /kibana/ {
    proxy_pass http://127.0.0.1:5601;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
  location /grafana/ {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF
  fi
  ln -sf /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/siemba
  rm -f /etc/nginx/sites-enabled/default
  nginx -t >> "$LOG_FILE" 2>&1 || { status_fail "Nginx" "config test failed"; err "Nginx config test failed"; }
  systemctl enable nginx >> "$LOG_FILE" 2>&1 || true
  systemctl restart nginx >> "$LOG_FILE" 2>&1 || { status_fail "Nginx" "service failed"; err "Nginx failed to start"; }
  if [[ "$TLS_MODE" == "letsencrypt" ]]; then
    certbot --nginx --non-interactive --agree-tos -m "$EMAIL" -d "$host" --redirect >> "$LOG_FILE" 2>&1 || { warn "Let's Encrypt failed; keeping HTTP-only Nginx config"; TLS_MODE="http-only"; }
  fi
  status_ok "Nginx"
}

setup_firewall() {
  register_section "Firewall"
  step "Firewall"
  if [[ "$ENABLE_UFW" != "true" ]]; then
    status_skip "Firewall"
    return 0
  fi
  q ufw allow OpenSSH
  q ufw allow 80/tcp
  q ufw allow 443/tcp
  q ufw allow 5514/udp
  echo 'y' | ufw enable >> "$LOG_FILE" 2>&1 || true
  status_ok "Firewall"
}

write_credentials() {
  register_section "Credentials"
  step "Writing credentials"
  mkdir -p "$INSTALL_DIR"
  cat > /root/siemba-credentials.txt <<EOF
SIEMBA ${VERSION}
Generated: $(date -Is)

Public URL: https://${PUBLIC_HOST}
Kibana: https://${PUBLIC_HOST}/kibana/
Grafana: https://${PUBLIC_HOST}/grafana/

Elasticsearch:
  URL: https://127.0.0.1:9200
  CA: ${ES_CERT_DIR}/http_ca.crt
  User: elastic
  Password: ${ELASTIC_PASS}

Kibana service user:
  User: kibana_system
  Password: ${KIBANA_SYSTEM_PASS}

Grafana:
  URL: https://${PUBLIC_HOST}/grafana/
  User: admin
  Password: ${GRAFANA_PASS}

Logstash:
  Syslog port: 5514/udp
  API key: ${LOGSTASH_API_KEY}

TLS mode: ${TLS_MODE}
Log: ${LOG_FILE}
Backups: ${BACKUP_DIR}
EOF
  chmod 600 /root/siemba-credentials.txt
  status_ok "Credentials"
}

print_summary() {
  print_status_summary
  echo -e "\n${GREEN}✅ SIEMBA INSTALL COMPLETE / ATTEMPTED${NC}" | tee -a "$LOG_FILE"
  echo "Version: ${VERSION}" | tee -a "$LOG_FILE"
  echo "Mode: ${MODE}" | tee -a "$LOG_FILE"
  echo "Public URL: https://${PUBLIC_HOST}" | tee -a "$LOG_FILE"
  echo "Kibana: https://${PUBLIC_HOST}/kibana/" | tee -a "$LOG_FILE"
  echo "Grafana: https://${PUBLIC_HOST}/grafana/" | tee -a "$LOG_FILE"
  echo "Elasticsearch heap: ${ES_HEAP_GB:-n/a}g" | tee -a "$LOG_FILE"
  echo "Credentials: /root/siemba-credentials.txt" | tee -a "$LOG_FILE"
  echo "Log file: ${LOG_FILE}" | tee -a "$LOG_FILE"
}

main() {
  : > "$LOG_FILE"
  banner
  parse_args "$@"
  require_root
  detect_platform
  prepare_clean_state
  ensure_swap
  install_prereqs
  setup_system_tuning
  install_elastic_packages
  install_grafana_package
  cleanup_stale_es_keystore
  generate_es_certs
  configure_elasticsearch
  reset_elastic_passwords

  if [[ "$MODE" == "elastic-only" ]]; then
    write_credentials
    print_summary
    exit 0
  fi

  configure_kibana
  create_logstash_api_key
  configure_logstash
  configure_grafana
  setup_nginx
  setup_firewall || true
  write_credentials
  print_summary
}

main "$@"
