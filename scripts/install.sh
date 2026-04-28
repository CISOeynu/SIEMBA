#!/usr/bin/env bash
# =============================================================================
# SIEMBA Installer v1.0.2
# Supported: Ubuntu 22.04 / 24.04, macOS 13+
#
# RECOMMENDED — pass all options so there are no prompts:
#
#   sudo bash install.sh --mode=full --domain=YOUR_IP_OR_DOMAIN --email=YOUR_EMAIL
#
# EXAMPLES:
#   sudo bash install.sh --mode=full   --domain=192.168.1.10        --email=admin@example.com
#   sudo bash install.sh --mode=docker --domain=siemba.company.com  --email=you@company.com
#   sudo bash install.sh --mode=full   --domain=localhost            --email=admin@example.com
#
# CURL ONE-LINER (pipe mode — must pass all three args):
#   curl -fsSL https://raw.githubusercontent.com/CISOeynu/siemba/main/scripts/install.sh \
#     | sudo bash -s -- --mode=full --domain=192.168.1.10 --email=admin@example.com
# =============================================================================

set -euo pipefail

SIEMBA_VERSION="1.0.2"
INSTALL_DIR="/opt/siemba"
REPO="https://github.com/CISOeynu/siemba.git"
LOG_FILE="/tmp/siemba-install.log"

# ── Defaults (overridden by --args) ──────────────────────────────────────────
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

# ── Banner ────────────────────────────────────────────────────────────────────
banner() {
echo ""
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
echo -e "${NC}   By Roy Coren(Cisoeynu.com) & Claude Code"
echo -e "   v${SIEMBA_VERSION}  |  log: ${LOG_FILE}"
echo ""
}

# ── Parse arguments ───────────────────────────────────────────────────────────
parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --mode=*)   MODE="${arg#--mode=}"    ;;
      --domain=*) DOMAIN="${arg#--domain=}" ;;
      --email=*)  EMAIL="${arg#--email=}"  ;;
      --help|-h)
        banner
        echo "Usage:  sudo bash install.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --mode=full       Full native install (default)"
        echo "  --mode=docker     Docker Compose install"
        echo "  --domain=DOMAIN   Your server IP or domain (default: localhost)"
        echo "  --email=EMAIL     Email for Let's Encrypt SSL (default: admin@example.com)"
        echo ""
        echo "Examples:"
        echo "  sudo bash install.sh --mode=full --domain=192.168.1.10 --email=admin@co.com"
        echo "  sudo bash install.sh --mode=docker --domain=siemba.co.com --email=you@co.com"
        echo ""
        echo "Pipe/curl mode:"
        echo "  curl -fsSL https://raw.githubusercontent.com/CISOeynu/siemba/main/scripts/install.sh \\"
        echo "    | sudo bash -s -- --mode=full --domain=192.168.1.10 --email=admin@example.com"
        exit 0
        ;;
    esac
  done
}

# ── Interactive prompts — only shown when no args given AND has a terminal ────
interactive_config() {
  # Only prompt if we have a real terminal
  if [ -t 1 ] && [ -t 0 ]; then
    echo -e "${BOLD}No arguments supplied — entering interactive mode.${NC}"
    echo -e "${YELLOW}Tip: next time run:  sudo bash install.sh --mode=full --domain=YOUR_IP --email=YOUR_EMAIL${NC}"
    echo ""

    echo -n "  Enter domain or IP address [localhost]: "
    read -r input_domain
    [ -n "$input_domain" ] && DOMAIN="$input_domain"

    echo -n "  Enter admin email for SSL cert [admin@example.com]: "
    read -r input_email
    [ -n "$input_email" ] && EMAIL="$input_email"

    echo ""
    echo "  Install type:"
    echo "    1) Full native install (recommended, needs 16 GB RAM)"
    echo "    2) Docker install (easier, needs 8 GB RAM)"
    echo -n "  Choice [1]: "
    read -r input_mode
    [ "$input_mode" = "2" ] && MODE="docker" || MODE="full"

    echo ""
  else
    # No terminal — use defaults and warn
    warn "No terminal detected and no --args supplied."
    warn "Using defaults: --mode=full --domain=localhost --email=admin@example.com"
    warn "For a real install, run:  sudo bash install.sh --mode=full --domain=YOUR_IP --email=YOUR_EMAIL"
    MODE="full"; DOMAIN="localhost"; EMAIL="admin@example.com"
  fi
}

