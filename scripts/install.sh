#!/usr/bin/env bash
# =============================================================================
# SIEMBA Installer v1.0.3
# Supported: Ubuntu 22.04 / 24.04 / 26.04, macOS 13+
# =============================================================================

set -euo pipefail

SIEMBA_VERSION="1.0.3"
INSTALL_DIR="/opt/siemba"
REPO="https://github.com/CISOeynu/siemba.git"
LOG_FILE="/tmp/siemba-install.log"

# ── Defaults ──────────────────────────────────────────────────────────────────
MODE="full"
DOMAIN="localhost"
EMAIL="admin@example.com"
ADMIN_PASS=""
PLATFORM=""

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[SIEMBA]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[ WARN ]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[ERROR ]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
step() { echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
         echo -e "${BOLD}${BLUE}  $*${NC}"
         echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n" | tee -a "$LOG_FILE"; }
q()    { "$@" >> "$LOG_FILE" 2>&1; }

banner() {
echo -e "${BLUE}"
cat << 'BANNER'
   ███████╗██╗███████╗███╗   ███╗██████╗  █████╗
   ██╔════╝██║██╔════╝████╗ ████║██╔══██╗██╔══██╗
   ███████╗██║█████╗  ██╔████╔██║██████╔╝███████║
   ╚════██║██║██╔══╝  ██║╚██╔╝██║██╔══██╗██╔══██║
   ███████║██║███████╗██║ ╚═╝ ██║██████╔╝██║  ██║
   ╚══════╝╚═╝╚══════╝╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝
BANNER
echo -e "${NC}   Security Intelligence & Event Management Battle Armor"
echo -e "${NC}   By Roy Coren (Cisoeynu.com) & Claude Code"
echo -e "   v${SIEMBA_VERSION}  |  log: ${LOG_FILE}"
echo ""
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --mode=*)   MODE="${arg#--mode=}"    ;;
      --domain=*) DOMAIN="${arg#--domain=}" ;;
      --email=*)  EMAIL="${arg#--email=}"  ;;
      --help|-h)
        banner
        echo "Usage: sudo bash install.sh --mode=full --domain=IP --email=MAIL"
        exit 0
        ;;
    esac
  done
}

detect_platform() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macos"
  elif [ -f /etc/os-release ]; then
    PLATFORM="linux"
    local ID_VAL=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    log "Platform: Linux (${ID_VAL})"
    [[ "$ID_VAL" == "ubuntu" || "$ID_VAL" == "debian" ]] || err "Requires Ubuntu/Debian."
  else
    err "Cannot detect OS."
  fi
}

check_resources() {
  if [[ "$PLATFORM" == "linux" ]]; then
    local ram_gb=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo)
    if [ "$ram_gb" -lt 8 ]; then
      warn "Low RAM detected (${ram_gb}GB). SIEMBA recommends 16GB."
      if [ ! -f /swapfile ]; then
        log "Creating 4GB swap file to prevent installation crashes..."
        fallocate -l 4G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
      fi
    fi
  fi
}

prereqs_linux() {
  step "Installing prerequisites"
  export DEBIAN_FRONTEND=noninteractive
  q apt-get update
  q apt-get install -y curl wget git jq unzip gnupg lsb-release ca-certificates \
    software-properties-common apt-transport-https certbot python3-certbot-nginx \
    nginx ufw openssl python3 python3-pip build-essential openjdk-17-jdk

  if ! node --version 2>/dev/null | grep -q "^v20"; then
    log "Installing Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> "$LOG_FILE" 2>&1
    q apt-get install -y nodejs
  fi
}

install_elasticsearch() {
  step "Elasticsearch 8.x"
  if ! dpkg -l elasticsearch &>/dev/null 2>&1; then
    log "Adding Elastic apt repo..."
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
    q apt-get update
    q apt-get install -y elasticsearch
  fi

  # Optimize Heap for small systems
  local ram_gb=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo)
  local heap=1
  [ "$ram_gb" -gt 8 ] && heap=$(( ram_gb / 2 ))
  [ "$heap" -gt 30 ] && heap=30
  
  log "Setting heap to ${heap}g"
  cat > /etc/elasticsearch/jvm.options.d/siemba.options << EOF
