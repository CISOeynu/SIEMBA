#!/usr/bin/env bash
# =============================================================================
# SIEMBA Installer v1.0
# Supported: Ubuntu 22.04/24.04, macOS 13+
# Usage:
#   Full:   curl -fsSL .../install.sh | sudo bash -s -- --mode=full
#   Docker: curl -fsSL .../install.sh | sudo bash -s -- --mode=docker
# =============================================================================
set -euo pipefail

SIEMBA_VERSION="1.0.0"
INSTALL_DIR="/opt/siemba"
LOG_FILE="/tmp/siemba-install.log"
MODE="${MODE:-}"
DOMAIN="" EMAIL="" ADMIN_PASS="" PLATFORM="" PKG_MANAGER=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[SIEMBA]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[ERROR]${NC}  $*" | tee -a "$LOG_FILE"; exit 1; }
step() { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━${NC}\n" | tee -a "$LOG_FILE"; }
q()    { "$@" >> "$LOG_FILE" 2>&1; }

banner() {
cat << 'EOF'

   ███████╗██╗███████╗███╗   ███╗██████╗  █████╗
   ██╔════╝██║██╔════╝████╗ ████║██╔══██╗██╔══██╗
   ███████╗██║█████╗  ██╔████╔██║██████╔╝███████║
   ╚════██║██║██╔══╝  ██║╚██╔╝██║██╔══██╗██╔══██║
   ███████║██║███████╗██║ ╚═╝ ██║██████╔╝██║  ██║
   ╚══════╝╚═╝╚══════╝╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝
   Security Intelligence & Event Management Battle Armor
EOF
echo -e "   v${SIEMBA_VERSION}  |  log: ${LOG_FILE}\n"
}

detect_platform() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macos"; PKG_MANAGER="brew"
  elif [[ -f /etc/os-release ]]; then
    source /etc/os-release; PLATFORM="linux"
    command -v apt-get &>/dev/null && PKG_MANAGER="apt" || err "Need Ubuntu 22.04+ or macOS 13+"
  else
    err "Unsupported platform"
  fi
  log "Platform: $PLATFORM"
}

prompt_config() {
  echo ""
  read -rp "  Domain (press Enter for localhost): " DOMAIN
  [[ -z "$DOMAIN" ]] && DOMAIN="localhost"
  read -rp "  Admin email (for Let's Encrypt): " EMAIL
  [[ -z "$EMAIL" ]] && EMAIL="admin@example.com"
  if [[ -z "$MODE" ]]; then
    echo ""; echo "  1) Full native install (16+ GB RAM recommended)"
    echo "  2) Docker install (8+ GB RAM)"
    read -rp "  Choice [1/2]: " c
    [[ "$c" == "2" ]] && MODE="docker" || MODE="full"
  fi
  ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9!@#' | head -c 20)
  log "Config: domain=$DOMAIN mode=$MODE"
}

prereqs_linux() {
  step "System prerequisites"
  q apt-get update
  q apt-get install -y curl wget git jq unzip gnupg lsb-release ca-certificates \
    software-properties-common apt-transport-https certbot python3-certbot-nginx \
    nginx ufw openssl python3 python3-pip build-essential
  # Java 17
  java -version &>/dev/null 2>&1 || q apt-get install -y openjdk-17-jdk
  # Node 20
  node --version 2>/dev/null | grep -q "^v20" || {
    q curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    q apt-get install -y nodejs
  }
  log "Java: $(java -version 2>&1 | head -1)"
  log "Node: $(node --version)"
}

prereqs_macos() {
  step "macOS prerequisites"
  command -v brew &>/dev/null || \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  q brew install curl wget git jq node@20 openjdk@17 nginx certbot
}

prereqs_docker() {
  step "Docker prerequisites"
  if [[ "$PLATFORM" == "linux" ]]; then
    command -v docker &>/dev/null || {
      q apt-get install -y ca-certificates curl gnupg
      curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1
      systemctl enable docker && systemctl start docker
    }
  else
    docker info &>/dev/null 2>&1 || err "Start Docker Desktop first, then re-run."
  fi
  log "Docker: $(docker --version)"
}

