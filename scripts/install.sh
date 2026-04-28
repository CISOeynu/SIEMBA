#!/usr/bin/env bash
# =============================================================================
# SIEMBA Installer v1.0.1
# Supported: Ubuntu 22.04/24.04, macOS 13+
#
# PIPE MODE (non-interactive) — pass all args after --:
#   curl -fsSL .../install.sh | sudo bash -s -- --mode=full --domain=siemba.company.com --email=you@company.com
#   curl -fsSL .../install.sh | sudo bash -s -- --mode=docker --domain=localhost --email=admin@example.com
#
# DOWNLOADED MODE (interactive):
#   sudo bash install.sh
#   sudo bash install.sh --mode=full --domain=siemba.company.com --email=you@company.com
# =============================================================================
set -euo pipefail

SIEMBA_VERSION="1.0.1"
INSTALL_DIR="/opt/siemba"
LOG_FILE="/tmp/siemba-install.log"
REPO="https://github.com/CISOeynu/siemba.git"

# Defaults
MODE=""
DOMAIN=""
EMAIL=""
ADMIN_PASS=""
PLATFORM=""
PKG_MANAGER=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[SIEMBA]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[ERROR]${NC}  $*" | tee -a "$LOG_FILE"; exit 1; }
step() { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━${NC}\n" | tee -a "$LOG_FILE"; }
q()    { "$@" >> "$LOG_FILE" 2>&1; }

banner() {
cat << 'BANNER'

   ███████╗██╗███████╗███╗   ███╗██████╗  █████╗
   ██╔════╝██║██╔════╝████╗ ████║██╔══██╗██╔══██╗
   ███████╗██║█████╗  ██╔████╔██║██████╔╝███████║
   ╚════██║██║██╔══╝  ██║╚██╔╝██║██╔══██╗██╔══██║
   ███████║██║███████╗██║ ╚═╝ ██║██████╔╝██║  ██║
   ╚══════╝╚═╝╚══════╝╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝
   Security Intelligence & Event Management Battle Armor
BANNER
echo -e "   v${SIEMBA_VERSION}  |  log: ${LOG_FILE}\n"
}

# ── Detect pipe vs interactive ────────────────────────────────────────────────
is_piped() { ! [ -t 0 ]; }

# ── Parse --key=value arguments ───────────────────────────────────────────────
parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --mode=*)    MODE="${arg#--mode=}"     ;;
      --domain=*)  DOMAIN="${arg#--domain=}" ;;
      --email=*)   EMAIL="${arg#--email=}"   ;;
      --help|-h)
        echo ""
        echo "Usage: install.sh [OPTIONS]"
        echo ""
        echo "  --mode=full|docker   Install type (default: full)"
        echo "  --domain=DOMAIN      Your domain or IP (default: localhost)"
        echo "  --email=EMAIL        Admin email for Let's Encrypt (default: admin@example.com)"
        echo ""
        echo "Examples:"
        echo "  # Pipe mode — must pass all args:"
        echo "  curl -fsSL .../install.sh | sudo bash -s -- --mode=full --domain=siemba.co.com --email=you@co.com"
        echo ""
        echo "  # Downloaded mode — interactive or with args:"
        echo "  sudo bash install.sh"
        echo "  sudo bash install.sh --mode=docker --domain=192.168.1.10 --email=admin@example.com"
        exit 0
        ;;
    esac
  done
}

# ── Prompt helper — uses /dev/tty so it works when stdin is a pipe ────────────
prompt() {
  local msg="$1" varname="$2" default="$3"
  if is_piped; then
    # Running via curl|bash — no TTY, just use the default
    printf -v "$varname" '%s' "$default"
    log "  $msg → using default: $default"
  else
    # Running interactively — read from /dev/tty
    printf '%b' "${BLUE}[SIEMBA]${NC} ${msg} [${default}]: " >/dev/tty
    local answer
    read -r answer </dev/tty
    printf -v "$varname" '%s' "${answer:-$default}"
  fi
}

prompt_mode() {
  if is_piped; then
    [[ -z "$MODE" ]] && MODE="full"
    log "  Install type → using default: $MODE"
  else
    echo "" >/dev/tty
    echo -e "  ${BOLD}Install type:${NC}" >/dev/tty
    echo    "    1) Full native install (recommended, 16+ GB RAM)" >/dev/tty
    echo    "    2) Docker install (easier, 8+ GB RAM)" >/dev/tty
    printf '%b' "${BLUE}[SIEMBA]${NC} Choice [1/2, default=1]: " >/dev/tty
    local c; read -r c </dev/tty
    [[ "$c" == "2" ]] && MODE="docker" || MODE="full"
  fi
}

