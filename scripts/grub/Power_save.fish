#!/usr/bin/env bash
#
# power-saver.sh - Aggressive power-saving script for AMD Ryzen APU laptops
#
# Applies CPU, iGPU, scheduler, and power-limit tuning to minimize
# power consumption at the cost of performance.
#
# Usage:
#   sudo ./power-saver.sh          # Apply power-saving settings
#   sudo ./power-saver.sh restore  # Restore default settings
#
set -uo pipefail

# ---------------------------------------------------------------------------
# Root check
# Writing to /sys/** and running ryzenadj both require root privileges.
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]
 then
  echo "⚠️  Run as root: sudo $0"
  exit 1
    fi

# ---------------------------------------------------------------------------
# CPU tuning
# ---------------------------------------------------------------------------
    Cpu() {
  echo "⚙️  Configuring CPU..."

  # Lock max frequency to 1.0 GHz (1000000 kHz) on every core.
  # This caps the CPU hard so it never ramps up under load.
  for i in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
    echo 1000000 >"$i" 2>/dev/null || true
  done

  # Set cpufreq governor to "powersave".
  # On amd-pstate-epp this is effectively the lowest-power mode.
  for i in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo powersave >"$i" 2>/dev/null || true
  done

  echo passive | sudo tee /sys/devices/system/cpu/amd_pstate/status

  # Disable CPU Boost (turbo).
  # Prevents the CPU from exceeding its base clock, saving power and heat.
  echo 0 >/sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true

  # Set Energy Performance Preference (EPP) to "power".
  # Biases the hardware toward power saving over responsiveness.
  for i in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo power >"$i" 2>/dev/null || true
  done
}

