#!/usr/bin/env bash
# =============================================================================
# SIEMBA Uninstaller
# Safely removes the SIEMBA Stack, dependencies, and configuration changes
# =============================================================================

set -euo pipefail

INSTALL_DIR="/opt/siemba"
LOG_FILE="/tmp/siemba-uninstall.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${GREEN}[UNINSTALL]${NC} $*"; }
warn() { echo -e "${YELLOW}[ WARN ]${NC} $*"; }
err()  { echo -e "${RED}[ERROR ]${NC} $*"; exit 1; }

if [[ "$EUID" -ne 0 ]]; then err "Run as root (sudo)."; fi

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  WARNING: This will completely delete SIEMBA, ES, and Kibana data!${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -p "Are you absolutely sure you want to proceed? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Uninstall canceled."
    exit 0
fi

# 1. Stop and Disable Services
log "Stopping services..."
systemctl stop kibana elasticsearch nginx || true
systemctl disable kibana elasticsearch nginx || true

# 2. Purge Packages
log "Purging Elasticsearch and Kibana packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get purge -y elasticsearch kibana || true
apt-get autoremove -y || true

# 3. Clean Filesystem Directories
log "Cleaning remaining database, configuration, and app folders..."
rm -rf /etc/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
rm -rf /etc/kibana /var/lib/kibana /var/log/kibana
rm -rf "$INSTALL_DIR"
rm -f /etc/apt/sources.list.d/elastic-8.x.list
rm -f /usr/share/keyrings/elasticsearch-keyring.gpg

# 4. Rollback Kernel Tuning
log "Restoring system tuning configurations..."
if [ -f /etc/sysctl.d/70-siemba.conf ]; then
    rm -f /etc/sysctl.d/70-siemba.conf
    sysctl -w vm.max_map_count=65530 || true
fi

# 5. Remove Swap Space (only if handled by install script)
if grep -q '/swapfile' /etc/fstab; then
    log "Disabling and removing the 4GB installation swapfile..."
    swapoff /swapfile || true
    sed -i '\/swapfile/d' /etc/fstab
    rm -f /swapfile
fi

systemctl daemon-reload
log "SIEMBA uninstalled successfully."