# ── Configuration setup ───────────────────────────────────────────────────────
setup_config() {
  [[ -z "$DOMAIN" ]] && prompt "Domain name (or Enter for localhost)" DOMAIN "localhost"
  [[ -z "$EMAIL"  ]] && prompt "Admin email (for Let's Encrypt SSL)"  EMAIL  "admin@example.com"
  [[ -z "$MODE"   ]] && prompt_mode

  # Sanitise mode
  case "$MODE" in
    full|docker) ;;
    *) warn "Unknown mode '$MODE', defaulting to 'full'"; MODE="full" ;;
  esac

  ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9!@#' | head -c 20)

  log "Configuration locked in:"
  log "  Domain : $DOMAIN"
  log "  Mode   : $MODE"
  log "  Email  : $EMAIL"

  echo ""
  echo -e "  ${BOLD}Domain :${NC} ${BLUE}$DOMAIN${NC}"
  echo -e "  ${BOLD}Mode   :${NC} ${BLUE}$MODE${NC}"
  echo -e "  ${BOLD}Email  :${NC} ${BLUE}$EMAIL${NC}"
  echo ""

  if ! is_piped; then
    echo -e "${YELLOW}Starting in 5 seconds — Ctrl+C to cancel${NC}"
    sleep 5
  fi
}

# ── Platform detection ────────────────────────────────────────────────────────
detect_platform() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macos"; PKG_MANAGER="brew"
  elif [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release; PLATFORM="linux"
    command -v apt-get &>/dev/null && PKG_MANAGER="apt" \
      || err "Unsupported distro — SIEMBA requires Ubuntu 22.04+ or macOS 13+"
  else
    err "Cannot detect OS platform"
  fi
  log "Platform: $PLATFORM ($PKG_MANAGER)"
}

check_root() {
  [[ "$PLATFORM" == "linux" && "$EUID" -ne 0 ]] && \
    err "Must run as root. Use: curl ... | sudo bash -s -- --mode=full --domain=... --email=..."
}

# ── Prerequisites ─────────────────────────────────────────────────────────────
prereqs_linux() {
  step "System prerequisites"
  export DEBIAN_FRONTEND=noninteractive
  q apt-get update
  q apt-get install -y \
    curl wget git jq unzip gnupg lsb-release ca-certificates \
    software-properties-common apt-transport-https \
    certbot python3-certbot-nginx \
    nginx ufw openssl python3 python3-pip build-essential

  java -version &>/dev/null 2>&1 || q apt-get install -y openjdk-17-jdk

  if ! node --version 2>/dev/null | grep -q "^v20"; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> "$LOG_FILE" 2>&1
    q apt-get install -y nodejs
  fi
  log "Java  : $(java -version 2>&1 | head -1)"
  log "Node  : $(node --version)"
}

prereqs_macos() {
  step "macOS prerequisites"
  command -v brew &>/dev/null || \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  q brew install curl wget git jq node@20 openjdk@17 nginx certbot
}

prereqs_docker() {
  step "Docker"
  export DEBIAN_FRONTEND=noninteractive
  if [[ "$PLATFORM" == "linux" ]]; then
    command -v docker &>/dev/null || {
      q apt-get install -y ca-certificates curl gnupg
      curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1
      systemctl enable docker && systemctl start docker
    }
    log "Docker: $(docker --version)"
  else
    docker info &>/dev/null 2>&1 || err "Start Docker Desktop first, then re-run."
  fi
}

# ── Services ──────────────────────────────────────────────────────────────────
install_elasticsearch() {
  step "Elasticsearch 8.x"
  dpkg -l elasticsearch &>/dev/null 2>&1 || {
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch \
      | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" \
      > /etc/apt/sources.list.d/elastic-8.x.list
    q apt-get update && q apt-get install -y elasticsearch
  }

  local ram_gb heap
  ram_gb=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo)
  heap=$(( ram_gb / 4 )); [[ $heap -lt 1 ]] && heap=1; [[ $heap -gt 32 ]] && heap=32
  cat > /etc/elasticsearch/jvm.options.d/siemba.options << EOF
-Xms${heap}g
-Xmx${heap}g
EOF
  grep -q "siemba-cluster" /etc/elasticsearch/elasticsearch.yml 2>/dev/null || cat >> /etc/elasticsearch/elasticsearch.yml << 'ES'
