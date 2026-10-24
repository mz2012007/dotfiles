#!/usr/bin/env bash
#
# Power_save.sh — AMD Ryzen APU laptop power management
# Profiles live in an external file (default: ./power-save.conf)
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${POWER_SAVE_CONF:-$SCRIPT_DIR/power-save.conf}"
LOG_FILE="$SCRIPT_DIR/power-save.log"
STATE_FILE="$SCRIPT_DIR/power-save.recent"
PROFILE_FILE="$SCRIPT_DIR/power-save.profile"
RYZEN_BASELINE="$SCRIPT_DIR/power-save.ryzenadj.before"

if [[ $EUID -ne 0 ]]; then
  exec sudo -E POWER_SAVE_CONF="$CONFIG_FILE" bash "$0" "$@"
fi

touch "$LOG_FILE" "$STATE_FILE" 2>/dev/null || true
if [[ -n "${SUDO_USER:-}" ]]; then
  chown "$SUDO_USER" "$LOG_FILE" "$STATE_FILE" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Colors (auto-disable when piped / NO_COLOR set)
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
  C_CYAN=$'\033[36m'
  C_GREY=$'\033[90m'
else
  C_RESET=
  C_BOLD=
  C_DIM=
  C_RED=
  C_GREEN=
  C_YELLOW=
  C_BLUE=
  C_MAGENTA=
  C_CYAN=
  C_GREY=
fi

# ---------------------------------------------------------------------------
# Logging  (file = plain text, console = colored)
# ---------------------------------------------------------------------------
_log_line() {
  local level="$1"
  shift
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  printf '[%s] [%-5s] %s\n' "$ts" "$level" "$*" >>"$LOG_FILE"
}
log() { _log_line "INFO" "$@"; }
log_warn() {
  _log_line "WARN" "$@"
  echo "  ${C_YELLOW}⚠  $*${C_RESET}" >&2
}
log_err() {
  _log_line "ERROR" "$@"
  echo "  ${C_RED}✗  $*${C_RESET}" >&2
}
say() {
  echo "${C_BOLD}$*${C_RESET}"
  _log_line "INFO" "$*"
}
section() {
  echo "${C_BOLD}${C_CYAN}── $* ────────────────────────────────────────${C_RESET}"
  _log_line "INFO" "── $* ──"
}
hr() { _log_line "INFO" "${C_BOLD}${C_BLUE}═══════════════════════════════════════════════════════════${C_RESET}"; }

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
COUNT_SET=0
COUNT_OK=0
COUNT_SKIP=0
COUNT_FAIL=0
reset_counters() {
  COUNT_SET=0
  COUNT_OK=0
  COUNT_SKIP=0
  COUNT_FAIL=0
}

# ---------------------------------------------------------------------------
# State tracking
# ---------------------------------------------------------------------------
state_has() {
  local path="$1"
  [[ -s "$STATE_FILE" ]] || return 1
  awk -F'\t' -v p="$path" '$1==p{f=1} END{exit !f}' "$STATE_FILE"
}
save_orig() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  state_has "$path" && return 0
  local val
  val=$(cat "$path" 2>/dev/null) || return 0
  printf '%s\t%s\n' "$path" "$val" >>"$STATE_FILE"
  log "SAVED   $path = $val"
}
write_val() {
  local path="$1" value="$2"
  if [[ ! -e "$path" ]]; then
    log "SKIP    $path (missing)"
    COUNT_SKIP=$((COUNT_SKIP + 1))
    return 0
  fi
  save_orig "$path"
  local current
  current=$(cat "$path" 2>/dev/null || echo "")
  if [[ "$current" == "$value" ]]; then
    log "OK      $path = $value (unchanged)"
    COUNT_OK=$((COUNT_OK + 1))
    return 0
  fi
  if printf '%s\n' "$value" >"$path" 2>/dev/null; then
    log "SET     $path = $value (was: $current)"
    COUNT_SET=$((COUNT_SET + 1))
    return 0
  fi
  log "FAIL    $path = $value (was: $current)"
  COUNT_FAIL=$((COUNT_FAIL + 1))
  return 1
}
write_glob() {
  local pattern="$1" value="$2" f
  for f in $pattern; do
    [[ -e "$f" ]] || continue
    write_val "$f" "$value"
  done
}

