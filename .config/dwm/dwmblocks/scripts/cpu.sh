#      #!/usr/bin/env bash
#      #
EDITOR="nvim"
TERMINAL="alacritty"
#      # Visualize CPU usage per-core on Linux
#      # Author: Dave Eddy <ysap@daveeddy.com>
#      #
#
#      declare -A CURRENT
#      declare -A PREVIOUS
#      declare -a ALL_CPUS
#
#      # Copy the data from the current array into the previous array
#      copy-data() {
#          PREVIOUS=()
#          local key value
#          for key in "${!CURRENT[@]}"; do
#              value=${CURRENT[$key]}
#              PREVIOUS[$key]=$value
#          done
#      }
#
#      # Read /proc/stat and populate CURRENT array
#      read-proc() {
#          local key user nice system idle iowait irq softirq steal guest guest_nice
#          CURRENT=()
#          for key in "${ALL_CPUS[@]}"; do
#              CURRENT[$key]=
#          done
#
#          local busy value num
#          while read -r key user nice system idle iowait irq softirq steal guest guest_nice; do
#              [[ $key != cpu* ]] && continue
#              num=${key#cpu}
#              [[ $key == cpu ]] && num="A"
#
#              busy=$((user + nice + system + irq + softirq + steal + guest + guest_nice))
#              idle=$((idle + iowait))
#              value="$busy $idle"
#
#              CURRENT[$num]=$value
#          done < /proc/stat
#      }
#
#      # Return a single CPU bar string
#      print-bar() {
#          local key=$1
#          local output=""
#          local busy1 idle1 busy2 idle2
#          read -r busy1 idle1 <<< "${PREVIOUS[$key]}"
#          read -r busy2 idle2 <<< "${CURRENT[$key]}"
#
#          local usage
#          if [[ -z $busy1 || -z $busy2 ]]; then
#              # Offline CPU
#              output+="^c#666666^ cpu$key offline "
#          else
#              local busy=$((busy2 - busy1))
#              local idle=$((idle2 - idle1))
#              local total=$((busy + idle))
#              usage=$((1000 * busy / total))  # scale 0..1000
#
#              local int=$((usage / 10))
#              local frac=$((usage % 10))
#              local perc="$int.$frac"
#
#              # Choose color
#              local bg
#              if (( usage >= 800 )); then
#                  bg="#ff0000"
#              elif (( usage >= 400 )); then
#                  bg="#ffaf00"
#              else
#                  bg="#5faf5f"
#              fi
#
#              output+="^c$bg^ c$key ^c#ffffff^$perc% "
#          fi
#
#          echo -n "$output"
#      }
#
#      # Aggregate all CPU bars into one string
#      visualize-data() {
#          local result=""
#          local key
#          for key in "${ALL_CPUS[@]}"; do
#              result+=$(print-bar "$key")
#          done
#          echo "$result"
#      }
#
#      # Detect all CPUs including total "all"
#      read-all-cpus() {
#          ALL_CPUS=(/sys/devices/system/cpu/cpu[0-9]*)
#          ALL_CPUS=("${ALL_CPUS[@]##*/cpu}")
#          ALL_CPUS=("A" "${ALL_CPUS[@]}")
#      }
#
#      main() {
#          read-all-cpus
#          read-proc
#          sleep 0.1
#
#          copy-data
#          read-proc
#          nm=$(visualize-data)
#
#          # Print all CPU bars in one line
#          printf "%s\n" "$nm"
#      }
#
#      main "$@"
#
#!/usr/bin/env bash

case $BLOCK_BUTTON in
1) setsid -f "$TERMINAL" -e htop ;;
3) setsid -f "$TERMINAL" -e "$EDITOR" "$0" ;;
6) notify-send "🖥 CPU module " "\- Shows CPU temperature.
- (shift + touch) to open code 
- () show intensive processes.
- Middle click to open htop." ;;
esac

#sensors | awk '/Core 0/ {print "🌡" $3}'

GREEN="#50fa7b"
YELLOW="#f1fa8c"
ORANGE="#ffb86c"
RED="#ff5555"

temp=$(sensors | awk '/Core 0/ {gsub(/[+°C]/,"",$3); print int($3)}')

if [ "$temp" -ge 85 ]; then
  col="$RED"
elif [ "$temp" -ge 70 ]; then
  col="$ORANGE"
elif [ "$temp" -ge 50 ]; then
  col="$YELLOW"
else
  col="$GREEN"
fi

printf "^c%s^%s°C 🌡%s\n" "$col" "$temp" ""$RESET""