# ---------------------------------------------------------------------------
# iGPU tuning
#
# Note: HawkPoint (Ryzen 7 260) does not support direct gfxclk / socclk
# control. Instead we pin the DPM level to "low", which forces the iGPU
# to its minimum performance state. This is the strongest available lever.
# ---------------------------------------------------------------------------
    Gpu() {
  echo "🎮 Configuring iGPU..."

  # Force the iGPU into its lowest DPM performance level ("low").
  # This pins the GPU clock to the minimum, minimizing its power draw.
  # Locate every DRM card that exposes amdgpu DPM controls
  for dpm in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
    [[ -e "$dpm" ]] || continue
    echo low >"$dpm" 2>/dev/null || true
    echo "   ↳ $(dirname "$dpm") → low"
  done

  # Also set the DPM state (older interface, harmless if absent)
  for state in /sys/class/drm/card*/device/power_dpm_state; do
    [[ -e "$state" ]] || continue
    echo battery >"$state" 2>/dev/null || true
  done

  # Enable maximum panel power savings (ABM level 4).
  # Reduces backlight power on supported eDP panels.
  for i in /sys/class/drm/*/amdgpu/panel_power_savings; do
    echo 4 >"$i" 2>/dev/null || true
  done
}

# ---------------------------------------------------------------------------
# Lock iGPU DPM against external resets
#
# Some components (TLP, power-profiles-daemon, amdgpu runtime PM) may reset
# power_dpm_force_performance_level back to "auto". This watcher re-applies
# "low" whenever it drifts, keeping the iGPU pinned to its lowest state.
# ---------------------------------------------------------------------------
    GpuWatch() {
  echo "🔒 Locking iGPU DPM to 'low' (Ctrl+C to stop)..."

  while true; do
    for dpm in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
      [[ -e "$dpm" ]] || continue
      current=$(cat "$dpm" 2>/dev/null || echo "")
      if [[ "$current" != "low" ]]; then
        echo low >"$dpm" 2>/dev/null || true
      fi
    done
    sleep 2
  done
}

# ---------------------------------------------------------------------------
# sched_ext scheduler tuning
# ---------------------------------------------------------------------------
    Scheduler() {
  echo "🧠 Configuring scheduler..."

  # Skip if scx_lavd is already running in powersave mode.
  if scxctl get 2>/dev/null | grep -qi "lavd.*powersave"; then
    echo "   ℹ️  lavd is already running in powersave mode."
    return 0
  fi

  # Ensure scx_loader service is enabled under runit, then start it.
  [ -e /var/service/scx_loader ] || ln -s /etc/sv/scx_loader /var/service/ 2>/dev/null || true
  sv status scx_loader >/dev/null 2>&1 || sv start scx_loader

  # Switch to scx_lavd in powersave mode.
  # Try both possible naming conventions ("scx_lavd" and "lavd").
  scxctl switch --sched scx_lavd --mode powersave 2>/dev/null ||
    scxctl switch --sched lavd --mode powersave 2>/dev/null ||
    echo "   ⚠️  Failed to switch scheduler."
}

# ---------------------------------------------------------------------------
# RyzenAdj power limits
# ---------------------------------------------------------------------------
    Ryzenadj() {
  echo "🔥 Configuring Ryzen power limits..."

  # Skip if ryzenadj is not installed.
  if ! command -v ryzenadj >/dev/null 2>&1; then
    echo "   ⚠️  ryzenadj not installed. Skipping."
    return 0
  fi

  # Apply very aggressive power limits:
  #   --stapm-limit  : sustained power limit (5 W)
  #   --fast-limit   : short boost power limit (5 W)
  #   --slow-limit   : medium-term power limit (5 W)
  #   --tctl-temp    : max CPU temperature (50 °C)
  #   --power-saving : enable power-saving bias
  ryzenadj \
    --stapm-limit=5000 \
    --fast-limit=5000 \
    --slow-limit=5000 \
    --tctl-temp=50 \
    --power-saving
}

# ---------------------------------------------------------------------------
# Gigabyte fan control
# ---------------------------------------------------------------------------
    Gigabyte() {
  echo "❄️  Configuring fans..."

  # Skip if gigabytectl is not installed.
  if ! command -v gigabytectl >/dev/null 2>&1; then
    echo "   ⚠️  gigabytectl not installed. Skipping."
    return 0
  fi

  # Set fan profile to silent, then print the current mode.
  gigabytectl fan-mode set silent
  gigabytectl fan-mode get
}

# ---------------------------------------------------------------------------
# Restore defaults
# Reverts all changes applied by the power-saving functions above.
# ---------------------------------------------------------------------------
    Restore() {
  echo "♻️  Restoring defaults..."

  # --- CPU ---
  # Return governor to "schedutil" (default on most modern kernels).
  for i in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo schedutil >"$i" 2>/dev/null || true
  done
  # Re-enable CPU Boost.
  echo 1 >/sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
  # Reset EPP to balanced.
  for i in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo balance_performance >"$i" 2>/dev/null || true
  done
  # Restore max frequency to the hardware maximum.
  for i in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
    cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq >"$i" 2>/dev/null || true
  done

  # --- GPU ---
  # Return DPM level to automatic.
  echo auto >/sys/class/drm/card0/device/power_dpm_force_performance_level 2>/dev/null || true
  # Disable panel power savings.
  for i in /sys/class/drm/*/amdgpu/panel_power_savings; do
    echo 0 >"$i" 2>/dev/null || true
  done

  # --- Scheduler ---
  # Switch scx_lavd back to automatic mode.
  scxctl switch --sched scx_lavd --mode auto 2>/dev/null ||
    scxctl switch --sched lavd --mode auto 2>/dev/null || true

  # --- RyzenAdj ---
  # Reset power limits to typical stock values.
  # Adjust these numbers to match your laptop's stock firmware.
  if command -v ryzenadj >/dev/null 2>&1; then
    ryzenadj \
      --stapm-limit=28000 \
      --fast-limit=30000 \
      --slow-limit=28000 \
      --tctl-temp=90 2>/dev/null || true
  fi

  echo "✅ Defaults restored."
}

    Apps() {
  pkill emacs
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
    main() {
  case "${1:-}" in
  restore)
    Restore
    ;;
  "")
    Cpu
    Gpu
    Scheduler
    Ryzenadj
    Gigabyte
    Apps
    echo "✅ Done."
    ;;
  *)
    echo "Usage: $0 [restore]"
    exit 1
    ;;
  esac
}

main "$@"
