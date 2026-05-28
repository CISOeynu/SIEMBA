#!/usr/bin/env bash
# =============================================================================
# SIEMBA Complete System Uninstaller
# Safely Tears Down Ingress Proxies, Platform Data Engine & Native Packages
# =============================================================================

set -euo pipefail

INSTALL_DIR="/opt/siemba"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()  { echo -e "${GREEN}[UNINSTALL]${NC} $*"; }
warn() { echo -e "${YELLOW}[ WARN ]${NC} $*"; }
err()  { echo -e "${RED}[ERROR ]${NC} $*"; exit 1; }

if [[ "$EUID" -ne 0 ]]; then err "Launch script with (sudo)."; fi

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  WARNING: This will completely wipe out SIEMBA data, ES, & Kibana indices!${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -p "Are you absolutely sure you want to proceed? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Uninstallation canceled."
    exit 0
fi

log "Stopping background services..."
systemctl stop kibana elasticsearch nginx || true
systemctl disable kibana elasticsearch nginx || true

log "Purging analytics package architectures..."
export DEBIAN_FRONTEND=noninteractive
apt-get purge -y elasticsearch kibana || true
apt-get autoremove -y || true

log "Removing database files and configurations..."
rm -rf /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
rm -rf /etc/kibana /var/lib/kibana /var/log/kibana
rm -rf "$INSTALL_DIR"
rm -f /etc/apt/sources.list.d/elastic-8.x.list
rm -f /usr/share/keyrings/elasticsearch-keyring.gpg
rm -f /etc/nginx/sites-available/siemba
rm -f /etc/nginx/sites-enabled/siemba

if [ -f /etc/sysctl.d/70-siemba.conf ]; then
    rm -f /etc/sysctl.d/70-siemba.conf
    sysctl -w vm.max_map_count=65530 || true
fi

systemctl daemon-reload
log "SIEMBA has been cleanly uninstalled."
