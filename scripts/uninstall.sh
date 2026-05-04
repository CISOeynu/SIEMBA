#!/usr/bin/env bash
# =============================================================================
# SIEMBA Uninstaller v1.0.0
# Safe-by-default uninstaller for Ubuntu/Debian
# - Stops/removes services and packages
# - Removes repos and Nginx site
# - Preserves application data and certificates by default
# =============================================================================

set -Eeuo pipefail

LOG_FILE="/tmp/siemba-uninstall.log"
BACKUP_DIR="/root/siemba-uninstall-backups/$(date +%F-%H%M%S)"
PURGE_DATA="false"
PURGE_CERTS="false"
PURGE_REPOS="true"
REMOVE_SWAPFILE="false"
REMOVE_FIREWALL_RULES="false"
YES="false"

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

banner() { echo -e "${BOLD}SIEMBA Uninstaller v1.0.0${NC}\nLog: ${LOG_FILE}\n"; }
usage() {
  cat <<EOF
Usage: sudo bash uninstall-siemba.sh [options]

Options:
  --yes                              Run non-interactively
  --purge-data=true|false            Remove application data/logs (default: false)
  --purge-certs=true|false           Remove SIEMBA-generated certificates (default: false)
  --purge-repos=true|false           Remove APT repo definitions/keys (default: true)
  --remove-swapfile=true|false       Remove /swapfile and fstab entry (default: false)
  --remove-firewall-rules=true|false Reset UFW to allow OpenSSH only and disable it (default: false)
  -h, --help                         Show help
EOF
}
parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --yes) YES="true" ;;
      --purge-data=*) PURGE_DATA="${arg#--purge-data=}" ;;
      --purge-certs=*) PURGE_CERTS="${arg#--purge-certs=}" ;;
      --purge-repos=*) PURGE_REPOS="${arg#--purge-repos=}" ;;
      --remove-swapfile=*) REMOVE_SWAPFILE="${arg#--remove-swapfile=}" ;;
      --remove-firewall-rules=*) REMOVE_FIREWALL_RULES="${arg#--remove-firewall-rules=}" ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Ignoring unknown argument: $arg" ;;
    esac
  done
}
require_root() { [[ "${EUID}" -eq 0 ]] || err "Run as root: sudo bash uninstall-siemba.sh"; }
backup_path() { local p="$1"; [[ -e "$p" ]] || return 0; mkdir -p "$BACKUP_DIR"; cp -a "$p" "$BACKUP_DIR/" 2>/dev/null || true; }
confirm() {
  if [[ "$YES" == "true" ]]; then return 0; fi
  echo "This will remove SIEMBA packages/services from this host."
  echo "Data purge:         $PURGE_DATA"
  echo "Certificates purge: $PURGE_CERTS"
  echo "Repo purge:         $PURGE_REPOS"
  echo "Remove swapfile:    $REMOVE_SWAPFILE"
  echo
  read -r -p "Continue? [y/N] " ans
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
  step "Backing up configuration"
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
remove_nginx_site() {
  register_section "Nginx site"
  step "Removing SIEMBA Nginx site"
  rm -f /etc/nginx/sites-enabled/siemba /etc/nginx/sites-available/siemba || true
  systemctl restart nginx >> "$LOG_FILE" 2>&1 || true
  status_ok "Nginx site"
}
remove_repos() {
  register_section "Repositories"
  step "Removing APT repositories"
  if [[ "$PURGE_REPOS" == "true" ]]; then
    rm -f /etc/apt/sources.list.d/elastic-*.list /etc/apt/sources.list.d/grafana.list /etc/apt/sources.list.d/strangebee.list || true
    rm -f /usr/share/keyrings/elasticsearch-keyring.gpg /etc/apt/keyrings/grafana.asc /etc/apt/keyrings/strangebee.asc || true
    q apt-get update || true
  fi
  status_ok "Repositories"
}
remove_runtime_files() {
  register_section "Runtime files"
  step "Removing runtime files"
  rm -f /etc/systemd/system/elasticsearch.service.d/override.conf /etc/security/limits.d/99-elasticsearch.conf /etc/sysctl.d/99-siemba-elasticsearch.conf || true
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  systemctl reset-failed >> "$LOG_FILE" 2>&1 || true
  status_ok "Runtime files"
}
purge_data() {
  register_section "Data"
  step "Data cleanup"
  if [[ "$PURGE_DATA" == "true" ]]; then
    rm -rf /var/lib/elasticsearch /var/log/elasticsearch /var/lib/kibana /var/lib/grafana /var/lib/logstash /var/log/logstash /var/lib/cassandra /var/log/cassandra /opt/siemba || true
    status_ok "Data"
  else
    status_skip "Data"
  fi
}
purge_certs() {
  register_section "Certificates"
  step "Certificate cleanup"
  if [[ "$PURGE_CERTS" == "true" ]]; then
    rm -rf /etc/elasticsearch/certs /etc/kibana/certs /etc/logstash/certs /etc/ssl/siemba || true
    status_ok "Certificates"
  else
    status_skip "Certificates"
  fi
}
remove_swapfile() {
  register_section "Swapfile"
  step "Swapfile"
  if [[ "$REMOVE_SWAPFILE" == "true" ]]; then
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
  step "Firewall cleanup"
  if [[ "$REMOVE_FIREWALL_RULES" == "true" ]]; then
    ufw --force reset >> "$LOG_FILE" 2>&1 || true
    ufw allow OpenSSH >> "$LOG_FILE" 2>&1 || true
    ufw disable >> "$LOG_FILE" 2>&1 || true
    status_ok "Firewall"
  else
    status_skip "Firewall"
  fi
}
print_summary() {
  echo -e "\n${BOLD}Uninstall status summary${NC}" | tee -a "$LOG_FILE"
  for s in "${SECTIONS[@]}"; do printf '  - %-18s : %s\n' "$s" "${STATUS[$s]}" | tee -a "$LOG_FILE"; done
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
  remove_nginx_site
  remove_repos
  remove_runtime_files
  purge_data
  purge_certs
  remove_swapfile
  firewall_cleanup
  print_summary
}
main "$@"
