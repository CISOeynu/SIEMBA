#!/usr/bin/env bash
# =============================================================================
# SIEMBA Installer v2.0.0-production
# Secure, production-oriented single-host install for Ubuntu/Debian
# Components: Elasticsearch, Kibana, Logstash, Grafana, Nginx (+ optional TheHive)
# Defaults:
#   - Elastic 8.x series, same-version stack
#   - Elasticsearch security ENABLED
#   - Elasticsearch bound to 127.0.0.1 and exposed externally only via Nginx/Kibana
#   - TLS between components (ES <-> Kibana/Logstash) using local CA + PEM certs
#   - Browser HTTPS via Let's Encrypt when domain+email are provided; otherwise self-signed
#   - Conservative JVM heap sizing for 12GB hosts (3g)
# =============================================================================

set -Eeuo pipefail
shopt -s lastpipe

VERSION="2.0.0-production"
LOG_FILE="/tmp/siemba-install.log"
BACKUP_DIR="/root/siemba-backups/$(date +%F-%H%M%S)"
INSTALL_DIR="/opt/siemba"
MODE="full"
ELASTIC_SERIES="8.x"
DOMAIN="localhost"
EMAIL=""
WITH_THEHIVE="false"
ENABLE_UFW="false"
FORCE_RECONFIGURE="false"
PLATFORM=""
PRIMARY_IP=""
ELASTIC_PASS=""
KIBANA_SYSTEM_PASS=""
GRAFANA_PASS=""
LOGSTASH_API_KEY=""
ES_HEAP_GB=""
TLS_MODE="self-signed"

ES_CERT_DIR="/etc/elasticsearch/certs"
KIBANA_CERT_DIR="/etc/kibana/certs"
LOGSTASH_CERT_DIR="/etc/logstash/certs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
SECTIONS=()
declare -A STATUS

ts() { date '+%F %T'; }
log()  { echo -e "$(ts) ${GREEN}[SIEMBA]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "$(ts) ${YELLOW}[WARN ]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "$(ts) ${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
q()    { "$@" >> "$LOG_FILE" 2>&1; }
register_section() { local s="$1"; SECTIONS+=("$s"); STATUS["$s"]="PENDING"; }
status_ok()    { local s="$1"; STATUS["$s"]="OK"; echo -e "${GREEN}[OK]${NC} ${s}" | tee -a "$LOG_FILE"; }
status_fail()  { local s="$1"; shift || true; STATUS["$s"]="FAILED${*:+ - $*}"; echo -e "${RED}[FAILURE]${NC} ${s}${*:+ - $*}" | tee -a "$LOG_FILE"; }
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
  echo -e "   Production installer"
  echo -e "   v${VERSION}  |  log: ${LOG_FILE}\n"
}

usage() {
  cat <<EOF
Usage: sudo bash install.sh [options]

Options:
  --mode=full|elastic-only     Install full stack or only Elasticsearch
  --domain=FQDN_OR_IP          Public domain or IP for Nginx/Grafana/Kibana links
  --email=EMAIL                Email for Let's Encrypt (optional but recommended)
  --elastic-series=8.x         Elastic major series (default: 8.x)
  --with-thehive=true|false    Install TheHive + Cassandra (default: false)
  --enable-ufw=true|false      Apply firewall rules and enable UFW (default: false)
  --force-reconfigure=true     Continue even if existing ES data/config is detected
  -h, --help                   Show help
EOF
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --mode=*) MODE="${arg#--mode=}" ;;
      --domain=*) DOMAIN="${arg#--domain=}" ;;
      --email=*) EMAIL="${arg#--email=}" ;;
      --elastic-series=*) ELASTIC_SERIES="${arg#--elastic-series=}" ;;
      --with-thehive=*) WITH_THEHIVE="${arg#--with-thehive=}" ;;
      --enable-ufw=*) ENABLE_UFW="${arg#--enable-ufw=}" ;;
      --force-reconfigure=*) FORCE_RECONFIGURE="${arg#--force-reconfigure=}" ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Ignoring unknown argument: $arg" ;;
    esac
  done
}

