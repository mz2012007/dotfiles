#!/usr/bin/env bash
# run-in-float.sh — robust: run script in tmux popup (if inside tmux & supports popup),
# otherwise open in a floating terminal emulator (kitty/alacritty/xterm) or fallback to current terminal.

set -euo pipefail

TARGET="${1:-}"
shift || true
ARGS=("$@")

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 /path/to/script [args...]"
  exit 2
fi
if [[ ! -f "$TARGET" ]]; then
  echo "Target not found: $TARGET"
  exit 3
fi

POPUP_WIDTH="90%"
POPUP_HEIGHT="90%"

# compare tmux version (returns 0 if tmux_ver >= req_ver)
version_ge() {
  # usage: version_ge actual required
  local act="$1" req="$2"
  # extract major.minor from strings like 3.5a, 3.2-rc1, 4, 5a -> "3.5", "3.2", "4", "5"
  local a b am aj bm
  a=$(echo "$act" | grep -oE '^[0-9]+(\.[0-9]+)?' || echo "0.0")
  b=$(echo "$req" | grep -oE '^[0-9]+(\.[0-9]+)?' || echo "0.0")
  am=${a%%.*}
  aj=${a#*.}
  bm=${b%%.*}
  bj=${b#*.}
  [[ "$aj" == "$a" ]] && aj=0
  [[ "$bj" == "$b" ]] && bj=0
  # numeric compare
  if ((am > bm)); then
    return 0
  elif ((am < bm)); then
    return 1
  else
    # same major
    if ((aj >= bj)); then
      return 0
    else
      return 1
    fi
  fi
}

run_in_tmux_popup() {
  #tmux split-window -v -p 70 "bash -lc '\"$TARGET\" ${ARGS[*]@Q}'"
  tmux new-window -n "float-$(basename "$TARGET")" "bash -lc '\"$TARGET\" ${ARGS[*]@Q}'"
}

run_in_terminal() {
  if command -v kitty >/dev/null 2>&1; then
    kitty --title "float: $(basename "$TARGET")" bash -lc "\"$TARGET\" ${ARGS[*]@Q}" &
    return
  fi
  if command -v alacritty >/dev/null 2>&1; then
    alacritty -t "float: $(basename "$TARGET")" -e bash -lc "\"$TARGET\" ${ARGS[*]@Q}" &
    return
  fi
  if command -v xterm >/dev/null 2>&1; then
    xterm -T "float: $(basename "$TARGET")" -e bash -lc "\"$TARGET\" ${ARGS[*]@Q}" &
    return
  fi

  # fallback: same terminal
  echo "No floating terminal found (kitty/alacritty/xterm). Running here..."
  exec bash -lc "\"$TARGET\" ${ARGS[*]@Q}"
}

# Main logic
if [[ -n "${TMUX-}" ]]; then
  # We're inside tmux: check version supports popup (>= 3.2)
  if command -v tmux >/dev/null 2>&1; then
    raw=$(tmux -V 2>/dev/null | awk '{print $2}' || true)
    # ensure parsing robust: use grep to extract digits
    ver=$(echo "$raw" | grep -oE '^[0-9]+(\.[0-9]+)?' || echo "0.0")
    if version_ge "$ver" "3.2"; then
      run_in_tmux_popup
      exit 0
    else
      # old tmux: fallback to running in external terminal
      run_in_terminal
      exit 0
    fi
  else
    run_in_terminal
    exit 0
  fi
else
  # not inside tmux -> try to open floating terminal
  run_in_terminal
  exit 0
fi