# ── Platform detection ────────────────────────────────────────────────────────
detect_platform() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macos"
    log "Platform: macOS"
  elif [ -f /etc/os-release ]; then
    PLATFORM="linux"
    # Read without sourcing to avoid polluting env with set -u
    local ID_VAL
    ID_VAL=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    local VERSION_VAL
    VERSION_VAL=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' || echo "unknown")
    log "Platform: Linux (${ID_VAL} ${VERSION_VAL})"
    command -v apt-get &>/dev/null || err "SIEMBA requires Ubuntu 22.04+ (apt-based). Detected: ${ID_VAL}"
  else
    err "Cannot detect OS. Supported: Ubuntu 22.04/24.04, macOS 13+"
  fi
}

check_root() {
  if [[ "$PLATFORM" == "linux" && "$EUID" -ne 0 ]]; then
    err "Must run as root. Use: sudo bash install.sh --mode=${MODE} --domain=${DOMAIN} --email=${EMAIL}"
  fi
}

# ── Show and confirm config ───────────────────────────────────────────────────
confirm_config() {
  ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20)

  echo -e "\n${BOLD}━━━ Install Configuration ━━━${NC}"
  echo -e "  Mode   : ${BLUE}${MODE}${NC}"
  echo -e "  Domain : ${BLUE}${DOMAIN}${NC}"
  echo -e "  Email  : ${BLUE}${EMAIL}${NC}"
  echo ""

  log "Config: mode=${MODE} domain=${DOMAIN} email=${EMAIL}"

  # 5-second countdown only if interactive
  if [ -t 1 ] && [ -t 0 ]; then
    echo -e "${YELLOW}Starting in 5 seconds — press Ctrl+C to cancel.${NC}"
    for i in 5 4 3 2 1; do
      echo -ne "\r  ${i}... "
      sleep 1
    done
    echo ""
  else
    log "Non-interactive mode — starting immediately."
  fi
  echo ""
}

# ── Linux prerequisites ───────────────────────────────────────────────────────
prereqs_linux() {
  step "Installing prerequisites"
  export DEBIAN_FRONTEND=noninteractive
  q apt-get update
  q apt-get install -y \
    curl wget git jq unzip gnupg lsb-release ca-certificates \
    software-properties-common apt-transport-https \
    certbot python3-certbot-nginx \
    nginx ufw openssl python3 python3-pip build-essential

  # Java 17
  if ! java -version &>/dev/null 2>&1; then
    log "Installing Java 17..."
    q apt-get install -y openjdk-17-jdk
  fi

  # Node.js 20
  if ! node --version 2>/dev/null | grep -q "^v20"; then
    log "Installing Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> "$LOG_FILE" 2>&1
    q apt-get install -y nodejs
  fi

  log "Java  : $(java -version 2>&1 | head -1)"
  log "Node  : $(node --version)"
  log "Prerequisites: done"
}

prereqs_macos() {
  step "macOS prerequisites"
  command -v brew &>/dev/null || \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  q brew install curl wget git jq node@20 openjdk@17 nginx certbot
  log "macOS prerequisites: done"
}

prereqs_docker() {
  step "Docker"
  export DEBIAN_FRONTEND=noninteractive
  if [[ "$PLATFORM" == "linux" ]]; then
    if ! command -v docker &>/dev/null; then
      log "Installing Docker..."
      q apt-get install -y ca-certificates curl gnupg
      curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1
      systemctl enable docker
      systemctl start docker
    fi
    log "Docker: $(docker --version)"
  else
    docker info &>/dev/null 2>&1 || err "Start Docker Desktop first, then re-run."
  fi
}

