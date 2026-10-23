#!/usr/bin/env bash
#
# core/diff.sh - the diff command.
#
# Compares the entries of two or more generations. The generations are
# compared in the order in which they are given: "hm diff 1 2 3" prints the
# changes from 1 to 2 and from 2 to 3.
#
# An entry is compared by its type, its content hash, its mode, its owner
# and its group. The modification time is recorded metadata, but it is not
# a difference: the apply command ignores it as well, and a copy updates it
# without changing the content.
#
# A difference is a normal result, not an error, therefore the command
# always exits with the success status. The exit code 1 already means a
# generic runtime failure in the contract of HM-Lite.
#
# The command only reads, it takes a shared lock and never touches the
# content store.
#
# The module only defines the diff function. Sourcing it does not run the
# command.
#

# --- Helpers ---------------------------------------------------------------

# _diff_usage
_diff_usage() {
  cat <<'EOF'
Usage: hm diff [--profile NAME] <generation> <generation> [<generation>...]

Compare the entries of two or more generations.

The generations are compared in the given order, every consecutive pair is
one comparison.

Options:
  --profile NAME Require the generations to belong to the profile
  --all          Show the entries that did not change
  -h, --help     Show this help
EOF
}

# _diff_mode MODE
# Print a mode in the octal form that the other commands use. An unexpected
# value is printed unchanged instead of aborting the comparison.
_diff_mode() {
  local mode="$1" octal

  octal="$(hm_mode_to_octal "$mode" 2>/dev/null || printf '%s' "$mode")"
  printf '%s' "${octal:-$mode}"
}

# _diff_load GENERATION VARIABLE
# Store the entries of GENERATION in the associative array VARIABLE. The key
# is the hex encoded path, therefore a path with any byte is safe and the
# keys can be sorted deterministically. The value is the entry record:
#   type HM_FIELD_SEP hex(hash) HM_FIELD_SEP mode HM_FIELD_SEP uid
#   HM_FIELD_SEP gid HM_FIELD_SEP mtime HM_FIELD_SEP size
_diff_load() {
  local generation="$1"
  # The nameref writes into the variable of the caller, shellcheck cannot
  # see through it.
  # shellcheck disable=SC2034
  local -n hm__diff_ref="$2"
  local rows row encoded entry_type hash_hex mode uid gid mtime size

  hm__diff_ref=()

  if ! hm_gen_entries "$generation" rows; then
    hm_die "$HM_EX_DB" "Cannot read the generation $generation from the database."
  fi

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS="$HM_FIELD_SEP" read -r encoded entry_type hash_hex mode uid gid mtime size <<< "$row"
    # shellcheck disable=SC2034
    hm__diff_ref["$encoded"]="$entry_type$HM_FIELD_SEP$hash_hex$HM_FIELD_SEP$mode$HM_FIELD_SEP$uid$HM_FIELD_SEP$gid$HM_FIELD_SEP$mtime$HM_FIELD_SEP$size"
  done <<< "$rows"
}