install_elasticsearch() {
  step "Elasticsearch 8.x"
  dpkg -l elasticsearch &>/dev/null 2>&1 || {
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch \
      | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" \
      > /etc/apt/sources.list.d/elastic-8.x.list
    q apt-get update && q apt-get install -y elasticsearch
  }
  RAM_GB=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo)
  HEAP=$(( RAM_GB / 4 )); [[ $HEAP -lt 1 ]] && HEAP=1; [[ $HEAP -gt 32 ]] && HEAP=32
  cat > /etc/elasticsearch/jvm.options.d/siemba.options << EOF
-Xms${HEAP}g
-Xmx${HEAP}g
EOF
  cat >> /etc/elasticsearch/elasticsearch.yml << 'ES'
cluster.name: siemba-cluster
node.name: siemba-node-1
network.host: 127.0.0.1
xpack.security.enabled: false
bootstrap.memory_lock: true
ES
  systemctl enable elasticsearch && systemctl start elasticsearch
  sleep 15
  curl -sf http://localhost:9200 >> "$LOG_FILE" 2>&1 && log "Elasticsearch: OK" || warn "Still starting..."
}

install_kibana() {
  step "Kibana 8.x"
  q apt-get install -y kibana
  cat >> /etc/kibana/kibana.yml << 'KB'
server.host: "127.0.0.1"
server.port: 5601
server.basePath: "/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://127.0.0.1:9200"]
KB
  systemctl enable kibana && systemctl start kibana
  log "Kibana: running :5601"
}