require_root() { [[ "${EUID}" -eq 0 ]] || err "Run as root: sudo bash install.sh"; }
ram_gb() { awk '/MemTotal/{printf "%d", ($2/1024/1024)+0.5}' /proc/meminfo; }
randpass() { openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 24; }
is_ip() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
primary_ip() { ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'; }

print_status_summary() {
  echo -e "\n${BOLD}Installation status summary${NC}" | tee -a "$LOG_FILE"
  for s in "${SECTIONS[@]}"; do
    printf '  - %-24s : %s\n' "$s" "${STATUS[$s]}" | tee -a "$LOG_FILE"
  done
}

backup_file() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  mkdir -p "$BACKUP_DIR"
  cp -a "$f" "$BACKUP_DIR/"
}

wait_for_https_401_or_200() {
  local url="$1" ca="$2" retries="${3:-90}"
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

wait_for_http_200() {
  local url="$1" retries="${2:-90}"
  local i code
  for ((i=1;i<=retries;i++)); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "401" ]]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

show_es_diagnostics() {
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
    echo "----- /etc/elasticsearch/elasticsearch.yml -----"
    sed -n '1,240p' /etc/elasticsearch/elasticsearch.yml || true
  } | tee -a "$LOG_FILE"
}

detect_platform() {
  register_section "Platform"
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    PLATFORM="linux"
    PRIMARY_IP="$(primary_ip || true)"
    log "Platform: Linux (${ID:-unknown} ${VERSION_ID:-})"
    case "${ID:-}" in
      ubuntu|debian) status_ok "Platform" ;;
      *) status_error "Platform" "Unsupported OS: ${ID:-unknown}"; err "Requires Ubuntu/Debian." ;;
    esac
  else
    status_error "Platform" "Cannot detect OS"
    err "Cannot detect OS."
  fi
  command -v systemctl >/dev/null 2>&1 || { status_error "Platform" "systemd missing"; err "systemd/systemctl is required."; }
}

