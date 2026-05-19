#      #!/usr/bin/env bash
#
#      read -r status cap <<<"$(acpi | awk '{print $3, $4}' | tr -d ',%')"
#
#      if [[ "$cap" -le 15 ]]; then
#        bg="#ff0000"
#      elif [[ "$cap" -le 40 ]]; then
#        bg="#ffaf00"
#      else
#        bg="#5faf5f"
#      fi
#
#      icon=""
#      [ "$status" = "Charging" ] && icon=""
#
#      printf "^c#000000^^b%s^ %s %s%% ^b#000000^^c#ffffff^" "$bg" "$icon" "$cap"

#!/usr/bin/env bash

# Prints all batteries, their percentage remaining and an emoji corresponding
# to charge status (🔌 for plugged up, 🔋 for discharging on battery, etc.).
TERMINAL="alacritty"
EDITOR="nvim"

case $BLOCK_BUTTON in
3) notify-send "🔋 Battery module" "🔋: discharging
🛑: not charging
♻: stagnant charge
🔌: charging
⚡: charged
❗: battery very low!
- Scroll to change adjust xbacklight." ;;
4) xbacklight -inc 10 ;;
5) xbacklight -dec 10 ;;
6) setsid -f "$TERMINAL" -e "$EDITOR" "$0" ;;
esac

# Loop through all attached batteries and format the info
for battery in /sys/class/power_supply/BAT?*; do
  # If non-first battery, print a space separator.
  [ -n "${capacity+x}" ] && printf " "
  # Sets up the status and capacity
  case "$(cat "$battery/status" 2>&1)" in
  "Full") status="⚡" ;;
  "Discharging") status="🔋" ;;
  "Charging") status="🔌" ;;
  "Not charging") status="🛑" ;;
  "Unknown") status="♻️" ;;
  *) exit 1 ;;
  esac
  capacity="$(cat "$battery/capacity" 2>&1)"
  # Will make a warn variable if discharging and low
  [ "$status" = "🔋" ] && [ "$capacity" -le 25 ] && warn="❗"
  # Prints the info
  printf "%s%s%d%%" "$status" "$warn" "$capacity"
  unset warn
done && printf "\\n"