install_logstash() {
  step "Logstash 8.x"
  q apt-get install -y logstash
  [[ -d "$INSTALL_DIR/config/logstash/pipelines" ]] && \
    cp "$INSTALL_DIR"/config/logstash/pipelines/*.conf /etc/logstash/conf.d/ 2>/dev/null || \
    cat > /etc/logstash/conf.d/01-syslog.conf << 'LS'
input {
  syslog { port => 5514; type => "syslog" }
  tcp    { port => 5000; type => "tcp-input"; codec => "json_lines" }
  http   { port => 8080; type => "http-input" }
}
filter {
  mutate { add_field => { "siemba_ingest_time" => "%{@timestamp}" } }
  if [type] == "syslog" { mutate { add_field => { "source_integration" => "syslog" } } }
}
output {
  elasticsearch {
    hosts => ["http://127.0.0.1:9200"]
    index => "siemba-%{[source_integration]:-generic}-%{+YYYY.MM.dd}"
  }
}
LS
  systemctl enable logstash && systemctl start logstash
  log "Logstash: running, syslog :5514"
}

install_grafana() {
  step "Grafana OSS"
  wget -qO - https://packages.grafana.com/gpg.key \
    | gpg --dearmor > /usr/share/keyrings/grafana.key 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://packages.grafana.com/oss/deb stable main" \
    > /etc/apt/sources.list.d/grafana.list
  q apt-get update && q apt-get install -y grafana
  sed -i "s|;http_port = 3000|http_port = 3001|" /etc/grafana/grafana.ini
  sed -i "s|;root_url = .*|root_url = %(protocol)s://%(domain)s/grafana/|" /etc/grafana/grafana.ini
  sed -i "s|;serve_from_sub_path = false|serve_from_sub_path = true|" /etc/grafana/grafana.ini
  systemctl enable grafana-server && systemctl start grafana-server
  log "Grafana: running :3001"
}

install_thehive() {
  step "TheHive 5"
  wget -qO /etc/apt/trusted.gpg.d/strangebee.gpg \
    https://raw.githubusercontent.com/StrangeBee/packages/main/strangebee.gpg 2>/dev/null || \
    { warn "TheHive GPG fetch failed — skipping"; return 0; }
  echo "deb https://deb.strangebee.com thehive-5.x main" > /etc/apt/sources.list.d/strangebee.list
  q apt-get update && q apt-get install -y thehive || warn "TheHive install failed — add manually later"
  systemctl enable thehive 2>/dev/null || true
  systemctl start thehive  2>/dev/null || true
  log "TheHive: done"
}

install_security_tools() {
  step "Security tools (Nuclei, Metasploit, Sn1per)"
  # Go + Nuclei
  command -v go &>/dev/null || {
    wget -qO /tmp/go.tar.gz "https://go.dev/dl/go1.22.3.linux-amd64.tar.gz"
    tar -C /usr/local -xzf /tmp/go.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> /etc/profile.d/go.sh
  }
  /usr/local/go/bin/go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest >> "$LOG_FILE" 2>&1 || warn "Nuclei failed"
  ln -sf "$HOME/go/bin/nuclei" /usr/local/bin/nuclei 2>/dev/null || true
  nuclei -update-templates -silent 2>/dev/null || true
  # Metasploit
  command -v msfconsole &>/dev/null || {
    curl -fsSL "https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb" \
      -o /tmp/msf_install.sh && chmod +x /tmp/msf_install.sh
    /tmp/msf_install.sh >> "$LOG_FILE" 2>&1 || warn "Metasploit failed — install from metasploit.com"
  }
  # Sn1per
  [[ -d /opt/sniper ]] || {
    git clone https://github.com/1N3/Sn1per.git /opt/sniper >> "$LOG_FILE" 2>&1
    cd /opt/sniper && bash install.sh >> "$LOG_FILE" 2>&1 || warn "Sn1per failed"
  }
  log "Security tools: done"
}

install_siemba_ui() {
  step "SIEMBA UI"
  mkdir -p "$INSTALL_DIR"
  [[ -d "./siemba-ui" ]] && cp -r . "$INSTALL_DIR/" 2>/dev/null || \
    git clone --depth 1 https://github.com/YOUR_ORG/siemba.git "$INSTALL_DIR" >> "$LOG_FILE" 2>&1 || \
    warn "Could not clone repo — deploy siemba-ui to $INSTALL_DIR manually"
  cd "$INSTALL_DIR/siemba-ui" 2>/dev/null || return
  npm install --omit=dev --silent >> "$LOG_FILE" 2>&1
  npm run build --silent >> "$LOG_FILE" 2>&1 || true
  cat > "$INSTALL_DIR/siemba-ui/.env" << EOF
NODE_ENV=production
PORT=3000
JWT_SECRET=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)
ADMIN_INITIAL_PASSWORD=$ADMIN_PASS
ES_HOST=http://127.0.0.1:9200
THEHIVE_URL=http://127.0.0.1:9000
SIEMBA_DOMAIN=$DOMAIN
EOF
  useradd -r -s /sbin/nologin siemba 2>/dev/null || true
  chown -R siemba:siemba "$INSTALL_DIR"
  cat > /etc/systemd/system/siemba-ui.service << EOF
[Unit]
Description=SIEMBA Web Interface
After=network.target elasticsearch.service
[Service]
Type=simple
User=siemba
WorkingDirectory=$INSTALL_DIR/siemba-ui
ExecStart=/usr/bin/node src/server/server.js
Restart=on-failure
RestartSec=5
EnvironmentFile=$INSTALL_DIR/siemba-ui/.env
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable siemba-ui && systemctl start siemba-ui
  log "SIEMBA UI: running :3000"
}

setup_tls() {
  step "HTTPS / TLS"
  local cert key
  if [[ "$DOMAIN" == "localhost" || "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    warn "No public domain — self-signed certificate"
    mkdir -p /etc/siemba/ssl
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout /etc/siemba/ssl/siemba.key \
      -out    /etc/siemba/ssl/siemba.crt \
      -subj   "/C=US/O=SIEMBA/CN=$DOMAIN" >> "$LOG_FILE" 2>&1
    cert="/etc/siemba/ssl/siemba.crt"; key="/etc/siemba/ssl/siemba.key"
  else
    log "Requesting Let's Encrypt for $DOMAIN"
    certbot certonly --nginx --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN" >> "$LOG_FILE" 2>&1
    cert="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    key="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo "0 3 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" > /etc/cron.d/siemba-certbot
  fi
  cat > /etc/nginx/sites-available/siemba << NGINX
upstream siemba_ui   { server 127.0.0.1:3000; }
upstream siemba_kib  { server 127.0.0.1:5601; }
upstream siemba_grf  { server 127.0.0.1:3001; }
upstream siemba_hive { server 127.0.0.1:9000; }

server { listen 80; server_name $DOMAIN; return 301 https://\$host\$request_uri; }

server {
    listen 443 ssl http2; server_name $DOMAIN;
    ssl_certificate $cert; ssl_certificate_key $key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    client_max_body_size 50M;

    location / {
        proxy_pass http://siemba_ui;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600;
    }
    location /kibana/  { proxy_pass http://siemba_kib/;  proxy_set_header Host \$host; }
    location /grafana/ { proxy_pass http://siemba_grf/;  proxy_set_header Host \$host; }
    location /cases/   { proxy_pass http://siemba_hive/; proxy_set_header Host \$host; }
    location /api/tools/stream/ {
        proxy_pass http://siemba_ui;
        proxy_buffering off; proxy_cache off;
        proxy_set_header Connection ''; proxy_http_version 1.1;
    }
}
NGINX
  ln -sf /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/siemba
  rm -f /etc/nginx/sites-enabled/default
  nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx
  log "Nginx: HTTPS configured"
}

configure_firewall() {
  step "Firewall"
  command -v ufw &>/dev/null || return
  ufw allow 22/tcp    >> "$LOG_FILE" 2>&1
  ufw allow 80/tcp    >> "$LOG_FILE" 2>&1
  ufw allow 443/tcp   >> "$LOG_FILE" 2>&1
  ufw allow 5514/udp  >> "$LOG_FILE" 2>&1
  ufw allow 5514/tcp  >> "$LOG_FILE" 2>&1
  ufw --force enable  >> "$LOG_FILE" 2>&1
  log "UFW enabled"
}

install_docker_stack() {
  step "Docker stack"
  mkdir -p "$INSTALL_DIR"
  [[ -f "./docker-compose.yml" ]] && cp -r . "$INSTALL_DIR/" || \
    git clone --depth 1 https://github.com/YOUR_ORG/siemba.git "$INSTALL_DIR" >> "$LOG_FILE" 2>&1
  cd "$INSTALL_DIR"
  cp .env.example .env
  JWT=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)
  sed -i "s/REPLACE_WITH_64_CHAR_RANDOM_STRING/$JWT/" .env
  sed -i "s/SIEMBA_DOMAIN=.*/SIEMBA_DOMAIN=$DOMAIN/" .env
  sed -i "s/ADMIN_INITIAL_PASSWORD=.*/ADMIN_INITIAL_PASSWORD=$ADMIN_PASS/" .env
  docker compose pull >> "$LOG_FILE" 2>&1
  docker compose up -d >> "$LOG_FILE" 2>&1
  log "Docker stack: all containers started"
}