cluster.name: siemba-cluster
node.name: siemba-node-1
network.host: 127.0.0.1
xpack.security.enabled: false
bootstrap.memory_lock: true
ES
  systemctl enable elasticsearch && systemctl start elasticsearch
  log "Elasticsearch starting (30s warmup)..."
  local n=0
  until curl -sf http://localhost:9200 >> "$LOG_FILE" 2>&1 || (( n++ >= 12 )); do sleep 5; done
  curl -sf http://localhost:9200 >> "$LOG_FILE" 2>&1 && log "Elasticsearch: UP" || warn "Still starting — check $LOG_FILE"
}

install_kibana() {
  step "Kibana 8.x"
  q apt-get install -y kibana
  grep -q "siemba-kibana" /etc/kibana/kibana.yml 2>/dev/null || cat >> /etc/kibana/kibana.yml << 'KB'
server.host: "127.0.0.1"
server.port: 5601
server.name: "siemba-kibana"
server.basePath: "/kibana"
server.rewriteBasePath: true
elasticsearch.hosts: ["http://127.0.0.1:9200"]
KB
  systemctl enable kibana && systemctl start kibana
  log "Kibana: :5601"
}

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
  if [type] == "syslog" { mutate { add_field => { "source_integration" => "syslog" } } }
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
  systemctl enable logstash && systemctl start logstash
  log "Logstash: syslog :5514"
}

install_grafana() {
  step "Grafana OSS"
  wget -qO - https://packages.grafana.com/gpg.key \
    | gpg --dearmor > /usr/share/keyrings/grafana.key 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://packages.grafana.com/oss/deb stable main" \
    > /etc/apt/sources.list.d/grafana.list
  q apt-get update && q apt-get install -y grafana
  sed -i "s|;http_port = 3000|http_port = 3001|"                           /etc/grafana/grafana.ini
  sed -i "s|;root_url = .*|root_url = %(protocol)s://%(domain)s/grafana/|" /etc/grafana/grafana.ini
  sed -i "s|;serve_from_sub_path = false|serve_from_sub_path = true|"      /etc/grafana/grafana.ini
  systemctl enable grafana-server && systemctl start grafana-server
  log "Grafana: :3001"
}

install_thehive() {
  step "TheHive 5"
  wget -qO /etc/apt/trusted.gpg.d/strangebee.gpg \
    https://raw.githubusercontent.com/StrangeBee/packages/main/strangebee.gpg 2>/dev/null || {
    warn "TheHive GPG unavailable — skipping (install manually later)"; return 0
  }
  echo "deb https://deb.strangebee.com thehive-5.x main" > /etc/apt/sources.list.d/strangebee.list
  q apt-get update
  q apt-get install -y thehive || { warn "TheHive install failed — skipping"; return 0; }
  systemctl enable thehive 2>/dev/null || true
  systemctl start  thehive 2>/dev/null || true
  log "TheHive: :9000"
}

install_siemba_ui() {
  step "SIEMBA UI"
  mkdir -p "$INSTALL_DIR"
  if [[ ! -d "$INSTALL_DIR/siemba-ui" ]]; then
    git clone --depth 1 "$REPO" "$INSTALL_DIR" >> "$LOG_FILE" 2>&1 || {
      warn "git clone failed — UI will need to be deployed manually"; mkdir -p "$INSTALL_DIR/siemba-ui"
    }
  fi
  if [[ -f "$INSTALL_DIR/siemba-ui/package.json" ]]; then
    cd "$INSTALL_DIR/siemba-ui"
    npm install --omit=dev --silent >> "$LOG_FILE" 2>&1
    npm run build --silent          >> "$LOG_FILE" 2>&1 || true
  fi
  cat > "$INSTALL_DIR/siemba-ui/.env" << EOF
NODE_ENV=production
PORT=3000
JWT_SECRET=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)
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
  systemctl enable siemba-ui && systemctl start siemba-ui
  log "SIEMBA UI: :3000"
}

