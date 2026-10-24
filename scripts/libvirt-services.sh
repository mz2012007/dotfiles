#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_DIR="/etc/sv"
RUN_DIR="/var/service"

SERVICES=(
  virtinterfaced
  virtlockd
  virtlogd
  virtlxcd
  virtnetworkd
  virtnodedevd
  virtnwfilterd
  virtproxyd
  virtqemud
  virtsecretd
  virtstoraged
  virtvboxd
)

if ((EUID != 0)); then
  exec sudo bash "$0" "$@"
fi

is_available() {
  [[ -d "$SERVICE_DIR/$1" ]]
}

is_enabled() {
  [[ -e "$RUN_DIR/$1" || -L "$RUN_DIR/$1" ]]
}

show_status() {
  local service
  printf '\n%-20s %s\n' "SERVICE" "STATUS"
  printf '%s\n' "----------------------------------------"

  for service in "${SERVICES[@]}"; do
    is_available "$service" || continue

    if ! is_enabled "$service"; then
      printf '%-20s %s\n' "$service" "Disabled"
    else
      sv status "$RUN_DIR/$service" 2>&1 || true
    fi
  done
}

enable_all() {
  local service
  local failed=0

  echo "WARNING: Enabling every daemon may cause conflicts."
  echo "The legacy libvirtd daemon may conflict with modular daemons."
  read -r -p "Continue anyway? Type YES: " answer
  [[ "$answer" == "YES" ]] || return 0

  for service in "${SERVICES[@]}"; do
    is_available "$service" || continue

    if ! is_enabled "$service"; then
      ln -s "$SERVICE_DIR/$service" "$RUN_DIR/$service" || {
        echo "Failed to enable: $service"
        failed=1
        continue
      }
    fi
  done

  echo "Waiting for runit to start services..."
  sleep 2

  for service in "${SERVICES[@]}"; do
    is_available "$service" || continue
    is_enabled "$service" || continue

    if ! sv status "$RUN_DIR/$service" >/dev/null 2>&1; then
      echo "Could not start: $service"
      failed=1
    fi
  done

  ((failed == 0)) && echo "Enable operation completed."
  return 0
}

disable_all() {
  local service
  local answer

  read -r -p "Stop and disable all detected services? Type YES: " answer
  [[ "$answer" == "YES" ]] || return 0

  for service in "${SERVICES[@]}"; do
    is_available "$service" || continue
    is_enabled "$service" || continue

    sv down "$RUN_DIR/$service" 2>/dev/null || true
  done

  for service in "${SERVICES[@]}"; do
    is_available "$service" || continue
    is_enabled "$service" || continue

    rm -f -- "$RUN_DIR/$service"
    echo "Disabled: $service"
  done

  echo "Disable operation completed."
}

while true; do
  printf '\n=== Libvirt Service Manager (runit) ===\n'
  printf '1) Enable all services\n'
  printf '2) Stop and disable all services\n'
  printf '3) Show status\n'
  printf '4) Exit\n'
  read -r -p "Choose an option: " choice

  case "$choice" in
  1) enable_all ;;
  2) disable_all ;;
  3) show_status ;;
  4) exit 0 ;;
  *) echo "Invalid option." ;;
  esac
done
