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

if [[ "$EUID" -ne 0 ]]; then err "Root context required. Re-launch script with (sudo)."; fi

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  WARNING: This will completely wipe out SIEMBA data, ES, & Kibana indices!${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -p "Are you absolutely sure you want to proceed? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Uninstallation sequence canceled."
    exit 0
fi

log "Shutting down platform processing services..."
systemctl stop kibana elasticsearch nginx || true
systemctl disable kibana elasticsearch nginx || true

log "Purging analytics software architecture and system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get purge -y elasticsearch kibana nodejs nginx || true
apt-get autoremove -y || true

log "Deleting data directory trees, source code configurations, and link maps..."
rm -rf /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
rm -rf /etc/kibana /var/lib/kibana /var/log/kibana
rm -rf "$INSTALL_DIR"
rm -f /etc/apt/sources.list.d/elastic-8.x.list
rm -f /etc/apt/sources.list.d/nodesource.list
rm -f /etc/apt/keyrings/nodesource.gpg
rm -f /usr/share/keyrings/elasticsearch-keyring.gpg
rm -f /etc/nginx/sites-available/siemba
rm -f /etc/nginx/sites-enabled/siemba

log "Restoring core system environment boundaries..."
if [ -f /etc/sysctl.d/70-siemba.conf ]; then
    rm -f /etc/sysctl.d/70-siemba.conf
    sysctl -w vm.max_map_count=65530 || true
fi

systemctl daemon-reload
log "SIEMBA tracking ecosystem completely deleted from host system."