# ---------------------------------------------------------------------------
# Load external config
# ---------------------------------------------------------------------------
[[ -f "$CONFIG_FILE" ]] || {
  echo "ERROR: config not found: $CONFIG_FILE" >&2
  exit 1
}
# shellcheck disable=SC1090
source "$CONFIG_FILE" || {
  echo "ERROR: failed to source $CONFIG_FILE" >&2
  exit 1
}
if ! declare -p PROFILES >/dev/null 2>&1 || [[ ${#PROFILES[@]} -eq 0 ]]; then
  echo "ERROR: PROFILES array missing/empty in $CONFIG_FILE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Profile vars
# ---------------------------------------------------------------------------
CPU_MAX_FREQ=""
CPU_GOVERNOR=""
AMD_PSTATE=""
CPU_BOOST=""
GPU_DPM=""
#GPU_DPM_STATE=""
PANEL_SAVINGS=""
SCHED_NAME=""
SCHED_MODE=""
STAPM=""
FAST=""
SLOW=""
TCTL=""
RYZEN_PS=""
FAN_MODE=""
APPLY_CMDS=()
RESTORE_CMDS=()

reset_profile_vars() {
  CPU_MAX_FREQ=""
  CPU_GOVERNOR=""
  AMD_PSTATE=""
  CPU_BOOST=""
  GPU_DPM=""
  #  GPU_DPM_STATE=""
  PANEL_SAVINGS=""
  SCHED_NAME=""
  SCHED_MODE=""
  STAPM=""
  FAST=""
  SLOW=""
  TCTL=""
  RYZEN_PS=""
  FAN_MODE=""
  APPLY_CMDS=()
  RESTORE_CMDS=()
}
profile_exists() { declare -f "profile_${1//-/_}" >/dev/null 2>&1; }
load_profile() {
  local name="$1" fn="profile_${1//-/_}"
  reset_profile_vars
  if ! declare -f "$fn" >/dev/null 2>&1; then
    log_err "Profile '$name' not defined (fn $fn missing)"
    return 1
  fi
  "$fn"
  log "Loaded profile: $name"
  return 0
}

# ---------------------------------------------------------------------------
# Custom commands
# ---------------------------------------------------------------------------
run_apply_cmds() {
  [[ ${#APPLY_CMDS[@]} -eq 0 ]] && return 0
  section "Apply commands"
  local c
  for c in "${APPLY_CMDS[@]}"; do
    [[ -z "$c" ]] && continue
    if bash -c "$c" >>"$LOG_FILE" 2>&1; then
      log "APPLY   ok: $c"
    else
      log_warn "apply cmd failed: $c"
    fi
  done
}
run_restore_cmds_of() {
  local name="$1"
  [[ -z "$name" ]] && return 0
  load_profile "$name" >/dev/null 2>&1 || return 0
  [[ ${#RESTORE_CMDS[@]} -eq 0 ]] && return 0
  section "Restore commands ($name)"
  local c
  for c in "${RESTORE_CMDS[@]}"; do
    [[ -z "$c" ]] && continue
    if bash -c "$c" >>"$LOG_FILE" 2>&1; then
      log "RESTORE ok: $c"
    else
      log_warn "restore cmd failed: $c"
    fi
  done
}

# ---------------------------------------------------------------------------
# CPU / iGPU / Scheduler / Ryzenadj / Fan
# ---------------------------------------------------------------------------
Cpu() {
  section "CPU"
  [[ -n "$CPU_MAX_FREQ" ]] &&
    write_glob "/sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq" "$CPU_MAX_FREQ"
  [[ -n "$CPU_GOVERNOR" ]] &&
    write_glob "/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor" "$CPU_GOVERNOR"
  [[ -n "$AMD_PSTATE" ]] &&
    write_val /sys/devices/system/cpu/amd_pstate/status "$AMD_PSTATE"
  [[ -n "$CPU_BOOST" ]] &&
    write_val /sys/devices/system/cpu/cpufreq/boost "$CPU_BOOST"
}

Gpu() {
  section "iGPU"
  [[ -n "$GPU_DPM" ]] &&
    write_glob "/sys/class/drm/card*/device/power_dpm_force_performance_level" "$GPU_DPM"
  #[[ -n "$GPU_DPM_STATE" ]] &&
  #  write_glob "/sys/class/drm/card*/device/power_dpm_state" "$GPU_DPM_STATE"
  [[ -n "$PANEL_SAVINGS" ]] &&
    write_glob "/sys/class/drm/*/amdgpu/panel_power_savings" "$PANEL_SAVINGS"
}

Scheduler() {
  section "Scheduler"
  command -v scxctl >/dev/null 2>&1 || {
    log_warn "scxctl not installed"
    return 0
  }
  [[ -z "$SCHED_NAME" || -z "$SCHED_MODE" ]] && {
    log "SKIP    scheduler (profile has none)"
    return 0
  }
  local name="$SCHED_NAME" mode="$SCHED_MODE" short="${SCHED_NAME#scx_}"

  if [[ -d /etc/sv/scx_loader ]]; then
    [[ -e /var/service/scx_loader ]] || ln -s /etc/sv/scx_loader /var/service/ 2>/dev/null || true
    command -v sv >/dev/null 2>&1 && sv status scx_loader >/dev/null 2>&1 ||
      sv start scx_loader >>"$LOG_FILE" 2>&1 || true
  else
    log "SCHED   no /etc/sv/scx_loader — using scxctl directly"
  fi

  local current rc
  current=$(scxctl get 2>&1)
  rc=$?
  current=$(echo "$current" | tr '\n' ' ')
  log "SCHED   scxctl get (rc=$rc): $current"
  if echo "$current" | grep -qiE "(${short}|${name}).*${mode}"; then
    log "SCHED   already on $name/$mode"
    return 0
  fi
  local action=switch
  if [[ $rc -ne 0 ]] || [[ -z "$current" ]] ||
    echo "$current" | grep -qiE 'no scheduler|not running|none|nothing|inactive|failed'; then
    action=start
  fi
  log "SCHED   action=$action sched=$name mode=$mode"
  if scxctl "$action" --sched "$name" --mode "$mode" >>"$LOG_FILE" 2>&1 ||
    scxctl "$action" --sched "$short" --mode "$mode" >>"$LOG_FILE" 2>&1; then
    log "SCHED   $action ok"
  else
    log_warn "failed to $action scheduler"
  fi
}

Ryzenadj() {
  section "RyzenAdj"
  command -v ryzenadj >/dev/null 2>&1 || {
    log_warn "ryzenadj not installed"
    return 0
  }
  [[ ! -f "$RYZEN_BASELINE" ]] && { ryzenadj --dump-table >"$RYZEN_BASELINE" 2>/dev/null || true; }
  local args=()
  [[ -n "$STAPM" ]] && args+=("--stapm-limit=$STAPM")
  [[ -n "$FAST" ]] && args+=("--fast-limit=$FAST")
  [[ -n "$SLOW" ]] && args+=("--slow-limit=$SLOW")
  [[ -n "$TCTL" ]] && args+=("--tctl-temp=$TCTL")
  [[ "$RYZEN_PS" == "1" ]] && args+=("--power-saving")
  [[ ${#args[@]} -eq 0 ]] && {
    log "SKIP    ryzenadj (no limits)"
    return 0
  }
  if ryzenadj "${args[@]}" >>"$LOG_FILE" 2>&1; then
    log "RYZEN   applied: ${args[*]}"
  else
    log_warn "ryzenadj failed: ${args[*]}"
  fi
}

Gigabyte() {
  section "Fans"
  command -v gigabytectl >/dev/null 2>&1 || {
    log_warn "gigabytectl not installed"
    return 0
  }
  [[ -z "$FAN_MODE" ]] && {
    log "SKIP    fan mode (none)"
    return 0
  }
  if ! state_has "gigabytectl:fan-mode"; then
    local cur
    cur=$(gigabytectl fan-mode get 2>/dev/null | tr '\n' ' ' | xargs)
    printf 'gigabytectl:fan-mode\t%s\n' "$cur" >>"$STATE_FILE"
    log "SAVED   fan-mode = $cur"
  fi
  if gigabytectl fan-mode set "$FAN_MODE" >>"$LOG_FILE" 2>&1; then
    log "FAN     set to $FAN_MODE"
  else
    log_warn "failed to set fan mode"
  fi
}

# ---------------------------------------------------------------------------
# Battery
# ---------------------------------------------------------------------------
battery_info() {
  local found=0 bat
  for bat in /sys/class/power_supply/BAT*; do
    [[ -e "$bat" ]] || continue
    found=1
    local name status capacity power_now voltage_now energy_now energy_full
    local charge_now charge_full cycle
    name=$(basename "$bat")
    status=$(cat "$bat/status" 2>/dev/null || echo "?")
    capacity=$(cat "$bat/capacity" 2>/dev/null || echo "?")
    power_now=$(cat "$bat/power_now" 2>/dev/null || echo "")
    voltage_now=$(cat "$bat/voltage_now" 2>/dev/null || echo "")
    energy_now=$(cat "$bat/energy_now" 2>/dev/null || echo "")
    energy_full=$(cat "$bat/energy_full" 2>/dev/null || echo "")
    charge_now=$(cat "$bat/charge_now" 2>/dev/null || echo "")
    charge_full=$(cat "$bat/charge_full" 2>/dev/null || echo "")
    cycle=$(cat "$bat/cycle_count" 2>/dev/null || echo "")

    local pwr_str="" vol_str="" energy_str="" remain_str=""
    [[ -n "$power_now" ]] && pwr_str=$(awk -v p="$power_now" 'BEGIN{printf "%.2f W", p/1e6}')
    [[ -n "$voltage_now" ]] && vol_str=$(awk -v v="$voltage_now" 'BEGIN{printf "%.2f V", v/1e6}')

    if [[ -n "$energy_now" && -n "$energy_full" ]]; then
      energy_str=$(awk -v n="$energy_now" -v f="$energy_full" \
        'BEGIN{printf "%.1f/%.1f Wh", n/1e6, f/1e6}')
    elif [[ -n "$charge_now" && -n "$charge_full" && -n "$voltage_now" ]]; then
      energy_str=$(awk -v n="$charge_now" -v f="$charge_full" -v v="$voltage_now" \
        'BEGIN{printf "%.1f/%.1f Wh", n*v/1e12, f*v/1e12}')
    fi

    if [[ -n "$power_now" && "$power_now" -gt 0 ]]; then
      local e_now="$energy_now"
      [[ -z "$e_now" && -n "$charge_now" && -n "$voltage_now" ]] &&
        e_now=$(awk -v c="$charge_now" -v v="$voltage_now" 'BEGIN{printf "%d", c*v/1e6}')
      [[ -n "$e_now" ]] && remain_str=$(awk -v e="$e_now" -v p="$power_now" \
        'BEGIN{h=e/p; hh=int(h); mm=int((h-hh)*60); printf "%dh %02dm", hh, mm}')
    fi

    local sc="$C_GREEN"
    case "$status" in
    Discharging) sc="$C_YELLOW" ;;
    Charging) sc="$C_CYAN" ;;
    Full) sc="$C_GREEN" ;;
    *) sc="$C_GREY" ;;
    esac

    printf '  %s%-6s%s  %s%-12s%s  %s%3s%%%s' \
      "$C_BOLD" "$name" "$C_RESET" \
      "$sc" "$status" "$C_RESET" \
      "$C_BOLD" "$capacity" "$C_RESET"
    [[ -n "$pwr_str" ]] && printf '   %s' "$pwr_str"
    [[ -n "$vol_str" ]] && printf '   %s' "$vol_str"
    [[ -n "$energy_str" ]] && printf '   %s' "$energy_str"
    [[ -n "$cycle" ]] && printf '   cycles %s' "$cycle"
    echo
    [[ -n "$remain_str" ]] &&
      printf '           %s→ ~%s remaining%s\n' "$C_DIM" "$remain_str" "$C_RESET"
  done
  [[ $found -eq 1 ]] || echo "  ${C_GREY}(no battery detected)${C_RESET}"
}

# ---------------------------------------------------------------------------
# Map sysfs path → profile target value
# ---------------------------------------------------------------------------
profile_target_for_path() {
  case "$1" in
  */scaling_governor) echo "$CPU_GOVERNOR" ;;
  */scaling_max_freq) echo "$CPU_MAX_FREQ" ;;
  */amd_pstate/status) echo "$AMD_PSTATE" ;;
  */cpufreq/boost) echo "$CPU_BOOST" ;;
  */power_dpm_force_performance_level) echo "$GPU_DPM" ;;
    # */power_dpm_state) echo "$GPU_DPM_STATE" ;;
  */panel_power_savings) echo "$PANEL_SAVINGS" ;;
  *) echo "" ;;
  esac
}