# ── Elasticsearch ─────────────────────────────────────────────────────────────
install_elasticsearch() {
  step "Elasticsearch 8.x"
  if ! dpkg -l elasticsearch &>/dev/null 2>&1; then
    log "Adding Elastic apt repo..."
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch \
      | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
https://artifacts.elastic.co/packages/8.x/apt stable main" \
      > /etc/apt/sources.list.d/elastic-8.x.list
    q apt-get update
    q apt-get install -y elasticsearch
  fi

  local ram_gb heap
  ram_gb=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo)
  heap=$(( ram_gb / 4 ))
  [ "$heap" -lt 1 ] && heap=1
  [ "$heap" -gt 32 ] && heap=32
  log "Setting Elasticsearch heap to ${heap}g (RAM: ${ram_gb}g)"

  cat > /etc/elasticsearch/jvm.options.d/siemba.options << EOF
-Xms${heap}g
-Xmx${heap}g
EOF

  grep -q "siemba-cluster" /etc/elasticsearch/elasticsearch.yml 2>/dev/null || \
  cat >> /etc/elasticsearch/elasticsearch.yml << 'ES'
cluster.name: siemba-cluster
node.name: siemba-node-1
network.host: 127.0.0.1
xpack.security.enabled: false
bootstrap.memory_lock: true
ES

  systemctl enable elasticsearch
  systemctl start elasticsearch
  log "Elasticsearch starting — waiting up to 60s..."
  local n=0
  until curl -sf http://localhost:9200 >> "$LOG_FILE" 2>&1; do
    sleep 5
    n=$(( n + 1 ))
    [ "$n" -ge 12 ] && warn "Elasticsearch taking long — check: journalctl -u elasticsearch" && break
  done
  curl -sf http://localhost:9200 >> "$LOG_FILE" 2>&1 && log "Elasticsearch: UP ✓" || warn "Still starting..."
}

# ── Kibana ────────────────────────────────────────────────────────────────────
install_kibana() {
  step "Kibana 8.x"
  q apt-get install -y kibana
  grep -q "siemba-kibana" /etc/kibana/kibana.yml 2>/dev/null || \
  cat >> /etc/kibana/kibana.yml << 'KB'
server.host: "127.0.0.1"
server.port: 5601
server.name: "siemba-kibana"
server.basePath: "/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://127.0.0.1:9200"]
KB
  systemctl enable kibana
  systemctl start kibana
  log "Kibana: running on :5601 ✓"
}

# ── Logstash ──────────────────────────────────────────────────────────────────
install_logstash() {
  step "Logstash 8.x"
  q apt-get install -y logstash
  cat > /etc/logstash/conf.d/01-syslog.conf << 'LS'
input {
  syslog { port => 5514; type => "syslog" }
  tcp    { port => 5000; type => "tcp-input"; codec => "json_lines" }
  http   { port => 8080; type => "http-input" }
}
filter {
  mutate { add_field => { "siemba_ingest_time" => "%{@timestamp}" } }
  if [type] == "syslog" {
    mutate { add_field => { "source_integration" => "syslog" } }
  }
  if [severity] {
    if      [severity] <= 2 { mutate { add_field => { "siemba_severity" => "critical" } } }
    else if [severity] <= 4 { mutate { add_field => { "siemba_severity" => "high"     } } }
    else if [severity] <= 5 { mutate { add_field => { "siemba_severity" => "medium"   } } }
    else                    { mutate { add_field => { "siemba_severity" => "low"      } } }
  }
}
output {
  elasticsearch {
    hosts => ["http://127.0.0.1:9200"]
    index => "siemba-%{[source_integration]:-generic}-%{+YYYY.MM.dd}"
  }
}
LS
  systemctl enable logstash
  systemctl start logstash
  log "Logstash: running, syslog on :5514 ✓"
}

