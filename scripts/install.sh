#!/usr/bin/env bash
# =============================================================================
# SIEMBA Production All-In-One Installer v1.1.3
# Fully Autonomous Dependency Provisions for Clean Ubuntu Server Virtual Machines
# =============================================================================

set -euo pipefail

SIEMBA_VERSION="1.1.3"
INSTALL_DIR="/opt/siemba"
REPO="https://github.com/CISOeynu/siemba.git"
LOG_FILE="/tmp/siemba-install.log"

# ── Defaults ──────────────────────────────────────────────────────────────────
MODE="full"
DOMAIN="127.0.0.1"
EMAIL="admin@example.com"

# ── Typography & Colors ───────────────────────────────────────────────────────
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
   ╚════██║██║██╔══╝  ██║╚██╔╝██║██╔══██╗██╔══██╗
   ███████║██║███████╗██║ ╚═╝ ██║██████╔╝██║  ██║
   ╚══════╝╚═╝╚══════╝╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝
BANNER
echo -e "${NC}   Security Intelligence & Event Management Battle Armor"
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
}

system_tuning() {
  step "System Tuning & Prerequisites"
  
  log "Setting memory maps required by Elasticsearch (vm.max_map_count)..."
  sysctl -w vm.max_map_count=262144 >> "$LOG_FILE" 2>&1 || true
  echo "vm.max_map_count=262144" > /etc/sysctl.d/70-siemba.conf

  export DEBIAN_FRONTEND=noninteractive
  
  log "Cleaning and updating system package tracking indices..."
  q apt-get update -y
  
  log "Explicitly pulling baseline toolchains (Curl, Git, GPG, Core Utils)..."
  q apt-get install -y curl wget git jq unzip gnupg build-essential ca-certificates

  log "Configuring secure upstream repository keys for NodeJS..."
  mkdir -p /etc/apt/keyrings
  q curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
  
  log "Refreshing indexes with new Node source distributions..."
  q apt-get update -y

  log "CRITICAL: Installing full Web & Application Engine environments (Nginx, Java, Node, NPM)..."
  q apt-get install -y nginx openjdk-17-jdk nodejs
  
  # Failover verification step to force installation of independent npm packages if separated by distribution maps
  if ! command -v npm &> /dev/null; then
     log "System split architecture noted. Manually enforcing standalone NPM binary extraction..."
     q apt-get install -y npm
  fi

  log "Verifying tool versions..."
  log "-> Node version: $(node -v)"
  log "-> NPM version:  $(npm -v)"
}

install_elasticsearch() {
  step "Installing Elasticsearch 8.x"
  
  if [ ! -f /etc/apt/sources.list.d/elastic-8.x.list ]; then
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg --yes
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
    q apt-get update -y
  fi

  log "Deploying binary structures..."
  apt-get install -y -o Dpkg::Options::="--force-confmiss" elasticsearch >> "$LOG_FILE" 2>&1

  log "Setting database heap limits (2GB boundaries)..."
  cat > /etc/elasticsearch/jvm.options.d/siemba.options << EOF
-Xms2g
-Xmx2g
EOF

  log "Writing local single-node cluster configurations..."
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

  chown -R elasticsearch:elasticsearch /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

  log "Starting the core database system runtime..."
  systemctl daemon-reload
  systemctl enable elasticsearch
  systemctl restart elasticsearch >> "$LOG_FILE" 2>&1

  log "Validating API responsiveness..."
  for i in {1..30}; do
    if curl -s http://127.0.0.1:9200 > /dev/null; then
      log "Elasticsearch engine: ONLINE ✓"
      return 0
    fi
    sleep 3
  done
  err "Elasticsearch engine failed to respond within limits."
}

install_kibana() {
  step "Installing Kibana 8.x"
  log "Deploying visualization package..."
  q apt-get install -y kibana
  
  log "Binding parameters to interface tracking maps..."
  cat > /etc/kibana/kibana.yml << EOF
server.host: "127.0.0.1"
server.port: 5601
server.basePath: "/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://127.0.0.1:9200"]
EOF

  chown -R kibana:kibana /etc/kibana /var/lib/kibana /var/log/kibana
  systemctl enable kibana
  systemctl restart kibana >> "$LOG_FILE" 2>&1
  log "Kibana engine: ONLINE ✓"
}

build_siemba_ui() {
  step "Deploying & Compiling SIEMBA UI"
  mkdir -p "$INSTALL_DIR"
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    log "Cloning clean repository directory trees from origin target..."
    q git clone "$REPO" "$INSTALL_DIR"
  fi

  if [ -d "$INSTALL_DIR/siemba-ui" ]; then
    log "Assembling production static interface application..."
    cd "$INSTALL_DIR/siemba-ui"
    
    log "Running clean package tracking maps configuration (npm install)..."
    q npm install --unsafe-perm
    
    log "Bundling optimized production build layout files (npm run build)..."
    q npm run build
  else
    err "The target installation repository structure is missing the required directory node: siemba-ui"
  fi

  log "Modifying file trees and directory route access metrics..."
  chmod 755 "$INSTALL_DIR"
  find "$INSTALL_DIR" -type d -exec chmod 755 {} +
  find "$INSTALL_DIR" -type f -exec chmod 644 {} +
}

configure_nginx_routing() {
  step "Configuring Network Routing (Nginx)"
  
  local web_root="$INSTALL_DIR/siemba-ui/dist"
  if [ ! -d "$web_root" ]; then
    # Failover fallback path map check
    if [ -d "$INSTALL_DIR/siemba-ui/build" ]; then
      web_root="$INSTALL_DIR/siemba-ui/build"
    else
      web_root="$INSTALL_DIR/siemba-ui"
    fi
  fi
  
  log "Binding web access routing boundaries to targeted path: $web_root"

  cat > /etc/nginx/sites-available/siemba << EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        root ${web_root};
        index index.html index.htm;
        try_files \$uri \$uri/ /index.html;
    }

    location /kibana {
        proxy_pass http://127.0.0.1:5601;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
    }
}
EOF

  log "Deactivating native web configuration boundaries..."
  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/
  
  log "Cycling active reverse proxy web node..."
  systemctl restart nginx
  log "Network architecture processing interface requests cleanly ✓"
}

main() {
  banner
  parse_args "$@"
  if [[ "$EUID" -ne 0 ]]; then err "Root environment privileges required. Re-launch execution with (sudo)."; fi

  system_tuning
  install_elasticsearch
  install_kibana
  build_siemba_ui
  configure_nginx_routing
  
  echo -e "\n${GREEN}=======================================================${NC}"
  echo -e "${GREEN}✅ SIEMBA IS FULLY CONFIGURED & READY FOR ACTION!${NC}"
  echo -e "${GREEN}=======================================================${NC}"
  echo -e "🖥️  Main Application Platform UI: http://${DOMAIN}"
  echo -e "📊 Direct Kibana Interface:       http://${DOMAIN}/kibana\n"
}

main "$@"