print_summary() {
  local url="https://$DOMAIN"
  mkdir -p "$INSTALL_DIR"
  printf "URL: %s\nUsername: admin\nPassword: %s\n" "$url" "$ADMIN_PASS" > "$INSTALL_DIR/.credentials"
  chmod 600 "$INSTALL_DIR/.credentials"
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║${NC}  ${BOLD}SIEMBA is ready!${NC}"
  echo -e "${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}  URL:      ${BLUE}$url${NC}"
  echo -e "${GREEN}║${NC}  Username: admin"
  echo -e "${GREEN}║${NC}  Password: ${YELLOW}$ADMIN_PASS${NC}"
  echo -e "${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}  ${RED}SAVE THE PASSWORD — shown only once!${NC}"
  echo -e "${GREEN}║${NC}  Saved to: $INSTALL_DIR/.credentials"
  echo -e "${GREEN}║${NC}  Log:      $LOG_FILE"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
}

main() {
  banner
  [[ "$EUID" -ne 0 && "$OSTYPE" != "darwin"* ]] && err "Run as root: sudo bash install.sh"
  detect_platform
  prompt_config
  if [[ "$MODE" == "docker" ]]; then
    prereqs_docker; install_docker_stack; setup_tls
  else
    [[ "$PLATFORM" == "linux" ]] && prereqs_linux || prereqs_macos
    install_elasticsearch; install_kibana; install_logstash
    install_grafana; install_thehive; install_siemba_ui
    install_security_tools; setup_tls; configure_firewall
  fi
  print_summary
}

for arg in "$@"; do
  case $arg in --mode=full) MODE="full" ;; --mode=docker) MODE="docker" ;; esac
done
main "$@"