# ── Grafana ───────────────────────────────────────────────────────────────────
install_grafana() {
  step "Grafana OSS"
  wget -qO - https://packages.grafana.com/gpg.key \
    | gpg --dearmor > /usr/share/keyrings/grafana.key 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://packages.grafana.com/oss/deb stable main" \
    > /etc/apt/sources.list.d/grafana.list
  q apt-get update
  q apt-get install -y grafana
  sed -i "s|;http_port = 3000|http_port = 3001|"                           /etc/grafana/grafana.ini
  sed -i "s|;root_url = .*|root_url = %(protocol)s://%(domain)s/grafana/|" /etc/grafana/grafana.ini
  sed -i "s|;serve_from_sub_path = false|serve_from_sub_path = true|"      /etc/grafana/grafana.ini
  systemctl enable grafana-server
  systemctl start grafana-server
  log "Grafana: running on :3001 ✓"
}

# ── TheHive ───────────────────────────────────────────────────────────────────
install_thehive() {
  step "TheHive 5"
  wget -qO /etc/apt/trusted.gpg.d/strangebee.gpg \
    https://raw.githubusercontent.com/StrangeBee/packages/main/strangebee.gpg 2>/dev/null || {
    warn "TheHive GPG unavailable — skipping (install manually later)"
    return 0
  }
  echo "deb https://deb.strangebee.com thehive-5.x main" > /etc/apt/sources.list.d/strangebee.list
  q apt-get update
  q apt-get install -y thehive || { warn "TheHive install failed — skipping (add manually later)"; return 0; }
  systemctl enable thehive 2>/dev/null || true
  systemctl start  thehive 2>/dev/null || true
  log "TheHive: running on :9000 ✓"
}

# ── SIEMBA UI ─────────────────────────────────────────────────────────────────
install_siemba_ui() {
  step "SIEMBA UI (Node.js)"
  mkdir -p "$INSTALL_DIR"

  if [ ! -d "$INSTALL_DIR/siemba-ui" ]; then
    log "Cloning SIEMBA repo to ${INSTALL_DIR}..."
    git clone --depth 1 "$REPO" "$INSTALL_DIR" >> "$LOG_FILE" 2>&1 || {
      warn "git clone failed. Deploy siemba-ui manually to ${INSTALL_DIR}"
      mkdir -p "${INSTALL_DIR}/siemba-ui"
    }
  fi

  if [ -f "$INSTALL_DIR/siemba-ui/package.json" ]; then
    log "Installing Node.js dependencies..."
    cd "$INSTALL_DIR/siemba-ui"
    npm install --omit=dev --silent >> "$LOG_FILE" 2>&1
    log "Building frontend..."
    npm run build --silent >> "$LOG_FILE" 2>&1 || warn "Build step failed — server-only mode"
  fi

  local jwt_secret
  jwt_secret=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)

  cat > "$INSTALL_DIR/siemba-ui/.env" << EOF
NODE_ENV=production
PORT=3000
JWT_SECRET=${jwt_secret}
ADMIN_INITIAL_PASSWORD=${ADMIN_PASS}
ES_HOST=http://127.0.0.1:9200
THEHIVE_URL=http://127.0.0.1:9000
SIEMBA_DOMAIN=${DOMAIN}
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
WorkingDirectory=${INSTALL_DIR}/siemba-ui
ExecStart=/usr/bin/node src/server/server.js
Restart=on-failure
RestartSec=5
EnvironmentFile=${INSTALL_DIR}/siemba-ui/.env

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable siemba-ui
  systemctl start siemba-ui
  log "SIEMBA UI: running on :3000 ✓"
}

