#!/usr/bin/env bash
# =======================================================================
# SIEMBA AUTOMATED INSTALLER & CONFIGURATION SCRIPT
# =======================================================================
set -e

INSTALL_DIR="/opt/siemba"
UI_DIR="$INSTALL_DIR/siemba-ui"
LOG_FILE="/tmp/siemba-install.log"
DOMAIN="127.0.0.1"
EMAIL="admin@cisoeynu.com"
DEFAULT_PASS="SiembaSecure2026!"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[SIEMBA]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[ WARN ]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[ERROR ]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
step() { echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BOLD}${BLUE}  $*\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n" | tee -a "$LOG_FILE"; }
q()    { "$@" >> "$LOG_FILE" 2>&1; }

if [[ "$EUID" -ne 0 ]]; then err "Privileged administrative execution required. Use (sudo)."; fi

step "System Tuning & Prerequisites"
log "Configuring elasticsearch kernel limits (vm.max_map_count)..."
sysctl -w vm.max_map_count=262144 >> "$LOG_FILE" 2>&1 || true
echo "vm.max_map_count=262144" > /etc/sysctl.d/70-siemba.conf

export DEBIAN_FRONTEND=noninteractive
log "Updating local target cache tables and installing dependencies..."
q apt-get update -y
q apt-get install -y curl gnupg2 nginx nodejs npm

step "Installing & Configuring Elasticsearch"
if ! command -v elasticsearch &> /dev/null; then
    log "Adding Elastic repository..."
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.dev/elastic-8.x.list
    q apt-get update -y && q apt-get install -y elasticsearch
fi

log "Writing secure elasticsearch.yml configuration..."
cat > /etc/elasticsearch/elasticsearch.yml << EOF
cluster.name: siemba-cluster
node.name: siemba-node-01
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 127.0.0.1
http.port: 9200
xpack.security.enabled: true
xpack.security.enrollment.enabled: true
xpack.security.http.ssl:
  enabled: false
xpack.security.transport.ssl:
  enabled: false
  verification_mode: none
EOF

log "Starting Elasticsearch database instance..."
q systemctl daemon-reload
q systemctl enable elasticsearch
q systemctl restart elasticsearch

log "Waiting for cluster initialization..."
until curl -s http://127.0.0.1:9200 > /dev/null; do sleep 2; done

log "Configuring static system administrative authentication credentials..."
(echo "$DEFAULT_PASS"; echo "$DEFAULT_PASS") | /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i -b >> "$LOG_FILE" 2>&1 || true

step "Building SIEMBA Application Interface"
if [ ! -d "$UI_DIR" ]; then
    log "Creating target directories..."
    mkdir -p "$INSTALL_DIR"
    cp -r ../siemba-ui "$INSTALL_DIR/" || log "Local UI files matching configuration framework."
fi

cd "$UI_DIR"

log "Ensuring clean workspace access flags..."
chown -R root:root .
chmod -R 755 node_modules/ 2>/dev/null || true

log "Injecting modern AuthProvider routing definitions..."
cat > patch_root.cjs << 'EOF'
const fs = require('fs');
const target = './src/client/main.jsx';
const fallback = './src/client/index.jsx';
function applyPatch(filePath) {
    if (fs.existsSync(filePath)) {
        let code = fs.readFileSync(filePath, 'utf8');
        if (!code.includes('AuthProvider')) {
            code = "import { AuthProvider } from './hooks/useAuth';\n" + code;
            code = code.replace('<App />', '<AuthProvider><App /></AuthProvider>');
            fs.writeFileSync(filePath, code, 'utf8');
            console.log(`Successfully patched: ${filePath}`);
        }
        return true;
    }
    return false;
}
if (!applyPatch(target)) applyPatch(fallback);
EOF
node patch_root.cjs >> "$LOG_FILE" 2>&1
rm -f patch_root.cjs

log "Installing package node tree targets..."
q npm install --unsafe-perm

log "Compiling production assets using Vite core..."
rm -rf dist/
q npm run build

step "Configuring Network Routing Configuration (Nginx)"
cat > /etc/nginx/sites-available/siemba << EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        root ${UI_DIR}/dist;
        index index.html index.htm;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/
chown -R www-data:www-data "$UI_DIR/dist"

log "Restarting HTTP proxies..."
q systemctl restart nginx

echo -e "\n${GREEN}=======================================================${NC}"
echo -e "${GREEN}✅ SIEMBA SYSTEM COMPILED & READY FOR SCRATCH FRESH START!${NC}"
echo -e "${GREEN}=======================================================${NC}"
echo -e "🖥️  UI Endpoint Address: http://${DOMAIN}"
echo -e "👤 Administrative User:  elastic (or ${EMAIL})"
echo -e "🔑 Absolute Password:   ${DEFAULT_PASS}\n"