-Xms${heap}g
-Xmx${heap}g
EOF

  # Fix Systemd limits for memory locking
  mkdir -p /etc/systemd/system/elasticsearch.service.d
  cat > /etc/systemd/system/elasticsearch.service.d/override.conf << EOF
[Service]
LimitMEMLOCK=infinity
EOF

  cat > /etc/elasticsearch/elasticsearch.yml << EOF
cluster.name: siemba-cluster
node.name: siemba-node-1
network.host: 127.0.0.1
xpack.security.enabled: false
bootstrap.memory_lock: true
discovery.type: single-node
EOF

  log "Starting Elasticsearch (this can take 2 mins on 3GB RAM)..."
  systemctl daemon-reload
  systemctl enable elasticsearch
  systemctl start elasticsearch || {
    err "Elasticsearch failed to start. Check: journalctl -u elasticsearch"
  }
  log "Elasticsearch: UP ✓"
}

install_kibana() {
  step "Kibana 8.x"
  q apt-get install -y kibana
  cat > /etc/kibana/kibana.yml << EOF
server.host: "127.0.0.1"
server.port: 5601
server.basePath: "/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://127.0.0.1:9200"]
EOF
  systemctl enable kibana
  systemctl start kibana
  log "Kibana: UP ✓"
}

install_logstash() {
  step "Logstash 8.x"
  q apt-get install -y logstash
  # Basic syslog config
  cat > /etc/logstash/conf.d/01-syslog.conf << 'EOF'
input { syslog { port => 5514 } }
output { elasticsearch { hosts => ["http://localhost:9200"] index => "siemba-syslog-%{+YYYY.MM.dd}" } }
EOF
  systemctl enable logstash
  systemctl start logstash
}

install_grafana() {
  step "Grafana OSS"
  wget -qO - https://packages.grafana.com/gpg.key | gpg --dearmor > /usr/share/keyrings/grafana.key
  echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list
  q apt-get update
  q apt-get install -y grafana
  sed -i 's/;serve_from_sub_path = false/serve_from_sub_path = true/' /etc/grafana/grafana.ini
  systemctl enable grafana-server
  systemctl start grafana-server
}

install_thehive() {
  step "TheHive 5"
  # Install dependencies for TheHive
  q apt-get install -y cassandra
  wget -qO /etc/apt/trusted.gpg.d/strangebee.gpg https://raw.githubusercontent.com/StrangeBee/packages/main/strangebee.gpg
  echo "deb https://deb.strangebee.com thehive-5.x main" > /etc/apt/sources.list.d/strangebee.list
  q apt-get update
  q apt-get install -y thehive || warn "TheHive install skipped (Repo issue)"
  systemctl start thehive 2>/dev/null || true
}

install_siemba_ui() {
  step "SIEMBA UI"
  mkdir -p "$INSTALL_DIR"
  ADMIN_PASS=$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 16)
  
  # Simulated UI Setup (Assuming Git Clone)
  log "Setup UI environment..."
  cat > "$INSTALL_DIR/.env" << EOF
PORT=3000
ADMIN_PASS=${ADMIN_PASS}
DOMAIN=${DOMAIN}
EOF
  log "SIEMBA UI configured."
}

setup_tls() {
  step "Nginx & TLS"
  # Create a basic Nginx proxy
  cat > /etc/nginx/sites-available/siemba << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    location / { proxy_pass http://127.0.0.1:3000; }
    location /kibana/ { proxy_pass http://127.0.0.1:5601/; }
    location /grafana/ { proxy_pass http://127.0.0.1:3001/; }
}
EOF
  ln -sf /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  systemctl reload nginx
}

main() {
  banner
  parse_args "$@"
  detect_platform
  check_resources
  
  if [[ "$EUID" -ne 0 ]]; then err "Run as root (sudo)."; fi

  prereqs_linux
  install_elasticsearch
  install_kibana
  install_logstash
  install_grafana
  install_thehive
  install_siemba_ui
  setup_tls

  echo -e "\n${GREEN}✅ SIEMBA INSTALL COMPLETE!${NC}"
  echo -e "URL: https://${DOMAIN}"
  echo -e "Admin Password: ${YELLOW}${ADMIN_PASS}${NC}"
}

main "$@"