# Skip duplicate cpuN entries (only show cpu0)
is_dup_cpu() {
  [[ "$1" =~ /cpu([0-9]+)/ ]] || return 1
  [[ "${BASH_REMATCH[1]}" != "0" ]]
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
Status() {
  echo
  echo "${C_BOLD}${C_CYAN}╔══ power-save · status ═════════════════════════════════╗${C_RESET}"

  local prof="(none)" prof_time=""
  if [[ -f "$PROFILE_FILE" ]]; then
    prof=$(cat "$PROFILE_FILE")
    prof_time=$(date -r "$PROFILE_FILE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null ||
      stat -c '%y' "$PROFILE_FILE" 2>/dev/null | cut -d. -f1)
  fi
  echo "  ${C_DIM}config :${C_RESET} $CONFIG_FILE"
  if [[ "$prof" != "(none)" ]]; then
    echo "  ${C_DIM}profile:${C_RESET} ${C_GREEN}${C_BOLD}$prof${C_RESET}  ${C_DIM}(applied $prof_time)${C_RESET}"
  else
    echo "  ${C_DIM}profile:${C_RESET} ${C_GREY}(none recorded)${C_RESET}"
  fi
  echo "${C_BOLD}${C_CYAN}╚════════════════════════════════════════════════════════╝${C_RESET}"
  echo

  # ── Battery ──
  echo "${C_BOLD}── Battery ─────────────────────────────────────────────${C_RESET}"
  battery_info
  echo

  # ── Settings table ──
  echo "${C_BOLD}── Settings ────────────────────────────────────────────${C_RESET}"

  if [[ ! -s "$STATE_FILE" ]]; then
    echo "  ${C_GREY}(no state file — nothing applied or already restored)${C_RESET}"
    echo
    return 0
  fi

  # Load profile target values
  local target_loaded=0
  if [[ "$prof" != "(none)" ]] && profile_exists "$prof"; then
    load_profile "$prof" >/dev/null 2>&1 && target_loaded=1
  fi

  printf '  %s%-34s %-12s %-12s %-12s %s%s\n' \
    "$C_BOLD" "Setting" "Original" "Applied" "Current" "State" "$C_RESET"
  printf '  %s%s%s\n' "$C_DIM" \
    "──────────────────────────────────────────────────────────────────────────────" \
    "$C_RESET"

  local n_ok=0 n_drift=0 n_reset=0 n_na=0 n_total=0
  local path val name original current applied state_color state_txt

  while IFS=$'\t' read -r path val; do
    [[ -z "$path" ]] && continue
    is_dup_cpu "$path" && continue

    case "$path" in
    gigabytectl:fan-mode)
      name="fan-mode"
      original="$val"
      applied="$FAN_MODE"
      current=$(gigabytectl fan-mode get 2>/dev/null | tr '\n' ' ' | xargs)
      ;;
    /sys/* | /proc/*)
      name=$(echo "$path" |
        sed -E 's|/sys/devices/system/cpu/||; s|/sys/class/drm/||; s|/sys/||; s|/proc/||; s|/device/|/|g; s|cpufreq/||')
      original="$val"
      current=$(cat "$path" 2>/dev/null || echo "?")
      applied=$(profile_target_for_path "$path")
      ;;
    *) continue ;;
    esac

    n_total=$((n_total + 1))

    if [[ -z "$current" || "$current" == "?" ]]; then
      state_color="$C_GREY"
      state_txt="n/a"
      n_na=$((n_na + 1))
    elif [[ -z "$applied" ]]; then
      if [[ "$current" == "$original" ]]; then
        state_color="$C_DIM"
        state_txt="original"
        n_ok=$((n_ok + 1))
      else
        state_color="$C_YELLOW"
        state_txt="changed"
        n_drift=$((n_drift + 1))
      fi
    elif [[ "$current" == "$applied" ]]; then
      if [[ "$applied" == "$original" ]]; then
        state_color="$C_DIM"
        state_txt="unchanged"
        n_ok=$((n_ok + 1))
      else
        state_color="$C_GREEN"
        state_txt="✓ ok"
        n_ok=$((n_ok + 1))
      fi
    elif [[ "$current" == "$original" ]]; then
      state_color="$C_BLUE"
      state_txt="↺ reset"
      n_reset=$((n_reset + 1))
    else
      state_color="$C_RED"
      state_txt="✗ drift"
      n_drift=$((n_drift + 1))
    fi

    printf '  %-34s %-12s %-12s %-12s %s%s%s\n' \
      "$name" "$original" "${applied:-—}" "$current" \
      "$state_color" "$state_txt" "$C_RESET"
  done <"$STATE_FILE"

  echo
  echo "${C_BOLD}── Summary ─────────────────────────────────────────────${C_RESET}"
  printf '  %s%d ok%s · %s%d drift%s · %s%d reset%s · %s%d n/a%s total %d' \
    "$C_GREEN" "$n_ok" "$C_RESET" \
    "$C_YELLOW" "$n_drift" "$C_RESET" \
    "$C_BLUE" "$n_reset" "$C_RESET" \
    "$C_GREY" "$n_na" "$C_RESET" \
    "$n_total"

  echo
  echo "${C_BOLD}── Last 10 log lines ──────────────────────────────────${C_RESET}"
  tail -n 10 "$LOG_FILE" 2>/dev/null | sed 's/^/  /' || echo "  (no log yet)"
  echo
}

# ---------------------------------------------------------------------------
# List / Watch / Restore
# ---------------------------------------------------------------------------
ListProfiles() {
  echo "${C_BOLD}Available profiles${C_RESET} (from ${C_DIM}$CONFIG_FILE${C_RESET}):"
  local p
  for p in "${PROFILES[@]}"; do
    printf '  %s%-14s%s' "$C_GREEN" "$p" "$C_RESET"
    if [[ "$p" == "$(cat "$PROFILE_FILE" 2>/dev/null)" ]]; then
      printf ' %s← active%s' "$C_DIM" "$C_RESET"
    fi
    echo
  done
  echo
  echo "${C_BOLD}Commands:${C_RESET}"
  printf '  %-14s apply a profile\n' "<profile>"
  printf '  %-14s restore original values + run RESTORE_CMDS\n' "restore"
  printf '  %-14s show current vs original vs applied (colored)\n' "status"
  printf '  %-14s keep iGPU DPM locked to low\n' "watch"
  printf '  %-14s this help\n' "list"
}

Watch() {
  say "Locking iGPU DPM to 'low' (Ctrl+C to stop)..."
  while true; do
    for dpm in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
      [[ -e "$dpm" ]] || continue
      local cur
      cur=$(cat "$dpm" 2>/dev/null || echo "")
      if [[ "$cur" != "low" ]]; then
        echo low >"$dpm" 2>/dev/null && log "WATCH   $dpm = $cur → low"
      fi
    done
    sleep 2
  done
}

Restore() {
  section "Restore"
  local last=""
  [[ -f "$PROFILE_FILE" ]] && last=$(cat "$PROFILE_FILE" 2>/dev/null || echo "")
  [[ -n "$last" ]] && run_restore_cmds_of "$last"

  if [[ -s "$STATE_FILE" ]]; then
    local path val
    while IFS=$'\t' read -r path val; do
      [[ -z "$path" ]] && continue
      case "$path" in
      gigabytectl:fan-mode)
        if command -v gigabytectl >/dev/null 2>&1 && [[ -n "$val" ]]; then
          local mode
          mode=$(echo "$val" | awk '{print $1}')
          gigabytectl fan-mode set "$mode" >>"$LOG_FILE" 2>&1 &&
            log "RESTORE fan-mode = $mode" ||
            log_warn "failed to restore fan-mode"
        fi
        ;;
      /sys/* | /proc/*)
        [[ -e "$path" ]] || {
          log "SKIP    $path (missing)"
          continue
        }
        if printf '%s\n' "$val" >"$path" 2>/dev/null; then
          log "RESTORE $path = $val"
        else
          log_warn "failed to restore $path = $val"
        fi
        ;;
      *) log "SKIP    unknown state entry: $path" ;;
      esac
    done <"$STATE_FILE"
  else
    log_warn "No state file — sysfs restore skipped"
  fi

  if command -v ryzenadj >/dev/null 2>&1; then
    ryzenadj --stapm-limit=28000 --fast-limit=30000 --slow-limit=28000 --tctl-temp=90 \
      >>"$LOG_FILE" 2>&1 && log "RESTORE ryzenadj to stock" ||
      log_warn "ryzenadj restore failed"
  fi

  if command -v scxctl >/dev/null 2>&1; then
    local cur rc action
    cur=$(scxctl get 2>&1)
    rc=$?
    if [[ $rc -ne 0 ]] || [[ -z "$cur" ]] ||
      echo "$cur" | grep -qiE 'no scheduler|not running|none|nothing|inactive|failed'; then
      action=start
    else
      action=switch
    fi
    scxctl "$action" --sched scx_lavd --mode auto >>"$LOG_FILE" 2>&1 ||
      scxctl "$action" --sched lavd --mode auto >>"$LOG_FILE" 2>&1 ||
      log_warn "failed to restore scheduler"
  fi

  rm -f "$STATE_FILE" "$PROFILE_FILE" "$RYZEN_BASELINE"
  say "Restored."
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  local cmd="${1:-max-save}"
  hr
  log "power-save invoked: cmd=$cmd argv=($*)"
  log "config: $CONFIG_FILE"
  reset_counters

  case "$cmd" in
  restore) Restore ;;
  status) Status ;;
  list | -h | --help | help) ListProfiles ;;
  watch) Watch ;;
  *)
    if ! profile_exists "$cmd"; then
      log_err "Unknown profile: $cmd"
      ListProfiles
      exit 1
    fi
    load_profile "$cmd" || {
      ListProfiles
      exit 1
    }
    log "profile: $cmd"
    echo "$cmd" >"$PROFILE_FILE"
    Cpu
    Gpu
    Scheduler
    Ryzenadj
    Gigabyte
    run_apply_cmds
    section "Summary"
    log "set=$COUNT_SET ok=$COUNT_OK skip=$COUNT_SKIP fail=$COUNT_FAIL"
    say "✅ Profile '$cmd' applied  (${C_GREEN}set $COUNT_SET${C_RESET}, ${C_DIM}ok $COUNT_OK${C_RESET}, ${C_YELLOW}skip $COUNT_SKIP${C_RESET}, ${C_RED}fail $COUNT_FAIL${C_RESET})"
    log "done: profile=$cmd"
    ;;
  esac

  hr
}

main "$@"
