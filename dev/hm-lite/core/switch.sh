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
Usage: hm switch <generation>

Select a generation and materialize it into <runtime>/current.

Options:
  -h, --help    Show this help
EOF
}

# switch GENERATION - select a generation and materialize it.
switch() {
  local generation=""
  local argument

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      -h | --help)
        _switch_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm switch': $argument"
        ;;
      *)
        if [[ -n "$generation" ]]; then
          hm_die "$HM_EX_USAGE" "Usage: hm switch <generation>"
        fi
        generation="$argument"
        shift
        ;;
    esac
  done

  if [[ -z "$generation" ]]; then
    hm_die "$HM_EX_USAGE" "Usage: hm switch <generation>"
  fi

  hm_require_initialized
  hm_lock_acquire exclusive

  if ! hm_gen_exists "$generation"; then
    hm_die "$HM_EX_STATE" "There is no generation with the id $generation."
  fi

  # Every object of the generation must be present, a half materialized tree
  # would be worse than no tree at all.
  local missing
  missing="$(hm_gen_missing_objects "$generation")"
  if [[ -n "$missing" ]]; then
    local hash count=0
    while IFS= read -r hash; do
      [[ -n "$hash" ]] || continue
      count=$((count + 1))
    done <<< "$missing"
    hm_log_error "The generation needs $count content object(s) that are missing from the store."
    hm_die "$HM_EX_STORE" "The generation cannot be materialized."
  fi

  local entries objects
  entries="$(hm_gen_entry_count "$generation")"
  objects="$(hm_gen_object_count "$generation")"

  printf 'Generation %s: %s entries, %s content objects.\n' "$generation" "$entries" "$objects"
  printf 'The tree is written to: %s\n' "$(hm_path_display "$HM_CURRENT_DIR")"
  printf '\n'

  # --- Materialize into a staging directory -------------------------------
  local stage
  stage="$(hm_mktemp_dir "switch.XXXXXXXX")" || hm_die "$HM_EX_IO" "Cannot create the staging directory."
  _SWITCH_STAGE="$stage"
  trap '_switch_cleanup_stage' EXIT

  if ! hm_gen_materialize "$generation" "$stage"; then
    hm_die "$HM_EX_STORE" "The generation could not be materialized, nothing was changed."
  fi

  # --- Replace the current tree -------------------------------------------
  # The new tree is renamed into place, the old tree is moved aside first.
  # A failure restores the old tree.
  local current="$HM_CURRENT_DIR"
  local previous=""

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

  hm_gen_set_selected "$generation"

  hm_log_success "Generation $generation is now materialized in current/."
  printf '%s\n' "Selected generation: $generation"

  return 0
}
