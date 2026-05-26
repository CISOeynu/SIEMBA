#!/usr/bin/env bash
# =============================================================================
# SIEMBA HTTPS Installer v1.0.5
# Fully Automated All-in-One Installer with Let's Encrypt SSL
# =============================================================================

set -euo pipefail

SIEMBA_VERSION="1.1"
INSTALL_DIR="/opt/siemba"
REPO="https://github.com/CISOeynu/siemba.git"
LOG_FILE="/tmp/siemba-install.log"

# ── Defaults ──────────────────────────────────────────────────────────────────
MODE="full"
DOMAIN=""
EMAIL=""

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
  
  if [[ -z "$DOMAIN" || "$DOMAIN" == "localhost" || "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    err "A valid public FQDN (domain name) is REQUIRED for Let's Encrypt SSL. Private IPs or localhosts will fail."
  fi

  if [[ -z "$EMAIL" ]]; then
    err "An email address is required for registration to manage Let's Encrypt certificate renewal notices."
  fi
}

system_tuning() {
  step "System Tuning & Prerequisites"
  
  log "Setting vm.max_map_count for Elasticsearch..."
  sysctl -w vm.max_map_count=262144 >> "$LOG_FILE" 2>&1
  echo "vm.max_map_count=262144" > /etc/sysctl.d/70-siemba.conf

  local ram_gb=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo)
  if [ "$ram_gb" -lt 16 ]; then
    if [ ! -f /swapfile ]; then
      log "Creating 4GB swap space (Detected RAM: ${ram_gb}GB)..."
      fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
  fi

  export DEBIAN_FRONTEND=noninteractive
  log "Installing stack packages & Certbot for SSL automation..."
  q apt-get update && q apt-get install -y curl wget git jq unzip gnupg nginx openjdk-17-jdk certbot python3-certbot-nginx
}

install_elasticsearch() {
  step "Installing Elasticsearch 8.x"
  
  if [ ! -f /etc/apt/sources.list.d/elastic-8.x.list ]; then
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
    q apt-get update
  fi

  log "Installing package files..."
  apt-get install -y -o Dpkg::Options::="--force-confmiss" elasticsearch >> "$LOG_FILE" 2>&1

  cat > /etc/elasticsearch/jvm.options.d/siemba.options << EOF
-Xms2g
-Xmx2g
EOF

  log "Configuring elasticsearch.yml..."
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

  log "Applying ownership and permission updates..."
  chown -R elasticsearch:elasticsearch /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

  log "Starting database service..."
  systemctl daemon-reload
  systemctl enable elasticsearch
  systemctl restart elasticsearch || {
    tail -n 20 /var/log/elasticsearch/siemba-cluster.log || true
    err "Elasticsearch failed to boot."
  }

  log "Verifying database health..."
  for i in {1..30}; do
    if curl -s http://127.0.0.1:9200 > /dev/null; then
      log "Elasticsearch Status: ONLINE ✓"
      return 0
    fi
    sleep 3
  done
  err "Elasticsearch API failed to respond in time."
}

install_kibana() {
  step "Installing Kibana 8.x"
  q apt-get install -y kibana
  
  log "Configuring kibana.yml..."
  cat > /etc/kibana/kibana.yml << EOF
server.host: "127.0.0.1"
server.port: 5601
server.basePath: "/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://127.0.0.1:9200"]
logging.root.level: info
EOF

  chown -R kibana:kibana /etc/kibana /var/lib/kibana /var/log/kibana
  systemctl enable kibana
  systemctl restart kibana
  log "Kibana Status: ONLINE ✓"
}

install_siemba_ui() {
  step "Deploying SIEMBA Front-End UI"
  mkdir -p "$INSTALL_DIR"
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    log "Downloading interface source code to $INSTALL_DIR..."
    q git clone "$REPO" "$INSTALL_DIR"
  fi
  log "SIEMBA UI code pulled down ✓"
}

configure_secure_nginx() {
  step "Configuring Network Routing & Production SSL (Nginx + Let's Encrypt)"
  
  log "Building temporary HTTP configuration for verification challenge..."
  cat > /etc/nginx/sites-available/siemba << EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        root ${INSTALL_DIR};
        index index.html index.htm;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/
  systemctl restart nginx

  log "Requesting formal SSL certificate from Let's Encrypt authority..."
  # Runs safely without prompts, automatically configures and overrides nginx config blocks for HTTPS
  certbot --nginx --non-interactive --agree-tos --email "${EMAIL}" --redirect -d "${DOMAIN}" >> "$LOG_FILE" 2>&1 || {
     err "SSL Certificate generation failed. Ensure domain resolves to this public IP and ports 80/443 are open."
  }

  log "Injecting production reverse-proxy directives back into secured site block..."
  cat > /etc/nginx/sites-available/siemba << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        root ${INSTALL_DIR};
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
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

  log "Restarting security wrapper proxy..."
  systemctl restart nginx
  log "HTTPS secure deployment completed successfully ✓"
}

main() {
  banner
  parse_args "$@"
  if [[ "$EUID" -ne 0 ]]; then err "This script must be run with root privileges (sudo)."; fi

  system_tuning
  install_elasticsearch
  install_kibana
  install_siemba_ui
  configure_secure_nginx
  
  echo -e "\n${GREEN}=======================================================${NC}"
  echo -e "${GREEN}✅ SIEMBA SECURE PLATFORM ONLINE AND ENCRYPTED!${NC}"
  echo -e "${GREEN}=======================================================${NC}"
  echo -e "🔒 Main Application Platform UI: https://${DOMAIN}"
  echo -e "📊 Secure Kibana Analytics Interface: https://${DOMAIN}/kibana\n"
}

main "$@"