check_existing_state() {
  register_section "Existing state"
  step "Checking existing state"
  mkdir -p "$BACKUP_DIR"
  if [[ -d /var/lib/elasticsearch ]] && find /var/lib/elasticsearch -mindepth 1 -print -quit | grep -q .; then
    warn "Existing Elasticsearch data directory detected: /var/lib/elasticsearch"
    if [[ "$FORCE_RECONFIGURE" != "true" ]]; then
      status_error "Existing state" "Existing ES data detected; rerun with --force-reconfigure=true if this is a fresh/partial deployment"
      err "Refusing to rewrite a host with existing Elasticsearch data without --force-reconfigure=true"
    fi
  fi
  status_ok "Existing state"
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
  warn "Low/no swap detected. Creating ${desired_gb}GB /swapfile for stability..."
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
  if [[ ! -f /usr/share/keyrings/elasticsearch-keyring.gpg ]]; then
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
  fi
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

cleanup_stale_es_keystore() {
  register_section "ES keystore cleanup"
  step "Cleaning stale Elasticsearch secure settings"
  systemctl stop elasticsearch >/dev/null 2>&1 || true
  if [[ ! -f /etc/elasticsearch/elasticsearch.keystore ]]; then
    su -s /bin/bash -c 'ES_PATH_CONF=/etc/elasticsearch /usr/share/elasticsearch/bin/elasticsearch-keystore create -f' elasticsearch >> "$LOG_FILE" 2>&1 || true
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

calc_es_heap_gb() {
  local ram heap
  ram="$(ram_gb)"
  if (( ram < 8 )); then heap=2
  elif (( ram < 16 )); then heap=3
  elif (( ram < 32 )); then heap=4
  else heap=4
  fi
  echo "$heap"
}

generate_es_certs() {
  register_section "ES certificates"
  step "Generating Elasticsearch CA and node certificates"
  mkdir -p "$ES_CERT_DIR" /var/lib/elasticsearch/tmp
  chown -R elasticsearch:elasticsearch /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
  chmod 750 /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch /var/lib/elasticsearch/tmp

  # CA in PEM format for easy trust by Kibana and Logstash
  if [[ ! -f "$ES_CERT_DIR/ca/ca.crt" || ! -f "$ES_CERT_DIR/ca/ca.key" ]]; then
    rm -rf "$ES_CERT_DIR/ca" "$ES_CERT_DIR/generated" "$ES_CERT_DIR/ca.zip" "$ES_CERT_DIR/certs.zip"
    q /usr/share/elasticsearch/bin/elasticsearch-certutil ca --silent --pem --out "$ES_CERT_DIR/ca.zip" --pass ""
    unzip -o "$ES_CERT_DIR/ca.zip" -d "$ES_CERT_DIR/ca" >> "$LOG_FILE" 2>&1
  fi

  local ca_crt ca_key
  ca_crt="$(find "$ES_CERT_DIR/ca" -type f -name '*.crt' | head -n1)"
  ca_key="$(find "$ES_CERT_DIR/ca" -type f -name '*.key' | head -n1)"
  [[ -n "$ca_crt" && -n "$ca_key" ]] || { status_fail "ES certificates" "failed to generate CA"; err "Certificate authority generation failed"; }

  cat > "$ES_CERT_DIR/instances.yml" <<EOF
instances:
  - name: "$(hostname -s)"
    dns:
      - "localhost"
      - "$(hostname -s)"
      - "$(hostname -f 2>/dev/null || hostname -s)"
EOF
  if [[ -n "$DOMAIN" && "$DOMAIN" != "localhost" && ! $(is_ip "$DOMAIN"; echo $?) -eq 0 ]]; then
    echo "      - \"$DOMAIN\"" >> "$ES_CERT_DIR/instances.yml"
  fi
  cat >> "$ES_CERT_DIR/instances.yml" <<EOF
    ip:
      - "127.0.0.1"
EOF
  if [[ -n "$PRIMARY_IP" ]]; then
    echo "      - \"$PRIMARY_IP\"" >> "$ES_CERT_DIR/instances.yml"
  fi

  rm -rf "$ES_CERT_DIR/generated" "$ES_CERT_DIR/certs.zip"
  q /usr/share/elasticsearch/bin/elasticsearch-certutil cert --silent --pem --ca-cert "$ca_crt" --ca-key "$ca_key" --in "$ES_CERT_DIR/instances.yml" --out "$ES_CERT_DIR/certs.zip" --pass ""
  unzip -o "$ES_CERT_DIR/certs.zip" -d "$ES_CERT_DIR/generated" >> "$LOG_FILE" 2>&1

  local node_crt node_key final_ca
  node_crt="$(find "$ES_CERT_DIR/generated" -type f -name '*.crt' ! -name 'ca.crt' | head -n1)"
  node_key="$(find "$ES_CERT_DIR/generated" -type f -name '*.key' ! -name 'ca.key' | head -n1)"
  final_ca="$ca_crt"
  [[ -n "$node_crt" && -n "$node_key" ]] || { status_fail "ES certificates" "failed to generate node cert/key"; err "Node certificate generation failed"; }

  cp -f "$node_crt" "$ES_CERT_DIR/node.crt"
  cp -f "$node_key" "$ES_CERT_DIR/node.key"
  cp -f "$final_ca" "$ES_CERT_DIR/http_ca.crt"
  chown -R elasticsearch:elasticsearch "$ES_CERT_DIR"
  chmod 750 "$ES_CERT_DIR"
  find "$ES_CERT_DIR" -type f -name '*.key' -exec chmod 640 {} \;
  find "$ES_CERT_DIR" -type f \( -name '*.crt' -o -name '*.yml' -o -name '*.txt' \) -exec chmod 644 {} \;
  status_ok "ES certificates"
}

configure_elasticsearch() {
  register_section "Elasticsearch"
  step "Configuring Elasticsearch"
  backup_file /etc/elasticsearch/elasticsearch.yml
  mkdir -p /etc/elasticsearch/jvm.options.d /var/lib/elasticsearch /var/log/elasticsearch /var/lib/elasticsearch/tmp
  chown -R elasticsearch:elasticsearch /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
  chmod 750 /var/lib/elasticsearch /var/log/elasticsearch /var/lib/elasticsearch/tmp /etc/elasticsearch

  ES_HEAP_GB="$(calc_es_heap_gb)"
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
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.key: ${ES_CERT_DIR}/node.key
xpack.security.http.ssl.certificate: ${ES_CERT_DIR}/node.crt
xpack.security.http.ssl.certificate_authorities: ["${ES_CERT_DIR}/http_ca.crt"]
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.key: ${ES_CERT_DIR}/node.key
xpack.security.transport.ssl.certificate: ${ES_CERT_DIR}/node.crt
xpack.security.transport.ssl.certificate_authorities: ["${ES_CERT_DIR}/http_ca.crt"]
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
  if ! wait_for_https_401_or_200 "https://127.0.0.1:9200" "$ES_CERT_DIR/http_ca.crt" 90; then
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
  enc1="$(openssl rand -hex 32)"
  enc2="$(openssl rand -hex 32)"
  enc3="$(openssl rand -hex 32)"
  public_url="https://${DOMAIN}/kibana"

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
    journalctl -u kibana -n 200 --no-pager | tee -a "$LOG_FILE" || true
    err "Kibana failed to start"
  fi
  if ! wait_for_http_200 "http://127.0.0.1:5601/kibana/login" 120; then
    status_fail "Kibana" "HTTP endpoint not ready"
    journalctl -u kibana -n 200 --no-pager | tee -a "$LOG_FILE" || true
    err "Kibana endpoint did not become ready"
  fi
  status_ok "Kibana"
}

create_logstash_api_key() {
  register_section "Logstash API key"
  step "Creating API key for Logstash"
  local payload resp id key
  payload='{"name":"siemba-logstash","role_descriptors":{"siemba_logstash_writer":{"cluster":["monitor"],"indices":[{"names":["siemba-syslog-*"],"privileges":["create_index","create_doc","view_index_metadata","write"]}]}}}'
  resp=$(curl --silent --show-error --fail --cacert "$ES_CERT_DIR/http_ca.crt" -u "elastic:${ELASTIC_PASS}" -H 'Content-Type: application/json' -X POST "https://127.0.0.1:9200/_security/api_key" -d "$payload") || { status_fail "Logstash API key" "API call failed"; err "Failed to create Logstash API key"; }
  id=$(echo "$resp" | jq -r '.id')
  key=$(echo "$resp" | jq -r '.api_key')
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

  /usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash create --force >> "$LOG_FILE" 2>&1 || true
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
    journalctl -u logstash -n 200 --no-pager | tee -a "$LOG_FILE" || true
    err "Logstash failed to start"
  fi
  status_ok "Logstash"
}

install_grafana() {
  register_section "Grafana"
  step "Installing and configuring Grafana"
  mkdir -p /etc/apt/keyrings
  wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key >> "$LOG_FILE" 2>&1
  chmod 644 /etc/apt/keyrings/grafana.asc
  echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
  q apt-get update
  q apt-get install -y grafana

  GRAFANA_PASS="$(randpass)"
  backup_file /etc/grafana/grafana.ini
  sed -i 's/^;*http_addr = .*/http_addr = 127.0.0.1/' /etc/grafana/grafana.ini
  sed -i 's/^;*http_port = .*/http_port = 3000/' /etc/grafana/grafana.ini
  sed -i 's#^;*root_url = .*#root_url = https://'"${DOMAIN}"'/grafana/#' /etc/grafana/grafana.ini
  sed -i 's/^;*serve_from_sub_path = .*/serve_from_sub_path = true/' /etc/grafana/grafana.ini

  systemctl enable grafana-server >> "$LOG_FILE" 2>&1 || true
  if ! systemctl restart grafana-server >> "$LOG_FILE" 2>&1; then
    status_fail "Grafana" "service failed to start"
    journalctl -u grafana-server -n 200 --no-pager | tee -a "$LOG_FILE" || true
    err "Grafana failed to start"
  fi
  /usr/sbin/grafana-cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini admin reset-admin-password "$GRAFANA_PASS" >> "$LOG_FILE" 2>&1 || true
  if ! wait_for_http_200 "http://127.0.0.1:3000/login" 90; then
    status_fail "Grafana" "HTTP endpoint not ready"
    journalctl -u grafana-server -n 200 --no-pager | tee -a "$LOG_FILE" || true
    err "Grafana endpoint did not become ready"
  fi
  status_ok "Grafana"
}

install_thehive() {
  register_section "TheHive"
  step "Optional TheHive installation"
  if [[ "$WITH_THEHIVE" != "true" ]]; then
    STATUS["TheHive"]="SKIPPED"
    echo -e "${YELLOW}[WARN ]${NC} TheHive skipped (use --with-thehive=true to enable)" | tee -a "$LOG_FILE"
    return 0
  fi
  q apt-get install -y cassandra || { status_fail "TheHive" "Cassandra install failed"; return 0; }
  wget -qO /etc/apt/keyrings/strangebee.asc https://raw.githubusercontent.com/StrangeBee/packages/main/strangebee.gpg || true
  echo "deb https://deb.strangebee.com thehive-5.x main" > /etc/apt/sources.list.d/strangebee.list
  q apt-get update || true
  q apt-get install -y thehive || { status_fail "TheHive" "TheHive install failed"; return 0; }
  systemctl enable cassandra >> "$LOG_FILE" 2>&1 || true
  systemctl restart cassandra >> "$LOG_FILE" 2>&1 || true
  systemctl enable thehive >> "$LOG_FILE" 2>&1 || true
  if systemctl restart thehive >> "$LOG_FILE" 2>&1; then status_ok "TheHive"; else status_fail "TheHive" "service failed"; fi
}

write_landing_page() {
  mkdir -p /var/www/siemba
  cat > /var/www/siemba/index.html <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>SIEMBA</title>
  <style>
    body{font-family:Arial,Helvetica,sans-serif;background:#0b1320;color:#e7eefc;margin:0;padding:40px}
    h1{margin-top:0} a{color:#7cc4ff;text-decoration:none} .card{background:#121b2b;padding:24px;border-radius:12px;max-width:900px}
    li{margin:10px 0}
  </style>
</head>
<body>
  <div class="card">
    <h1>SIEMBA</h1>
    <p>Security Intelligence &amp; Event Management Battle Armor</p>
    <ul>
      <li><a href="/kibana/">Open Kibana</a></li>
      <li><a href="/grafana/">Open Grafana</a></li>
    </ul>
  </div>
</body>
</html>
EOF
}

setup_nginx() {
  register_section "Nginx"
  step "Configuring Nginx and browser TLS"
  write_landing_page

  backup_file /etc/nginx/sites-available/siemba
  local cert_path key_path fqdn
  fqdn="$DOMAIN"
  if [[ "$fqdn" == "localhost" || "$fqdn" == "127.0.0.1" || $(is_ip "$fqdn"; echo $?) -eq 0 || -z "$EMAIL" ]]; then
    TLS_MODE="self-signed"
    mkdir -p /etc/ssl/siemba
    cert_path="/etc/ssl/siemba/siemba.crt"
    key_path="/etc/ssl/siemba/siemba.key"
    if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
      openssl req -x509 -nodes -newkey rsa:4096 -days 825 \
        -keyout "$key_path" -out "$cert_path" \
        -subj "/CN=${fqdn:-localhost}" >> "$LOG_FILE" 2>&1
    fi
    cat > /etc/nginx/sites-available/siemba <<EOF
server {
    listen 80;
    server_name ${fqdn};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${fqdn};

    ssl_certificate ${cert_path};
    ssl_certificate_key ${key_path};

    root /var/www/siemba;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /kibana/ {
        proxy_pass http://127.0.0.1:5601/kibana/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /grafana/ {
        proxy_pass http://127.0.0.1:3000/grafana/;
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
    nginx -t >> "$LOG_FILE" 2>&1 || { status_fail "Nginx" "config test failed"; err "Nginx config test failed"; }
    systemctl enable nginx >> "$LOG_FILE" 2>&1 || true
    systemctl restart nginx >> "$LOG_FILE" 2>&1 || { status_fail "Nginx" "service failed"; err "Nginx failed to start"; }
  else
    TLS_MODE="letsencrypt"
    cat > /etc/nginx/sites-available/siemba <<EOF
server {
    listen 80;
    server_name ${fqdn};
    root /var/www/siemba;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /kibana/ {
        proxy_pass http://127.0.0.1:5601/kibana/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /grafana/ {
        proxy_pass http://127.0.0.1:3000/grafana/;
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
    nginx -t >> "$LOG_FILE" 2>&1 || { status_fail "Nginx" "config test failed"; err "Nginx config test failed"; }
    systemctl enable nginx >> "$LOG_FILE" 2>&1 || true
    systemctl restart nginx >> "$LOG_FILE" 2>&1 || { status_fail "Nginx" "service failed"; err "Nginx failed to start"; }
    certbot --nginx --non-interactive --agree-tos -m "$EMAIL" -d "$fqdn" --redirect >> "$LOG_FILE" 2>&1 || {
      warn "Let's Encrypt failed; keeping HTTP-only Nginx config."
      TLS_MODE="http-only"
    }
  fi
  status_ok "Nginx"
}

setup_firewall() {
  register_section "Firewall"
  step "Firewall"
  if [[ "$ENABLE_UFW" != "true" ]]; then
    STATUS["Firewall"]="SKIPPED"
    echo -e "${YELLOW}[WARN ]${NC} Firewall skipped (use --enable-ufw=true to enable UFW rules)" | tee -a "$LOG_FILE"
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

Public URL: https://${DOMAIN}
Kibana: https://${DOMAIN}/kibana/
Grafana: https://${DOMAIN}/grafana/

Elasticsearch:
  URL: https://127.0.0.1:9200
  CA: ${ES_CERT_DIR}/http_ca.crt
  User: elastic
  Password: ${ELASTIC_PASS}

Kibana service user:
  User: kibana_system
  Password: ${KIBANA_SYSTEM_PASS}

Grafana:
  URL: https://${DOMAIN}/grafana/
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
  echo "Elastic series: ${ELASTIC_SERIES}" | tee -a "$LOG_FILE"
  echo "Heap: ${ES_HEAP_GB:-n/a}g" | tee -a "$LOG_FILE"
  echo "TLS mode: ${TLS_MODE}" | tee -a "$LOG_FILE"
  echo "Public URL: https://${DOMAIN}" | tee -a "$LOG_FILE"
  echo "Kibana: https://${DOMAIN}/kibana/" | tee -a "$LOG_FILE"
  echo "Grafana: https://${DOMAIN}/grafana/" | tee -a "$LOG_FILE"
  echo "Credentials: /root/siemba-credentials.txt" | tee -a "$LOG_FILE"
  echo "Log file: ${LOG_FILE}" | tee -a "$LOG_FILE"
}

main() {
  : > "$LOG_FILE"
  banner
  parse_args "$@"
  require_root
  detect_platform
  check_existing_state
  ensure_swap
  install_prereqs
  setup_system_tuning
  install_elastic_packages
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
  install_grafana
  install_thehive || true
  setup_nginx
  setup_firewall || true
  write_credentials
  print_summary
}

main "$@"
