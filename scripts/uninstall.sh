#!/usr/bin/env bash
# =============================================================================
# SIEMBA Full Uninstaller v2.2.0
# Destroys SIEMBA/Elastic/Grafana/Nginx site state created by the installer.
# Defaults to FULL removal (packages, data, certs, repos, site config).
# =============================================================================

set -Eeuo pipefail

LOG_FILE="/tmp/siemba-uninstall.log"
BACKUP_DIR="/root/siemba-uninstall-backups/$(date +%F-%H%M%S)"
YES="false"
KEEP_SWAPFILE="true"
KEEP_FIREWALL="true"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
SECTIONS=(); declare -A STATUS

ts() { date '+%F %T'; }
log()  { echo -e "$(ts) ${GREEN}[UNINSTALL]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "$(ts) ${YELLOW}[WARN ]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "$(ts) ${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
q()    { "$@" >> "$LOG_FILE" 2>&1; }
register_section() { local s="$1"; SECTIONS+=("$s"); STATUS["$s"]="PENDING"; }
status_ok()    { local s="$1"; STATUS["$s"]="OK"; echo -e "${GREEN}[OK]${NC} ${s}" | tee -a "$LOG_FILE"; }
status_skip()  { local s="$1"; STATUS["$s"]="SKIPPED"; echo -e "${YELLOW}[WARN ]${NC} ${s} skipped" | tee -a "$LOG_FILE"; }

banner() { echo -e "${BOLD}SIEMBA Full Uninstaller v2.2.0${NC}\nLog: ${LOG_FILE}\n"; }
usage() {
  cat <<EOF
Usage: sudo bash uninstall.sh [options]

Options:
  --yes                     Run non-interactively
  --remove-swapfile=true    Also remove /swapfile and fstab entry
  --remove-firewall=true    Also reset/disable UFW
  -h, --help                Show help
EOF
}
parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --yes) YES="true" ;;
      --remove-swapfile=true) KEEP_SWAPFILE="false" ;;
      --remove-firewall=true) KEEP_FIREWALL="false" ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Ignoring unknown argument: $arg" ;;
    esac
  done
}
require_root() { [[ "${EUID}" -eq 0 ]] || err "Run as root: sudo bash uninstall.sh"; }
backup_path() { local p="$1"; [[ -e "$p" ]] || return 0; mkdir -p "$BACKUP_DIR"; cp -a "$p" "$BACKUP_DIR/" 2>/dev/null || true; }
confirm() {
  if [[ "$YES" == "true" ]]; then return 0; fi
  echo "This will FULLY remove SIEMBA / Elastic / Grafana / related config and data from this host."
  echo "Continue? [y/N]"
  read -r ans
  [[ "$ans" =~ ^[Yy]$ ]] || err "Aborted by user."
}
step() {
  echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
  echo -e "${BOLD}  $*${NC}" | tee -a "$LOG_FILE"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n" | tee -a "$LOG_FILE"
}
stop_services() {
  register_section "Stop services"
  step "Stopping services"
  for s in grafana-server logstash kibana elasticsearch nginx thehive cassandra; do
    systemctl stop "$s" >> "$LOG_FILE" 2>&1 || true
    systemctl disable "$s" >> "$LOG_FILE" 2>&1 || true
  done
  status_ok "Stop services"
}
backup_configs() {
  register_section "Backup configs"
  step "Backing up current configuration"
  for p in /etc/elasticsearch /etc/kibana /etc/logstash /etc/grafana /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/siemba /root/siemba-credentials.txt /opt/siemba; do
    backup_path "$p"
  done
  status_ok "Backup configs"
}
remove_packages() {
  register_section "Packages"
  step "Removing packages"
  export DEBIAN_FRONTEND=noninteractive
  q apt-get remove -y elasticsearch kibana logstash grafana grafana-enterprise thehive cassandra || true
  q apt-get autoremove -y || true
  status_ok "Packages"
}
remove_repos() {
  register_section "Repositories"
  step "Removing APT repositories"
  rm -f /etc/apt/sources.list.d/elastic-*.list /etc/apt/sources.list.d/grafana.list /etc/apt/sources.list.d/strangebee.list || true
  rm -f /usr/share/keyrings/elasticsearch-keyring.gpg /etc/apt/keyrings/grafana.asc /etc/apt/keyrings/strangebee.asc || true
  q apt-get update || true
  status_ok "Repositories"
}
remove_everything() {
  register_section "Files and data"
  step "Removing files, data, certificates and site configuration"
  rm -rf \
    /var/lib/elasticsearch /var/log/elasticsearch /etc/elasticsearch \
    /etc/kibana /var/lib/kibana \
    /etc/logstash /var/lib/logstash /var/log/logstash \
    /etc/grafana /var/lib/grafana \
    /etc/ssl/siemba /var/www/siemba /opt/siemba \
    /etc/nginx/sites-available/siemba /etc/nginx/sites-enabled/siemba || true
  rm -f /etc/systemd/system/elasticsearch.service.d/override.conf /etc/security/limits.d/99-elasticsearch.conf /etc/sysctl.d/99-siemba-elasticsearch.conf || true
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  systemctl reset-failed >> "$LOG_FILE" 2>&1 || true
  status_ok "Files and data"
}
remove_swapfile() {
  register_section "Swapfile"
  step "Swapfile"
  if [[ "$KEEP_SWAPFILE" == "false" ]]; then
    swapoff /swapfile >> "$LOG_FILE" 2>&1 || true
    sed -i '\#^/swapfile none swap sw 0 0$#d' /etc/fstab || true
    rm -f /swapfile || true
    status_ok "Swapfile"
  else
    status_skip "Swapfile"
  fi
}
firewall_cleanup() {
  register_section "Firewall"
  step "Firewall"
  if [[ "$KEEP_FIREWALL" == "false" ]]; then
    ufw --force reset >> "$LOG_FILE" 2>&1 || true
    ufw disable >> "$LOG_FILE" 2>&1 || true
    status_ok "Firewall"
  else
    status_skip "Firewall"
  fi
}
print_summary() {
  echo -e "\n${BOLD}Uninstall status summary${NC}" | tee -a "$LOG_FILE"
  for s in "${SECTIONS[@]}"; do printf '  - %-20s : %s\n' "$s" "${STATUS[$s]}" | tee -a "$LOG_FILE"; done
  echo "Backups: $BACKUP_DIR" | tee -a "$LOG_FILE"
  echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
}
main() {
  : > "$LOG_FILE"
  banner
  parse_args "$@"
  require_root
  confirm
  stop_services
  backup_configs
  remove_packages
  remove_repos
  remove_everything
  remove_swapfile
  firewall_cleanup
  print_summary
}
main "$@"