# ── Security tools ────────────────────────────────────────────────────────────
install_security_tools() {
  step "Security tools (Nuclei / Metasploit / Sn1per)"

  # Go + Nuclei
  if ! command -v go &>/dev/null; then
    log "Installing Go 1.22..."
    wget -qO /tmp/go.tar.gz "https://go.dev/dl/go1.22.3.linux-amd64.tar.gz"
    tar -C /usr/local -xzf /tmp/go.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> /etc/profile.d/siemba-go.sh
  fi
  export PATH=$PATH:/usr/local/go/bin

  log "Installing Nuclei..."
  go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest >> "$LOG_FILE" 2>&1 \
    && ln -sf "$HOME/go/bin/nuclei" /usr/local/bin/nuclei 2>/dev/null \
    && nuclei -update-templates -silent 2>/dev/null \
    || warn "Nuclei install failed — install manually later"

  log "Installing Metasploit..."
  command -v msfconsole &>/dev/null || {
    curl -fsSL "https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb" \
      -o /tmp/msf_install.sh 2>/dev/null \
    && chmod +x /tmp/msf_install.sh \
    && /tmp/msf_install.sh >> "$LOG_FILE" 2>&1 \
    || warn "Metasploit install failed — install from metasploit.com"
  }

  log "Installing Sn1per..."
  [ -d /opt/sniper ] || {
    git clone https://github.com/1N3/Sn1per.git /opt/sniper >> "$LOG_FILE" 2>&1
    cd /opt/sniper
    bash install.sh >> "$LOG_FILE" 2>&1 || warn "Sn1per install failed"
    cd -
  }

  log "Security tools: done ✓"
}

