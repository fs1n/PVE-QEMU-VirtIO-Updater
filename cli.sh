#!/usr/bin/env bash
#
# Module: cli.sh (PVE-QEMU-VirtIO-Updater)
# Description: CLI Management for PVE-QEMU-VirtIO-Updater
# Author: Frederik S. (fs1n) and PVE-QEMU-VirtIO-Updater Contributors
# Date: 2026-04-01
#
# Dependencies: jq, curl, pvesh, qm, sed, awk, grep, whiptail
# Environment: 
# Usage: ./cli.sh
#
# Description:
#   Serves as management for the PVE-QEMU-VirtIO-Updater, providing a command-line interface for manual checks, configuration overrides, and update management.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
ENV_FILE="$SCRIPT_DIR/.env"

# Load environment overrides if they exist
if [[ -f "$ENV_FILE" ]]; then
  set -o allexport
  . "$ENV_FILE"
#   set +o allexport # Currently removed to fix array sourcing issues
fi

# Source all functions in lib files
for lib_file in "$LIB_DIR"/*.func; do
  if [[ -f "$lib_file" ]]; then
    source "$lib_file"
  fi
done

LOG_PATH="${LOG_DIR:=$SCRIPT_DIR/logs}/cli.log"
USE_WHIPTAIL=true
RUNNING_AS_ROOT=false
CRON_MARKER="# pve-qemu-virtio-updater"

function cleanup_tty() {
  stty sane 2>/dev/null || :
}

function ui_use_whiptail() {
  [[ "$USE_WHIPTAIL" == "true" ]]
}

function ui_msg() {
  local title="$1"
  local message="$2"
  local rendered
  rendered="$(printf '%b' "$message")"

  if ui_use_whiptail; then
    whiptail --title "$title" --msgbox "$rendered" 14 80
  else
    printf '\n[%s]\n%s\n\n' "$title" "$rendered"
    read -r -p "Weiter mit Enter... " _unused
  fi
}

function ui_error() {
  local message="$1"
  ui_msg "Fehler" "$message"
}

function ui_confirm() {
  local title="$1"
  local question="$2"

  if ui_use_whiptail; then
    whiptail --title "$title" --yesno "$question" 12 80
  else
    local answer
    read -r -p "$question [y/N]: " answer
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
  fi
}

function ui_show_text() {
  local title="$1"
  local content="$2"
  local rendered
  rendered="$(printf '%b' "$content")"

  if ui_use_whiptail; then
    local tmp_file
    tmp_file="$(mktemp)"
    printf '%s\n' "$rendered" > "$tmp_file"
    whiptail --title "$title" --scrolltext --textbox "$tmp_file" 25 110
    rm -f "$tmp_file"
  else
    printf '\n=== %s ===\n%s\n\n' "$title" "$rendered"
    read -r -p "Weiter mit Enter... " _unused
  fi
}

function check_cli_dependencies() {
  local dependencies=( "curl" "jq" "pvesh" "qm" "grep" "sed" "awk" "sort" )

  if ui_use_whiptail; then
    dependencies+=("whiptail")
  fi

  local dep
  for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      log_error "Abhaengigkeit fehlt: $dep"
      ui_error "Fehlende Abhaengigkeit: $dep"
      exit 1
    fi
  done
}

function ui_main_menu_choice() {
  if ui_use_whiptail; then
    local choice status
    set +e
    choice=$(whiptail --title "PVE-QEMU-VirtIO-Updater" --menu "Startseite - Aktion waehlen" 20 90 10 \
      "1" "Update-Check aller laufenden Windows-VMs" \
      "2" "VM-Statusuebersicht" \
      "3" "Manueller Check fuer einzelne VM" \
      "4" "State bereinigen oder zuruecksetzen" \
      "5" "Einstellungen anzeigen (.env)" \
      "6" "Cron-Verwaltung fuer main.sh" \
      "7" "Beenden" \
      3>&1 1>&2 2>&3)
    status=$?
    set -e

    if [[ $status -ne 0 ]]; then
      echo "7"
      return 0
    fi

    echo "$choice"
    return 0
  fi

  printf '\nPVE-QEMU-VirtIO-Updater Startseite\n'
  printf '1) Update-Check aller laufenden Windows-VMs\n'
  printf '2) VM-Statusuebersicht\n'
  printf '3) Manueller Check fuer einzelne VM\n'
  printf '4) State bereinigen oder zuruecksetzen\n'
  printf '5) Einstellungen anzeigen (.env)\n'
  printf '6) Cron-Verwaltung fuer main.sh\n'
  printf '7) Beenden\n'

  local choice
  read -r -p "Auswahl [1-7]: " choice
  echo "$choice"
}

function require_interactive_tty() {
  if [[ ! -t 0 ]]; then
    printf 'ERROR: cli.sh requires an interactive terminal (TTY).\n' >&2
    exit 78
  fi
}

function detect_ui_mode() {
  if command -v whiptail >/dev/null 2>&1; then
    USE_WHIPTAIL=true
  else
    USE_WHIPTAIL=false
    printf 'WARN: whiptail not found. Falling back to text mode.\n' >&2
  fi
}

function init_runtime() {
  require_interactive_tty
  detect_ui_mode

  if [[ "$EUID" -eq 0 ]]; then
    RUNNING_AS_ROOT=true
  fi

  init_state_dir
  load_init_state

  if [[ "${LOGGER_INITIALIZED:-false}" != "true" ]]; then
    init_logger \
      --log "$LOG_PATH" \
      --level "${LOG_LEVEL:=info}" \
      --format "${LOG_FORMAT:=[%d] [%l] %m}" \
      --quiet \
      --journal \
      --tag "PVE-VirtIO-Updater-CLI"
    save_init_state "true"
  else
    init_logger \
      --log "$LOG_PATH" \
      --level "${LOG_LEVEL:=info}" \
      --format "${LOG_FORMAT:=[%d] [%l] %m}" \
      --quiet \
      --journal \
      --tag "PVE-VirtIO-Updater-CLI"
  fi

  check_cli_dependencies

  if [[ "$RUNNING_AS_ROOT" != "true" ]]; then
    log_warn "CLI laeuft nicht als root. Einige Funktionen wie pvesh/qm koennen fehlschlagen."
  fi

  if ! pvesh get /nodes --output-format json >/dev/null 2>&1; then
    log_error "Proxmox API nicht erreichbar via pvesh."
    ui_error "Proxmox API nicht erreichbar (pvesh get /nodes). Bitte Ausfuehrung und Rechte pruefen."
    exit 1
  fi
}

function gather_vm_sets() {
  windows_vms_all="$(get_windows_vms)"
  windows_vms_running="$(echo "$windows_vms_all" | jq 'to_entries | map(select(.value.status == "running")) | from_entries')"
}

function perform_update_for_vm() {
  local vmid="$1"
  local vmset_json="$2"

  local node
  node="$(echo "$vmset_json" | jq -r --arg vmid "$vmid" '.[$vmid].node')"
  if [[ -z "$node" || "$node" == "null" ]]; then
    log_warn "VM $vmid hat keinen gueltigen Node-Eintrag."
    return 1
  fi

  local vmgenid
  vmgenid="$(get_vm_genid "$node" "$vmid")"

  local virtio_version qemu_ga_version
  virtio_version="$(get_windows_virtio_version "$vmid")"
  qemu_ga_version="$(get_windows_QEMU_GA_version "$vmid")"

  local need_virtio=false
  local need_qemu_ga=false

  if [[ "$virtio_version" != "$CurrentVirtIOVersion" ]]; then
    need_virtio=true
  fi

  if [[ "$qemu_ga_version" != "$CurrentQEMUGAVersion" ]]; then
    need_qemu_ga=true
  fi

  local nag_status
  if should_show_nag "$vmid" "$virtio_version" "$CurrentVirtIOVersion" \
                     "$qemu_ga_version" "$CurrentQEMUGAVersion" "$vmgenid"; then
    nag_status=0
  else
    nag_status=$?
  fi

  case "$nag_status" in
    0)
      maybe_show_update_nag \
        "$node" "$vmid" \
        "$need_virtio" "$need_qemu_ga" \
        "$virtio_version" "$CurrentVirtIOVersion" \
        "$qemu_ga_version" "$CurrentQEMUGAVersion" \
        "$CurrentVirtIORelease" "$CurrentQEMUGARelease" \
        "$vmgenid"
      ;;
    1)
      :
      ;;
    2)
      remove_vm_nag "$node" "$vmid"
      save_vm_state "$vmid" "$virtio_version" "$qemu_ga_version" "false" "$vmgenid"
      ;;
    *)
      log_warn "Unknown nag_status='$nag_status' for VM $vmid."
      save_vm_state "$vmid" "$virtio_version" "$qemu_ga_version" "false" "$vmgenid"
      ;;
  esac

  return 0
}

function fetch_latest_versions() {
  local virtio_info qemu_info
  virtio_info="$(fetch_latest_virtio_version)"
  qemu_info="$(fetch_latest_qemu_ga_version)"

  CurrentVirtIOVersion="$(echo "$virtio_info" | jq -r '.version')"
  CurrentVirtIORelease="$(echo "$virtio_info" | jq -r '.release')"

  CurrentQEMUGAVersion="$(echo "$qemu_info" | jq -r '.version')"
  CurrentQEMUGARelease="$(echo "$qemu_info" | jq -r '.release')"
}

function action_check_updates_all() {
  gather_vm_sets

  if [[ -z "$windows_vms_running" || "$windows_vms_running" == "{}" ]]; then
    ui_msg "Info" "Keine laufenden Windows-VMs gefunden."
    return 0
  fi

  cleanup_stale_state_files "$windows_vms_all"
  fetch_latest_versions

  local report
  report="Update-Check abgeschlossen\n\n"

  local vmid
  for vmid in $(echo "$windows_vms_running" | jq -r 'keys[]'); do
    perform_update_for_vm "$vmid" "$windows_vms_running"
    report+="VM ${vmid}: geprueft\n"
  done

  log_info "CLI: Update-Check fuer alle laufenden Windows-VMs abgeschlossen."
  ui_msg "Ergebnis" "$report"
}

function build_vm_status_report() {
  gather_vm_sets
  if [[ -z "$windows_vms_all" || "$windows_vms_all" == "{}" ]]; then
    printf 'Keine Windows-VMs gefunden.\n'
    return 0
  fi

  fetch_latest_versions

  local output
  output="Latest VirtIO: ${CurrentVirtIOVersion} (${CurrentVirtIORelease})\n"
  output+="Latest QEMU-GA: ${CurrentQEMUGAVersion} (${CurrentQEMUGARelease})\n\n"
  output+="VMID  STATUS   VIRTIO(inst/latest)    QEMU-GA(inst/latest)    UPDATE\n"
  output+="----  ------   --------------------    --------------------    ------\n"

  local vmid
  for vmid in $(echo "$windows_vms_all" | jq -r 'keys[]'); do
    local status virtio_inst qemu_inst needs_update
    status="$(echo "$windows_vms_all" | jq -r --arg vmid "$vmid" '.[$vmid].status')"

    if [[ "$status" == "running" ]]; then
      virtio_inst="$(get_windows_virtio_version "$vmid")"
      qemu_inst="$(get_windows_QEMU_GA_version "$vmid")"
    else
      virtio_inst="n/a"
      qemu_inst="n/a"
    fi

    needs_update="no"
    if [[ "$status" == "running" ]]; then
      if [[ "$virtio_inst" != "$CurrentVirtIOVersion" || "$qemu_inst" != "$CurrentQEMUGAVersion" ]]; then
        needs_update="yes"
      fi
    fi

    output+="$(printf '%-4s  %-7s  %-20s    %-20s    %-6s\n' \
      "$vmid" "$status" "${virtio_inst}/${CurrentVirtIOVersion}" "${qemu_inst}/${CurrentQEMUGAVersion}" "$needs_update")"
  done

  printf '%b' "$output"
}

function action_show_vm_status() {
  local report
  report="$(build_vm_status_report)"
  ui_show_text "VM-Statusuebersicht" "$report"
}

function select_vm_from_running() {
  gather_vm_sets
  if [[ -z "$windows_vms_running" || "$windows_vms_running" == "{}" ]]; then
    echo ""
    return 0
  fi

  if ui_use_whiptail; then
    local menu_args=()
    local vmid name
    while IFS= read -r vmid; do
      name="$(echo "$windows_vms_running" | jq -r --arg vmid "$vmid" '.[$vmid].name // "unnamed"')"
      menu_args+=("$vmid" "$name")
    done < <(echo "$windows_vms_running" | jq -r 'keys[]')

    local choice status
    set +e
    choice=$(whiptail --title "VM-Auswahl" --menu "Laufende Windows-VM auswaehlen" 22 90 12 "${menu_args[@]}" 3>&1 1>&2 2>&3)
    status=$?
    set -e

    if [[ $status -ne 0 ]]; then
      echo ""
      return 0
    fi

    echo "$choice"
    return 0
  fi

  printf '\nLaufende Windows-VMs:\n'
  local vmid
  for vmid in $(echo "$windows_vms_running" | jq -r 'keys[]'); do
    printf '%s\n' "$vmid"
  done
  local choice
  read -r -p "VMID eingeben (leer = abbrechen): " choice
  echo "$choice"
}

function action_manual_vm_check() {
  local vmid
  vmid="$(select_vm_from_running)"

  if [[ -z "$vmid" ]]; then
    ui_msg "Info" "Keine VM ausgewaehlt."
    return 0
  fi

  fetch_latest_versions
  perform_update_for_vm "$vmid" "$windows_vms_running"
  ui_msg "Ergebnis" "Manueller Check fuer VM $vmid abgeschlossen."
}

function delete_state_file_for_vmid() {
  local vmid="$1"
  local state_file="$STATE_DIR/vm-${vmid}.state"

  if [[ -f "$state_file" ]]; then
    rm -f "$state_file"
    log_info "State-Datei fuer VM $vmid geloescht."
  fi
}

function state_reset_menu_choice() {
  if ui_use_whiptail; then
    local choice status
    set +e
    choice=$(whiptail --title "State verwalten" --menu "Aktion waehlen" 16 90 7 \
      "1" "Stale State-Dateien bereinigen" \
      "2" "State einer VM zuruecksetzen" \
      "3" "Alle VM-State-Dateien loeschen" \
      "4" "Zurueck" \
      3>&1 1>&2 2>&3)
    status=$?
    set -e

    if [[ $status -ne 0 ]]; then
      echo "4"
      return 0
    fi

    echo "$choice"
    return 0
  fi

  printf '\nState-Verwaltung\n'
  printf '1) Stale State-Dateien bereinigen\n'
  printf '2) State einer VM zuruecksetzen\n'
  printf '3) Alle VM-State-Dateien loeschen\n'
  printf '4) Zurueck\n'
  local choice
  read -r -p "Auswahl [1-4]: " choice
  echo "$choice"
}

function action_state_reset() {
  local choice
  choice="$(state_reset_menu_choice)"

  case "$choice" in
    1)
      gather_vm_sets
      cleanup_stale_state_files "$windows_vms_all"
      ui_msg "Ergebnis" "Stale State-Dateien wurden bereinigt."
      ;;
    2)
      gather_vm_sets
      local vmid
      vmid="$(select_vm_from_running)"
      if [[ -z "$vmid" ]]; then
        ui_msg "Info" "Keine VM ausgewaehlt."
        return 0
      fi
      if ui_confirm "Bestaetigung" "State fuer VM $vmid wirklich loeschen?"; then
        delete_state_file_for_vmid "$vmid"
        ui_msg "Ergebnis" "State fuer VM $vmid wurde geloescht."
      fi
      ;;
    3)
      if ui_confirm "Bestaetigung" "Alle VM-State-Dateien loeschen?"; then
        rm -f "$STATE_DIR"/vm-*.state 2>/dev/null || :
        ui_msg "Ergebnis" "Alle VM-State-Dateien wurden geloescht."
      fi
      ;;
    *)
      return 0
      ;;
  esac
}

function mask_env_value() {
  local key="$1"
  local value="$2"

  if [[ "$key" =~ (PASS|TOKEN|SECRET|KEY) ]]; then
    echo "***"
  else
    echo "$value"
  fi
}

function action_show_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    ui_msg "Info" "Keine .env gefunden unter $ENV_FILE"
    return 0
  fi

  local output
  output="Datei: $ENV_FILE\n\n"

  local line key value masked
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" != *"="* ]]; then
      continue
    fi
    key="${line%%=*}"
    value="${line#*=}"
    key="${key// /}"
    masked="$(mask_env_value "$key" "$value")"
    output+="${key}=${masked}\n"
  done < "$ENV_FILE"

  ui_show_text "Konfiguration (.env)" "$output"
}

function get_crontab_text() {
  local current
  set +e
  current="$(crontab -l 2>/dev/null)"
  set -e
  printf '%s' "$current"
}

function action_cron_show() {
  local current
  current="$(get_crontab_text)"
  if [[ -z "$current" ]]; then
    current="Keine Crontab-Eintraege vorhanden."
  fi
  ui_show_text "Aktuelle Crontab" "$current"
}

function set_cron_for_main() {
  local schedule="$1"
  local cmd="$SCRIPT_DIR/main.sh"
  local new_entry="$schedule $cmd $CRON_MARKER"

  local current filtered
  current="$(get_crontab_text)"
  filtered="$(printf '%s\n' "$current" | grep -vF "$CRON_MARKER" | grep -vF "$cmd" || true)"

  local final
  if [[ -n "$filtered" ]]; then
    final="$filtered"$'\n'"$new_entry"
  else
    final="$new_entry"
  fi

  printf '%s\n' "$final" | crontab -
}

function remove_cron_for_main() {
  local cmd="$SCRIPT_DIR/main.sh"
  local current filtered
  current="$(get_crontab_text)"
  filtered="$(printf '%s\n' "$current" | grep -vF "$CRON_MARKER" | grep -vF "$cmd" || true)"
  printf '%s\n' "$filtered" | crontab -
}

function cron_menu_choice() {
  if ui_use_whiptail; then
    local choice status
    set +e
    choice=$(whiptail --title "Cron-Verwaltung" --menu "Aktion waehlen" 16 90 8 \
      "1" "Crontab anzeigen" \
      "2" "main.sh taeglich 02:00 einplanen" \
      "3" "main.sh taeglich 04:00 einplanen" \
      "4" "main.sh Cron-Eintrag entfernen" \
      "5" "Zurueck" \
      3>&1 1>&2 2>&3)
    status=$?
    set -e

    if [[ $status -ne 0 ]]; then
      echo "5"
      return 0
    fi

    echo "$choice"
    return 0
  fi

  printf '\nCron-Verwaltung\n'
  printf '1) Crontab anzeigen\n'
  printf '2) main.sh taeglich 02:00 einplanen\n'
  printf '3) main.sh taeglich 04:00 einplanen\n'
  printf '4) main.sh Cron-Eintrag entfernen\n'
  printf '5) Zurueck\n'
  local choice
  read -r -p "Auswahl [1-5]: " choice
  echo "$choice"
}

function action_cron_management() {
  local choice
  choice="$(cron_menu_choice)"

  case "$choice" in
    1)
      action_cron_show
      ;;
    2)
      set_cron_for_main "0 2 * * *"
      ui_msg "Ergebnis" "Cron-Eintrag fuer main.sh auf taeglich 02:00 gesetzt."
      ;;
    3)
      set_cron_for_main "0 4 * * *"
      ui_msg "Ergebnis" "Cron-Eintrag fuer main.sh auf taeglich 04:00 gesetzt."
      ;;
    4)
      if ui_confirm "Bestaetigung" "Cron-Eintrag fuer main.sh wirklich entfernen?"; then
        remove_cron_for_main
        ui_msg "Ergebnis" "Cron-Eintrag fuer main.sh wurde entfernt."
      fi
      ;;
    *)
      return 0
      ;;
  esac
}

function run_startpage() {
  while true; do
    local choice
    choice="$(ui_main_menu_choice)"

    case "$choice" in
      1) action_check_updates_all ;;
      2) action_show_vm_status ;;
      3) action_manual_vm_check ;;
      4) action_state_reset ;;
      5) action_show_env ;;
      6) action_cron_management ;;
      7)
        log_info "CLI durch Benutzer beendet."
        break
        ;;
      *)
        ui_error "Ungueltige Auswahl: $choice"
        ;;
    esac
  done
}

trap cleanup_tty EXIT INT TERM

init_runtime
run_startpage

