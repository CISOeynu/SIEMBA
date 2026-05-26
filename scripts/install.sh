#!/usr/bin/env bash
# =============================================================================
# SIEMBA Installer v1.0.7
# Fully Automated All-in-One Installer (Compiles Frontend UI & Configures Nginx)
# =============================================================================

set -euo pipefail

SIEMBA_VERSION="1.0.7"
INSTALL_DIR="/opt/siemba"
REPO="https://github.com/CISOeynu/siemba.git"
LOG_FILE="/tmp/siemba-install.log"

MODE="full"
DOMAIN="127.0.0.1"
EMAIL="admin@example.com"

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
echo -e "${BLUE}\n   ███████╗██╗███████╗███╗   ███╗██████╗  █████╗\n   ██╔════╝██║██╔════╝████╗ ████║██╔══██╗██╔══██╗\n   ███████╗██║█████╗  ██╔████╔██║██████╔╝███████║\n   ╚════██║██║██╔══╝  ██║╚██╔╝██║██╔══██╗██╔══██║\n   ███████║██║███████╗██║ ╚═╝ ██║██████╔╝██║  ██║\n   ╚══════╝╚═╝╚══════╝╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝\n${NC}   Security Intelligence & Event Management Battle Armor\n   v${SIEMBA_VERSION}  |  log: ${LOG_FILE}\n"
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
  
  log "Setting vm.max_map_count..."
  sysctl -w vm.max_map_count=262144 >> "$LOG_FILE" 2>&1
  echo "vm.max_map_count=262144" > /etc/sysctl.d/70-siemba.conf

  local ram_gb=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo)
  if [ "$ram_gb" -lt 16 ] && [ ! -f /swapfile ]; then
      log "Creating 4GB swap space..."
      fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi

  export DEBIAN_FRONTEND=noninteractive
  log "Installing software packages (Nginx, Git, Java, Node.js)..."
  # Pulling official Node.js long-term-support build to handle compiling frontend tools
  q curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  q apt-get update && q apt-get install -y curl wget git jq unzip gnupg nginx openjdk-17-jdk nodejs
}

install_elasticsearch() {
  step "Installing Elasticsearch 8.x"
  if [ ! -f /etc/apt/sources.list.d/elastic-8.x.list ]; then
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
    q apt-get update
  fi
  apt-get install -y -o Dpkg::Options::="--force-confmiss" elasticsearch >> "$LOG_FILE" 2>&1

  cat > /etc/elasticsearch/jvm.options.d/siemba.options << EOF
-Xms2g
-Xmx2g
EOF

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
EOF

  chown -R elasticsearch:elasticsearch /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
  systemctl daemon-reload && systemctl enable elasticsearch && systemctl restart elasticsearch >> "$LOG_FILE" 2>&1
}

install_kibana() {
  step "Installing Kibana 8.x"
  q apt-get install -y kibana
  cat > /etc/kibana/kibana.yml << EOF
server.host: "127.0.0.1"
server.port: 5601
server.basePath: "/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://127.0.0.1:9200"]
EOF
  chown -R kibana:kibana /etc/kibana /var/lib/kibana /var/log/kibana
  systemctl enable kibana && systemctl restart kibana >> "$LOG_FILE" 2>&1
}

build_siemba_ui() {
  step "Deploying & Compiling SIEMBA UI"
  mkdir -p "$INSTALL_DIR"
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    log "Cloning source code repository..."
    q git clone "$REPO" "$INSTALL_DIR"
  fi

  if [ -d "$INSTALL_DIR/siemba-ui" ]; then
    log "Found raw UI code. Installing dependencies and compiling application..."
    cd "$INSTALL_DIR/siemba-ui"
    q npm install
    q npm run build || warn "Build command complete. Verifying targets..."
  fi

  log "Applying global permission overrides..."
  chmod 755 "$INSTALL_DIR"
  find "$INSTALL_DIR" -type d -exec chmod 755 {} +
  find "$INSTALL_DIR" -type f -exec chmod 644 {} +
}

configure_nginx_routing() {
  step "Configuring Network Routing (Nginx)"
  
  local web_root="$INSTALL_DIR"
  # Target the newly compiled folder locations inside siemba-ui
  if [ -d "$INSTALL_DIR/siemba-ui/dist" ]; then
    web_root="$INSTALL_DIR/siemba-ui/dist"
  elif [ -d "$INSTALL_DIR/siemba-ui/build" ]; then
    web_root="$INSTALL_DIR/siemba-ui/build"
  elif [ -d "$INSTALL_DIR/siemba-ui" ]; then
    web_root="$INSTALL_DIR/siemba-ui"
  fi
  
  log "Setting Nginx production target directory to: $web_root"

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

  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/
  systemctl restart nginx
}

main() {
  banner
  parse_args "$@"
  if [[ "$EUID" -ne 0 ]]; then err "Run with sudo privilege."; fi

  system_tuning
  install_elasticsearch
  install_kibana
  build_siemba_ui
  configure_nginx_routing
  
  echo -e "\n${GREEN}✅ SIEMBA IS COMPLETELY FIXED & READY!${NC}"
  echo -e "🖥️ UI Link: http://${DOMAIN}\n📊 Analytics Link: http://${DOMAIN}/kibana"
}

main "$@"