# ── TLS / Nginx ───────────────────────────────────────────────────────────────
setup_tls() {
  step "HTTPS / Nginx"
  local cert key

  if [[ "$DOMAIN" == "localhost" || "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    warn "No public domain supplied — generating self-signed certificate"
    warn "Your browser will show a security warning — click Advanced → Proceed"
    mkdir -p /etc/siemba/ssl
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout /etc/siemba/ssl/siemba.key \
      -out    /etc/siemba/ssl/siemba.crt \
      -subj   "/C=US/O=SIEMBA/CN=${DOMAIN}" >> "$LOG_FILE" 2>&1
    cert="/etc/siemba/ssl/siemba.crt"
    key="/etc/siemba/ssl/siemba.key"
  else
    log "Requesting Let's Encrypt certificate for ${DOMAIN}..."
    certbot certonly --nginx --non-interactive --agree-tos \
      -m "$EMAIL" -d "$DOMAIN" >> "$LOG_FILE" 2>&1
    cert="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    key="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
    echo "0 3 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" \
      > /etc/cron.d/siemba-certbot
  fi

  cat > /etc/nginx/sites-available/siemba << NGINX
upstream siemba_ui   { server 127.0.0.1:3000; }
upstream siemba_kib  { server 127.0.0.1:5601; }
upstream siemba_grf  { server 127.0.0.1:3001; }
upstream siemba_hive { server 127.0.0.1:9000; }

server {
    listen 80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name _;

    ssl_certificate     ${cert};
    ssl_certificate_key ${key};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    client_max_body_size 50M;

    # SIEMBA main UI + API
    location / {
        proxy_pass         http://siemba_ui;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600;
    }
    # Tool streaming (SSE)
    location /api/tools/stream/ {
        proxy_pass         http://siemba_ui;
        proxy_buffering    off;
        proxy_cache        off;
        proxy_set_header   Connection '';
        proxy_http_version 1.1;
        proxy_read_timeout 600;
    }
    # Embedded Kibana
    location /kibana/ {
        proxy_pass       http://siemba_kib/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
    # Embedded Grafana
    location /grafana/ {
        proxy_pass       http://siemba_grf/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
    # TheHive cases
    location /cases/ {
        proxy_pass       http://siemba_hive/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX

  ln -sf /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/siemba
  rm -f /etc/nginx/sites-enabled/default
  nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx
  log "Nginx: HTTPS configured ✓"
}

# ── Firewall ──────────────────────────────────────────────────────────────────
configure_firewall() {
  step "Firewall (UFW)"
  command -v ufw &>/dev/null || { log "ufw not found — skipping firewall config"; return; }
  ufw allow 22/tcp   comment "SSH"        >> "$LOG_FILE" 2>&1
  ufw allow 80/tcp   comment "HTTP"       >> "$LOG_FILE" 2>&1
  ufw allow 443/tcp  comment "HTTPS"      >> "$LOG_FILE" 2>&1
  ufw allow 5514/udp comment "Syslog UDP" >> "$LOG_FILE" 2>&1
  ufw allow 5514/tcp comment "Syslog TCP" >> "$LOG_FILE" 2>&1
  ufw --force enable >> "$LOG_FILE" 2>&1
  log "Firewall: UFW enabled ✓"
}

# ── Docker Compose stack ──────────────────────────────────────────────────────
install_docker_stack() {
  step "Docker Compose stack"
  mkdir -p "$INSTALL_DIR"

  if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
    log "Cloning SIEMBA repo..."
    git clone --depth 1 "$REPO" "$INSTALL_DIR" >> "$LOG_FILE" 2>&1
  fi

  cd "$INSTALL_DIR"
  cp .env.example .env

  local jwt
  jwt=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)
  sed -i "s|REPLACE_WITH_64_CHAR_RANDOM_STRING|${jwt}|"                      .env
  sed -i "s|SIEMBA_DOMAIN=.*|SIEMBA_DOMAIN=${DOMAIN}|"                       .env
  sed -i "s|ADMIN_INITIAL_PASSWORD=.*|ADMIN_INITIAL_PASSWORD=${ADMIN_PASS}|"  .env
  sed -i "s|LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${EMAIL}|"                 .env

  log "Pulling Docker images (this may take a few minutes)..."
  docker compose pull  >> "$LOG_FILE" 2>&1
  docker compose up -d >> "$LOG_FILE" 2>&1
  log "Docker stack: all containers started ✓"
}

# ── Final summary ─────────────────────────────────────────────────────────────
print_summary() {
  local url="https://${DOMAIN}"

  # Save credentials to file (root-readable only)
  mkdir -p "$INSTALL_DIR"
  cat > "$INSTALL_DIR/.credentials" << EOF
SIEMBA Credentials — installed $(date)
URL:      ${url}
Username: admin
Password: ${ADMIN_PASS}
EOF
  chmod 600 "$INSTALL_DIR/.credentials"

  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}   ${BOLD}✅  SIEMBA installation complete!${NC}                    ${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}   URL      : ${BLUE}${url}${NC}"
  echo -e "${GREEN}║${NC}   Username : ${BOLD}admin${NC}"
  echo -e "${GREEN}║${NC}   Password : ${YELLOW}${ADMIN_PASS}${NC}"
  echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}   ${RED}▲  SAVE THE PASSWORD ABOVE — shown only once!${NC}       ${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}   Credentials saved to : ${INSTALL_DIR}/.credentials    ${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}   Full install log     : ${LOG_FILE}           ${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  if [[ "$DOMAIN" == "localhost" || "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${YELLOW}Note: Self-signed certificate — browser will warn.${NC}"
    echo -e "      Click  ${BOLD}Advanced → Proceed to ${DOMAIN}${NC}  to continue."
    echo ""
  fi

  log "Installation complete. URL: ${url}"
}

# ── Entry point ───────────────────────────────────────────────────────────────
main() {
  # Clear log
  : > "$LOG_FILE"

  banner
  parse_args "$@"

  # If no args were given, try interactive prompts
  if [ "$MODE" = "full" ] && [ "$DOMAIN" = "localhost" ] && [ "$EMAIL" = "admin@example.com" ]; then
    # Check if args were explicitly passed or we're using defaults
    if [ "$#" -eq 0 ]; then
      interactive_config
    fi
  fi

  detect_platform
  check_root
  confirm_config

  if [ "$MODE" = "docker" ]; then
    prereqs_docker
    install_docker_stack
    setup_tls
  else
    if [ "$PLATFORM" = "linux" ]; then
      prereqs_linux
    else
      prereqs_macos
    fi
    install_elasticsearch
    install_kibana
    install_logstash
    install_grafana
    install_thehive
    install_siemba_ui
    install_security_tools
    setup_tls
    configure_firewall
  fi

  print_summary
}

main "$@"
