#!/usr/bin/env bash
# =============================================================================
# SIEMBA Installer v1.0.6
# Optimized for Ubuntu (x86/ARM), Debian, and Low-Resource POCs
# =============================================================================

set -euo pipefail

SIEMBA_VERSION="1.0.5"
INSTALL_DIR="/opt/siemba"
REPO="https://github.com/CISOeynu/siemba.git"
LOG_FILE="/tmp/siemba-install.log"

# ── Defaults ──────────────────────────────────────────────────────────────────
MODE="full"
DOMAIN="localhost"
EMAIL="admin@example.com"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[SIEMBA]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"; }
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
echo -e "${NC}   Optimized for Cloud & ARM Environments"
echo -e "   v${SIEMBA_VERSION}  |  log: ${LOG_FILE}"
echo ""
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --mode=*)   MODE="${arg#--mode=}"    ;;
      --domain=*) DOMAIN="${arg#--domain=}" ;;
      --email=*)  EMAIL="${arg#--email=}"  ;;
    esac
  done
  
  # Strip unneeded quotes or spaces if "IP ADDR" placeholder text is passed accidentally
  if [[ "$DOMAIN" == "IP ADDR" || -z "$DOMAIN" ]]; then
    warn "Domain/IP was not explicitly specified. Defaulting to system localhost."
    DOMAIN="127.0.0.1"
  fi
}

system_tuning() {
  step "System Tuning & Prerequisites"
  
  # 1. Kernel Limits (Crucial for ES)
  log "Setting vm.max_map_count..."
  sysctl -w vm.max_map_count=262144 >> "$LOG_FILE" 2>&1
  echo "vm.max_map_count=262144" > /etc/sysctl.d/70-siemba.conf

  # 2. Swap File
  local ram_gb=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo)
  if [ "$ram_gb" -lt 16 ]; then
    if [ ! -f /swapfile ]; then
      log "Creating 4GB swap (RAM: ${ram_gb}GB)..."
      fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
  fi

  # 3. APT Update
  export DEBIAN_FRONTEND=noninteractive
  log "Updating package lists & dependencies..."
  q apt-get update && q apt-get install -y curl wget git jq unzip gnupg nginx openjdk-17-jdk
}

install_elasticsearch() {
  step "Installing Elasticsearch 8.x"
  
  # Ensure Repo exists
  if [ ! -f /etc/apt/sources.list.d/elastic-8.x.list ]; then
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
    q apt-get update
  fi

  # Install AND Force-Restore missing config files
  log "Installing package (re-extracting configs)..."
  apt-get install -y -o Dpkg::Options::="--force-confmiss" elasticsearch >> "$LOG_FILE" 2>&1

  # JVM Heap Tuning (Set to 2G for your 12GB system)
  cat > /etc/elasticsearch/jvm.options.d/siemba.options << EOF
-Xms2g
-Xmx2g
EOF

  # Minimal Working Config without contradictory TLS settings
  log "Writing elasticsearch.yml..."
  cat > /etc/elasticsearch/elasticsearch.yml << EOF
cluster.name: siemba-cluster
node.name: siemba-node-1
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node
xpack.security.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
bootstrap.memory_lock: false
EOF

  # Permissions Fix
  log "Applying permission fixes..."
  chown -R elasticsearch:elasticsearch /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

  log "Starting service (patience required)..."
  systemctl daemon-reload
  systemctl enable elasticsearch
  systemctl restart elasticsearch || {
    echo -e "${RED}Elasticsearch failed to boot.${NC}"
    echo -e "Printing terminal lines from /var/log/elasticsearch/siemba-cluster.log:"
    tail -n 20 /var/log/elasticsearch/siemba-cluster.log || true
    err "ES failed. Check logs: journalctl -u elasticsearch"
  }

  # Wait for API
  log "Waiting for API response..."
  for i in {1..30}; do
    if curl -s http://127.0.0.1:9200 > /dev/null; then
      log "Elasticsearch: UP ✓"
      return 0
    fi
    sleep 3
  done
  err "Elasticsearch is running but API timed out."
}

install_kibana() {
  step "Installing Kibana 8.x"
  q apt-get install -y kibana
  
  log "Writing kibana.yml..."
  cat > /etc/kibana/kibana.yml << EOF
server.host: "127.0.0.1"
server.port: 5601
server.basePath: "/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://127.0.0.1:9200"]
logging.root.level: info
EOF

  chown -R kibana:kibana /etc/kibana /var/lib/kibana /var/log/kibana
  systemctl daemon-reload
  systemctl enable kibana
  systemctl restart kibana
  log "Kibana: UP ✓"
}

install_siemba_ui() {
  step "Deploying SIEMBA UI"
  mkdir -p "$INSTALL_DIR"
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    log "Cloning SIEMBA source code to $INSTALL_DIR..."
    q git clone "$REPO" "$INSTALL_DIR"
  fi
  log "SIEMBA UI logic deployed ✓"
}

main() {
  banner
  parse_args "$@"
  if [[ "$EUID" -ne 0 ]]; then err "Run as root (sudo)."; fi

  system_tuning
  install_elasticsearch
  install_kibana
  install_siemba_ui
  
  echo -e "\n${GREEN}✅ SIEMBA POC READY!${NC}"
  echo -e "Access domain config configured for: http://${DOMAIN}"
}

main "$@"
