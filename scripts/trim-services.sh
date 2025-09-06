#!/usr/bin/env bash
# Trim non-essential services on a Debian K3s node
set -euo pipefail
STATE_DIR="/var/local/trim-services"
DISABLED_LIST="$STATE_DIR/disabled-services.list"
DISABLED_GETTYS="$STATE_DIR/disabled-gettys.list"
MOTD_NEWS_BACKUP="$STATE_DIR/motd-news.backup"
LOGFILE="$STATE_DIR/trim-services.log"
mkdir -p "$STATE_DIR"
ACTION="${1:-}"
if [[ -z "$ACTION" ]]; then
  echo "Usage: sudo $(basename "$0") [--apply | --dry-run | --status | --restore]"
  exit 1
fi
timestamp() { date '+%F %T'; }
log() { echo "[$(timestamp)] $*" | tee -a "$LOGFILE"; }
unit_exists() { systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q "$1" || systemctl status "$1" &>/dev/null; }
is_enabled() { systemctl is-enabled "$1" &>/dev/null; }
is_active()  { systemctl is-active  "$1" &>/dev/null; }
disable_unit(){ local u="$1"; unit_exists "$u" || return 0; is_active "$u" && systemctl stop "$u" || true; is_enabled "$u" && systemctl disable "$u" || true; }
enable_unit(){ local u="$1"; unit_exists "$u" && systemctl enable --now "$u" || true; }
detect_gettys(){ systemctl list-unit-files 'getty@tty*.service' --no-legend 2>/dev/null | awk '{print $1}' | sed -n 's/^getty@tty\([0-9]\)\.service$/\1/p' | sort -n; }

SERVICES=(avahi-daemon.service bluetooth.service ModemManager.service cups.service cups-browsed.service rpcbind.service nfs-client.target nfs-client.service smbd.service nmbd.service motd-news.timer systemd-timesyncd.service)
APT_TIMERS_KEEP=(apt-daily.timer apt-daily-upgrade.timer)

apply_changes(){
  : >"$DISABLED_LIST"; : >"$DISABLED_GETTYS"
  log "Applying trim…"
  for svc in "${SERVICES[@]}"; do
    unit_exists "$svc" || continue
    if is_enabled "$svc" || is_active "$svc"; then
      echo "$svc" >> "$DISABLED_LIST"
      if [[ "$ACTION" == "--apply" ]]; then log "Disabling $svc"; disable_unit "$svc"; else log "[dry-run] Would disable $svc"; fi
    fi
  done
  for tty in $(detect_gettys); do
    [[ "$tty" -eq 1 ]] && continue
    unit="getty@tty${tty}.service"
    if unit_exists "$unit" && (is_enabled "$unit" || is_active "$unit"); then
      echo "$unit" >> "$DISABLED_GETTYS"
      if [[ "$ACTION" == "--apply" ]]; then log "Disabling $unit"; disable_unit "$unit"; else log "[dry-run] Would disable $unit"; fi
    fi
  done
  if [[ -f /etc/default/motd-news ]]; then
    if [[ "$ACTION" == "--apply" ]]; then
      [[ -f "$MOTD_NEWS_BACKUP" ]] || cp /etc/default/motd-news "$MOTD_NEWS_BACKUP"
      sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news || true
      log "Set motd-news ENABLED=0"
    else
      log "[dry-run] Would set motd-news ENABLED=0"
    fi
  fi
  log "Trim apply complete."
}
restore_changes(){
  log "Restoring disabled units…"
  [[ -f "$DISABLED_LIST" ]] && while read -r u; do [[ -n "$u" ]] && enable_unit "$u"; done <"$DISABLED_LIST"
  [[ -f "$DISABLED_GETTYS" ]] && while read -r u; do [[ -n "$u" ]] && enable_unit "$u"; done <"$DISABLED_GETTYS"
  [[ -f "$MOTD_NEWS_BACKUP" ]] && cp "$MOTD_NEWS_BACKUP" /etc/default/motd-news && log "Restored motd-news"
  log "Restore done."
}
status_report(){
  echo "==== Trim Status ===="
  printf "%-35s %-10s %-10s\n" "UNIT" "Enabled?" "Active?"
  for svc in "${SERVICES[@]}"; do
    unit_exists "$svc" || continue
    en="no"; is_enabled "$svc" && en="yes"
    ac="no"; is_active "$svc" && ac="yes"
    printf "%-35s %-10s %-10s\n" "$svc" "$en" "$ac"
  done
  echo; echo "TTY getty units:"
  for tty in $(detect_gettys); do
    unit="getty@tty${tty}.service"
    en="no"; is_enabled "$unit" && en="yes"
    ac="no"; is_active "$unit" && ac="yes"
    printf "%-35s %-10s %-10s\n" "$unit" "$en" "$ac"
  done
  echo; echo "Kept timers:"
  for t in "${APT_TIMERS_KEEP[@]}"; do
    en="no"; systemctl is-enabled "$t" &>/dev/null && en="yes"
    printf "%-35s %-10s\n" "$t" "$en"
  done
  echo; if command -v kubectl >/dev/null 2>&1; then
    kubectl get nodes -o wide || true; kubectl get pods -A | head -10 || true
  else echo "kubectl not found"; fi
  echo "====================="
}
case "${ACTION}" in
  --apply|--dry-run) apply_changes; status_report ;;
  --status)          status_report ;;
  --restore)         restore_changes; status_report ;;
  *) echo "Usage: sudo $(basename "$0") [--apply | --dry-run | --status | --restore]"; exit 1 ;;
esac
