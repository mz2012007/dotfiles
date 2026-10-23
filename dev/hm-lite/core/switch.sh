#!/usr/bin/env bash
#
# core/switch.sh - the switch command.
#
# Selects a generation and materializes it into the working directory
# <runtime>/current. The command never writes to the live filesystem, the
# materialized tree only lives inside the project directory.
#
# The materialization mirrors the absolute path of every entry, the entry
# /home/user/.bashrc is written to <runtime>/current/home/user/.bashrc.
#
# The module only defines the switch function. Sourcing it does not run the
# command.
#

# _switch_cleanup_stage
# Remove the staging directory of a failed materialization.
_switch_cleanup_stage() {
  local stage="${_SWITCH_STAGE:-}"

  trap - EXIT
  _SWITCH_STAGE=""

  [[ -n "$stage" ]] || return 0
  hm_rm_rf_under "${HM_TMP_DIR:-/nonexistent}" "$stage" 2>/dev/null || true
  return 0
}

# _switch_usage
_switch_usage() {
  cat <<'EOF'
Usage: hm switch [--profile NAME] <generation>

Select a generation and materialize it into <runtime>/current.

Options:
  --profile NAME  Resolve the local number in the profile
  -h, --help      Show this help
EOF
}

# switch GENERATION - select a generation and materialize it.
switch() {
  local generation="" profile_arg="" profile id
  local argument

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
      -h | --help)
        _switch_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm switch': $argument"
        ;;
      *)
        if [[ -n "$generation" ]]; then
          hm_die "$HM_EX_USAGE" "Usage: hm switch [--profile NAME] <generation>"
        fi
        generation="$argument"
        shift
        ;;
    esac
  done

  if [[ -z "$generation" ]]; then
    hm_die "$HM_EX_USAGE" "Usage: hm switch [--profile NAME] <generation>"
  fi

  hm_require_initialized
  hm_lock_acquire exclusive

  profile="$(hm_profile_context_name "$profile_arg")" || exit $?
  hm_profile_require "$profile" > /dev/null
  hm_profile_workspace_prepare "$profile"
  id="$(hm_gen_require "$profile" "$generation")" || exit $?

  # Every object of the generation must be present, a half materialized tree
  # would be worse than no tree at all.
  local missing
  if ! hm_gen_missing_objects "$id" missing; then
    hm_die "$HM_EX_DB" "Cannot read the generation $generation from the database."
  fi
  if [[ -n "$missing" ]]; then
    local hash count=0
    while IFS= read -r hash; do
      [[ -n "$hash" ]] || continue
      count=$((count + 1))
    done <<< "$missing"
    hm_log_error "The generation needs $count content object(s) that are missing from the store."
    hm_die "$HM_EX_STORE" "The generation cannot be materialized."
  fi

  local entries objects current_dir
  entries="$(hm_gen_entry_count "$id")" ||
    hm_die "$HM_EX_DB" "Cannot read the generation $generation from the database."
  objects="$(hm_gen_object_count "$id")" ||
    hm_die "$HM_EX_DB" "Cannot read the generation $generation from the database."
  current_dir="$(hm_profile_current_dir "$profile")"

  printf 'Generation %s%s%s: %s entries, %s content objects.\n' \
    "$HM_C_OUT_CYAN" "$generation" "$HM_C_OUT_RESET" "$entries" "$objects"
  printf 'The tree is written to: %s\n' "$(hm_path_display "$current_dir")"
  printf '\n'

  # --- Materialize into a staging directory -------------------------------
  local stage
  stage="$(hm_mktemp_dir "switch.XXXXXXXX")" || hm_die "$HM_EX_IO" "Cannot create the staging directory."
  _SWITCH_STAGE="$stage"
  trap '_switch_cleanup_stage' EXIT

  if ! hm_gen_materialize "$id" "$stage"; then
    hm_die "$HM_EX_STORE" "The generation could not be materialized, nothing was changed."
  fi

  # --- Replace the current tree -------------------------------------------
  # The new tree is renamed into place, the old tree is moved aside first.
  # A failure restores the old tree.
  local current current_dir previous

  current_dir="$(hm_profile_current_dir "$profile")"
  current="$current_dir"
  previous=""

  if [[ -e "$current" ]]; then
    previous="$HM_TMP_DIR/current.previous.$$"
    rm -rf -- "$previous"
    if ! mv -- "$current" "$previous"; then
      hm_die "$HM_EX_IO" "Cannot move the current tree aside."
    fi
  fi

  if ! mv -- "$stage" "$current"; then
    if [[ -n "$previous" && -d "$previous" ]]; then
      mv -- "$previous" "$current" 2>/dev/null || true
    fi
    hm_die "$HM_EX_IO" "Cannot install the new tree, the project was left unchanged."
  fi

  _SWITCH_STAGE=""
  trap - EXIT

  if [[ -n "$previous" ]]; then
    hm_rm_rf_under "$HM_TMP_DIR" "$previous" 2>/dev/null || true
  fi

  hm_gen_set_selected "$id" "$profile"

  hm_log_success "Generation $generation is now materialized in current/."
  printf '%sProfile:%s             %s\n' "$HM_C_OUT_LABEL" "$HM_C_OUT_RESET" "$profile"
  printf '%sSelected generation:%s %s%s%s\n' "$HM_C_OUT_LABEL" "$HM_C_OUT_RESET" \
    "$HM_C_OUT_GREEN" "$generation" "$HM_C_OUT_RESET"

  return 0
}