# _diff_pair FROM TO SHOW_ALL
# Print the differences between the generations FROM and TO.
_diff_pair() {
  local from="$1" to="$2" show_all="$3"
  local -A old=() new=()
  local keys encoded path old_record new_record detail reason
  local o_type o_hash o_mode o_uid o_gid _o_mtime o_size
  local n_type n_hash n_mode n_uid n_gid _n_mtime n_size
  local added=0 removed=0 changed=0 unchanged=0
  local -a reasons=()

  _diff_load "$from" old
  _diff_load "$to" new

  keys="$(printf '%s\n' "${!old[@]}" "${!new[@]}" | sort -u)"

  printf '%sGeneration %s -> %s%s\n' "$HM_C_OUT_HEADING" "$from" "$to" "$HM_C_OUT_RESET"
  printf '\n'

  while IFS= read -r encoded; do
    [[ -n "$encoded" ]] || continue

    old_record="${old[$encoded]:-}"
    new_record="${new[$encoded]:-}"
    hm_hex_decode path "$encoded"

    if [[ -z "$old_record" ]]; then
      added=$((added + 1))
      printf '  %s+ %s%s\n' "$HM_C_OUT_GREEN" "$(hm_path_display "$path")" "$HM_C_OUT_RESET"
      continue
    fi

    if [[ -z "$new_record" ]]; then
      removed=$((removed + 1))
      printf '  %s- %s%s\n' "$HM_C_OUT_RED" "$(hm_path_display "$path")" "$HM_C_OUT_RESET"
      continue
    fi

    IFS="$HM_FIELD_SEP" read -r o_type o_hash o_mode o_uid o_gid _o_mtime o_size <<< "$old_record"
    IFS="$HM_FIELD_SEP" read -r n_type n_hash n_mode n_uid n_gid _n_mtime n_size <<< "$new_record"

    reasons=()

    if [[ "$o_type" != "$n_type" ]]; then
      reasons+=("type $o_type -> $n_type")
    fi

    if [[ "$o_hash" != "$n_hash" ]]; then
      reasons+=("content")
    elif [[ "$o_size" != "$n_size" ]]; then
      reasons+=("size $o_size -> $n_size")
    fi

    if [[ "$o_mode" != "$n_mode" ]]; then
      reasons+=("mode $(_diff_mode "$o_mode") -> $(_diff_mode "$n_mode")")
    fi

    if [[ "$o_uid" != "$n_uid" || "$o_gid" != "$n_gid" ]]; then
      reasons+=("owner $o_uid:$o_gid -> $n_uid:$n_gid")
    fi

    if (( ${#reasons[@]} > 0 )); then
      changed=$((changed + 1))
      detail="${reasons[0]}"
      for reason in "${reasons[@]:1}"; do
        detail+=", $reason"
      done
      printf '  %s~ %s%s (%s)\n' "$HM_C_OUT_YELLOW" "$(hm_path_display "$path")" \
        "$HM_C_OUT_RESET" "$detail"
    else
      unchanged=$((unchanged + 1))
      if [[ "$show_all" == "1" ]]; then
        printf '  = %s\n' "$(hm_path_display "$path")"
      fi
    fi
  done <<< "$keys"

  printf '\n'

  if (( added + removed + changed == 0 )); then
    printf '  %sNo differences.%s\n' "$HM_C_OUT_GREEN" "$HM_C_OUT_RESET"
  fi

  printf '  %s%d added%s, %s%d removed%s, %s%d changed%s, %d unchanged\n' \
    "$HM_C_OUT_GREEN" "$added" "$HM_C_OUT_RESET" \
    "$HM_C_OUT_RED" "$removed" "$HM_C_OUT_RESET" \
    "$HM_C_OUT_YELLOW" "$changed" "$HM_C_OUT_RESET" \
    "$unchanged"
}

# --- The command -----------------------------------------------------------

# diff GENERATION... - compare the entries of the given generations.
diff() {
  local show_all=0
  local profile_arg="" profile
  local -a generations=()
  local argument id index duplicate

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      --profile)
        [[ $# -ge 2 ]] || hm_die "$HM_EX_USAGE" "--profile requires a value."
        profile_arg="$2"
        shift 2
        ;;
      --profile=*)
        profile_arg="${argument#*=}"
        shift
        ;;
      --all)
        show_all=1
        shift
        ;;
      -h | --help)
        _diff_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm diff': $argument"
        ;;
      *)
        generations+=("$argument")
        shift
        ;;
    esac
  done

  if [[ ${#generations[@]} -eq 0 ]]; then
    hm_die "$HM_EX_USAGE" "Usage: hm diff [--profile NAME] <generation> <generation> [<generation>...]"
  fi

  if [[ ${#generations[@]} -lt 2 ]]; then
    hm_die "$HM_EX_USAGE" "At least two generations are required."
  fi

  hm_require_initialized
  hm_lock_acquire shared

  profile="$(hm_profile_scope "$profile_arg")"
  if [[ -n "$profile" ]]; then
    hm_profile_require "$profile" > /dev/null
  fi

  for index in "${!generations[@]}"; do
    if ! hm_gen_exists "${generations[$index]}"; then
      hm_die "$HM_EX_STATE" "There is no generation with the id ${generations[$index]}."
    fi
    if [[ -n "$profile" && "$(hm_profile_of_generation "${generations[$index]}")" != "$profile" ]]; then
      hm_die "$HM_EX_VALIDATION" "The generation ${generations[$index]} does not belong to the profile $profile."
    fi
    id="$(hm_sql_int "${generations[$index]}")"
    generations[index]="$((10#$id))"
  done

  for (( index = 0; index < ${#generations[@]}; index++ )); do
    for (( duplicate = index + 1; duplicate < ${#generations[@]}; duplicate++ )); do
      if [[ "${generations[$index]}" == "${generations[$duplicate]}" ]]; then
        hm_die "$HM_EX_USAGE" "The generations to compare must be distinct."
      fi
    done
  done

  hm_log_debug "Comparing the generations: ${generations[*]}."

  printf '%sHM-Lite diff%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  printf '\n'

  for (( index = 1; index < ${#generations[@]}; index++ )); do
    if (( index > 1 )); then
      printf '\n'
    fi
    _diff_pair "${generations[$index - 1]}" "${generations[$index]}" "$show_all"
  done

  return 0
}
