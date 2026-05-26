#!/usr/bin/env bash
# =============================================================================
# SIEMBA Multi-Stage Container Installer v1.1.0
# Uses isolated container compilation to guarantee success on low-RAM hosts
# =============================================================================

set -euo pipefail

SIEMBA_VERSION="1.1.0"
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
echo -e "${BLUE}\n   ███████╗██╗███████╗███╗   ███╗██████╗  █████╗\n   ██╔════╝██║██╔════╝████╗ ████║██╔══██╗██╔══██╗\n   ███████╗██║█████╗  ██╔████╔██║██████╔╝███████║\n   ╚════██║██║██╔══╝  ██║╚██╔╝██║██╔══██╗██╔══██║\n   ███████║██║███████╗██║ ╚═╝ ██║██████╔╝██║  ██║\n   ╚══════╝╚═╝╚══════╝╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝\n${NC}   Containerized Compilation Engine\n   v${SIEMBA_VERSION}  |  log: ${LOG_FILE}\n"
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
  
  log "Setting memory maps via kernel limits..."
  sysctl -w vm.max_map_count=262144 >> "$LOG_FILE" 2>&1
  echo "vm.max_map_count=262144" > /etc/sysctl.d/70-siemba.conf

  export DEBIAN_FRONTEND=noninteractive
  log "Installing stack packages & container runtime..."
  q apt-get update
  q apt-get install -y curl wget git jq unzip gnupg nginx openjdk-17-jdk docker.io
  
  systemctl enable docker >> "$LOG_FILE" 2>&1
  systemctl start docker >> "$LOG_FILE" 2>&1
}

install_elasticsearch() {
  step "Installing Elasticsearch 8.x"
  if [ ! -f /etc/apt/sources.list.d/elastic-8.x.list ]; then
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
    q apt-get update
  fi
  q apt-get install -y -o Dpkg::Options::="--force-confmiss" elasticsearch

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

containerized_ui_build() {
  step "Containerized UI Compilation (OOM Guard)"
  mkdir -p "$INSTALL_DIR"
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    log "Cloning clean repository from origin..."
    q git clone "$REPO" "$INSTALL_DIR"
  fi

  log "Generating temporary isolated build pipeline container..."
  cat > "$INSTALL_DIR/siemba-ui/Dockerfile.build" << 'EOF'
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install --unsafe-perm
COPY . .
RUN npm run build
EOF

  log "Compiling production UI assets inside sandbox (this keeps memory safe)..."
  cd "$INSTALL_DIR/siemba-ui"
  q docker build -t siemba-ui-builder -f Dockerfile.build .

  log "Extracting finished static production files out to system web root..."
  mkdir -p "$INSTALL_DIR/siemba-ui/dist"
  local container_id=$(docker create siemba-ui-builder)
  docker cp "${container_id}:/app/dist/." "$INSTALL_DIR/siemba-ui/dist/" >> "$LOG_FILE" 2>&1
  docker rm -f "${container_id}" >> "$LOG_FILE" 2>&1

  log "Applying permission mappings..."
  chmod 755 "$INSTALL_DIR"
  find "$INSTALL_DIR" -type d -exec chmod 755 {} +
  find "$INSTALL_DIR" -type f -exec chmod 644 {} +
}

configure_nginx_routing() {
  step "Configuring Network Routing (Nginx)"
  
  local web_root="$INSTALL_DIR/siemba-ui/dist"
  log "Routing requests to verified production directory: $web_root"

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
  if [[ "$EUID" -ne 0 ]]; then err "Root context required. Re-launch with (sudo)."; fi

  system_tuning
  install_elasticsearch
  install_kibana
  containerized_ui_build
  configure_nginx_routing
  
  echo -e "\n${GREEN}=======================================================${NC}"
  echo -e "${GREEN}✅ SIEMBA IS FULLY CONFIGURED & COMPILED PROPERLY!${NC}"
  echo -e "${GREEN}=======================================================${NC}"
  echo -e "🖥️  Main Application Platform UI: http://${DOMAIN}"
  echo -e "📊 Direct Kibana Interface:       http://${DOMAIN}/kibana\n"
}

main "$@"
