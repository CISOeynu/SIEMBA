#!/usr/bin/env bash
# =============================================================================
# SIEMBA Complete System Uninstaller
# Safely Tears Down Ingress Proxies, Platform Data Engine & Native Packages
# =============================================================================

set -euo pipefail

INSTALL_DIR="/opt/siemba"
LOG_FILE="/tmp/siemba-uninstall.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${GREEN}[UNINSTALL]${NC} $*"; }
warn() { echo -e "${YELLOW}[ WARN ]${NC} $*"; }
err()  { echo -e "${RED}[ERROR ]${NC} $*"; exit 1; }

if [[ "$EUID" -ne 0 ]]; then err "Root context required. Re-launch with (sudo)."; fi

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  WARNING: This will completely wipe out SIEMBA data, ES, & Kibana indices!${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -p "Are you absolutely sure you want to proceed? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Uninstallation sequence canceled."
    exit 0
fi

log "Shutting down system execution tasks..."
systemctl stop kibana elasticsearch nginx || true
systemctl disable kibana elasticsearch nginx || true

log "Purging analytics package environments..."
export DEBIAN_FRONTEND=noninteractive
apt-get purge -y elasticsearch kibana || true
apt-get autoremove -y || true

log "Deleting application system path matrices & code files..."
rm -rf /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
rm -rf /etc/kibana /var/lib/kibana /var/log/kibana
rm -rf "$INSTALL_DIR"
rm -f /etc/apt/sources.list.d/elastic-8.x.list
rm -f /usr/share/keyrings/elasticsearch-keyring.gpg
rm -f /etc/nginx/sites-available/siemba
rm -f /etc/nginx/sites-enabled/siemba

log "Restoring system tuning defaults..."
if [ -f /etc/sysctl.d/70-siemba.conf ]; then
    rm -f /etc/sysctl.d/70-siemba.conf
    sysctl -w vm.max_map_count=65530 || true
fi

if grep -q '/swapfile' /etc/fstab; then
    log "Reclaiming disk landscape from installation swapfile..."
    swapoff /swapfile || true
    sed -i '\/swapfile/d' /etc/fstab
    rm -f /swapfile
fi

systemctl daemon-reload
log "SIEMBA ecosystem cleanly uninstalled."