install_security_tools() {
  step "Security tools"
  command -v go &>/dev/null || {
    wget -qO /tmp/go.tar.gz "https://go.dev/dl/go1.22.3.linux-amd64.tar.gz"
    tar -C /usr/local -xzf /tmp/go.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> /etc/profile.d/go.sh
  }
  export PATH=$PATH:/usr/local/go/bin
  go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest >> "$LOG_FILE" 2>&1 \
    && ln -sf "$HOME/go/bin/nuclei" /usr/local/bin/nuclei 2>/dev/null \
    && nuclei -update-templates -silent 2>/dev/null \
    || warn "Nuclei install failed"

  command -v msfconsole &>/dev/null || {
    curl -fsSL "https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb" \
      -o /tmp/msf_install.sh 2>/dev/null && chmod +x /tmp/msf_install.sh \
      && /tmp/msf_install.sh >> "$LOG_FILE" 2>&1 \
      || warn "Metasploit install failed — install from metasploit.com"
  }

  [[ -d /opt/sniper ]] || {
    git clone https://github.com/1N3/Sn1per.git /opt/sniper >> "$LOG_FILE" 2>&1
    cd /opt/sniper && bash install.sh >> "$LOG_FILE" 2>&1 || warn "Sn1per failed"
    cd -
  }
  log "Security tools: done"
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
      -subj   "/C=US/O=SIEMBA/CN=${DOMAIN}" >> "$LOG_FILE" 2>&1
    cert="/etc/siemba/ssl/siemba.crt"; key="/etc/siemba/ssl/siemba.key"
  else
    log "Requesting Let's Encrypt for ${DOMAIN}"
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
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    client_max_body_size 50M;

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
    location /api/tools/stream/ {
        proxy_pass         http://siemba_ui;
        proxy_buffering    off; proxy_cache off;
        proxy_set_header   Connection ''; proxy_http_version 1.1;
    }
    location /kibana/  { proxy_pass http://siemba_kib/;  proxy_set_header Host \$host; }
    location /grafana/ { proxy_pass http://siemba_grf/;  proxy_set_header Host \$host; }
    location /cases/   { proxy_pass http://siemba_hive/; proxy_set_header Host \$host; }
}
NGINX

  ln -sf /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/siemba
  rm -f /etc/nginx/sites-enabled/default
  nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx
  log "Nginx: HTTPS ready"
}

configure_firewall() {
  step "Firewall"
  command -v ufw &>/dev/null || { log "ufw not found — skipping"; return; }
  ufw allow 22/tcp   >> "$LOG_FILE" 2>&1
  ufw allow 80/tcp   >> "$LOG_FILE" 2>&1
  ufw allow 443/tcp  >> "$LOG_FILE" 2>&1
  ufw allow 5514/udp >> "$LOG_FILE" 2>&1
  ufw allow 5514/tcp >> "$LOG_FILE" 2>&1
  ufw --force enable >> "$LOG_FILE" 2>&1
  log "UFW enabled"
}

install_docker_stack() {
  step "Docker Compose stack"
  mkdir -p "$INSTALL_DIR"
  [[ -f "$INSTALL_DIR/docker-compose.yml" ]] || \
    git clone --depth 1 "$REPO" "$INSTALL_DIR" >> "$LOG_FILE" 2>&1
  cd "$INSTALL_DIR"
  cp .env.example .env
  local jwt; jwt=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)
  sed -i "s|REPLACE_WITH_64_CHAR_RANDOM_STRING|${jwt}|"                      .env
  sed -i "s|SIEMBA_DOMAIN=.*|SIEMBA_DOMAIN=${DOMAIN}|"                       .env
  sed -i "s|ADMIN_INITIAL_PASSWORD=.*|ADMIN_INITIAL_PASSWORD=${ADMIN_PASS}|"  .env
  sed -i "s|LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${EMAIL}|"                 .env
  docker compose pull  >> "$LOG_FILE" 2>&1
  docker compose up -d >> "$LOG_FILE" 2>&1
  log "Docker stack: up"
}

print_summary() {
  local url="https://${DOMAIN}"
  mkdir -p "$INSTALL_DIR"
  printf 'URL: %s\nUsername: admin\nPassword: %s\n' "$url" "$ADMIN_PASS" > "$INSTALL_DIR/.credentials"
  chmod 600 "$INSTALL_DIR/.credentials"

  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║${NC}  ${BOLD}✅ SIEMBA installation complete!${NC}"
  echo -e "${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}  URL:      ${BLUE}${url}${NC}"
  echo -e "${GREEN}║${NC}  Username: ${BOLD}admin${NC}"
  echo -e "${GREEN}║${NC}  Password: ${YELLOW}${ADMIN_PASS}${NC}"
  echo -e "${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}  ${RED}▲ SAVE THIS PASSWORD — shown only once!${NC}"
  echo -e "${GREEN}║${NC}  Saved to: ${INSTALL_DIR}/.credentials"
  echo -e "${GREEN}║${NC}  Log:      ${LOG_FILE}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
  if [[ "$DOMAIN" == "localhost" || "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${YELLOW}Self-signed cert in use — browser will warn: click Advanced → Proceed${NC}"
  fi
}

# ── Entry point ───────────────────────────────────────────────────────────────
main() {
  > "$LOG_FILE"
  banner
  parse_args "$@"
  detect_platform
  check_root
  setup_config

  if [[ "$MODE" == "docker" ]]; then
    prereqs_docker
    install_docker_stack
    setup_tls
  else
    [[ "$PLATFORM" == "linux" ]] && prereqs_linux || prereqs_macos
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
