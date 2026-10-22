#!/usr/bin/env bash
#
# core/discard.sh - the discard command.
#
# Resets the testing workspace from the current tree. The command only
# touches directories that HM-Lite owns, the live filesystem is never
# involved.
#
# The module only defines the discard function. Sourcing it does not run the
# command.
#

# _discard_cleanup_stage
# Remove the staging directory of a failed copy.
_discard_cleanup_stage() {
  local stage="${_DISCARD_STAGE:-}"

  trap - EXIT
  _DISCARD_STAGE=""

  [[ -n "$stage" ]] || return 0
  hm_rm_rf_under "${HM_TMP_DIR:-/nonexistent}" "$stage" 2>/dev/null || true
  return 0
}

# _discard_usage
_discard_usage() {
  cat <<'EOF'
Usage: hm discard

Reset the testing workspace from the current tree.

Options:
  -h, --help    Show this help
EOF
}

# discard - reset the testing workspace.
discard() {
  local argument

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      -h | --help)
        _discard_usage
        return 0
        ;;
      *)
        hm_die "$HM_EX_USAGE" "Unknown argument for 'hm discard': $argument"
        ;;
    esac
  done

  hm_require_initialized
  hm_lock_acquire exclusive

  if [[ ! -d "$HM_CURRENT_DIR" ]]; then
    hm_die "$HM_EX_STATE" "There is no current tree. Run 'hm switch <generation>' first."
  fi

  if [[ -z "$(find "$HM_CURRENT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    hm_die "$HM_EX_STATE" "The current tree is empty. Run 'hm switch <generation>' first."
  fi

  local selected
  selected="$(hm_gen_selected)"
  if [[ -z "$selected" ]]; then
    hm_die "$HM_EX_STATE" "No generation is selected. Run 'hm switch <generation>' first."
  fi

  printf 'The testing workspace is reset from generation %s%s%s.\n' \
    "$HM_C_OUT_CYAN" "$selected" "$HM_C_OUT_RESET"
  printf 'The live filesystem is not touched.\n'
  printf '\n'

  # --- Copy the current tree into a staging directory ----------------------
  local stage
  stage="$(hm_mktemp_dir "discard.XXXXXXXX")" || hm_die "$HM_EX_IO" "Cannot create the staging directory."
  _DISCARD_STAGE="$stage"
  trap '_discard_cleanup_stage' EXIT

  if ! cp -a -- "$HM_CURRENT_DIR/." "$stage/"; then
    hm_die "$HM_EX_IO" "Cannot copy the current tree, the testing workspace was not changed."
  fi

  # --- Replace the testing workspace --------------------------------------
  local previous=""

  if [[ -e "$HM_TESTING_DIR" ]]; then
    previous="$HM_TMP_DIR/testing.previous.$$"
    rm -rf -- "$previous"
    if ! mv -- "$HM_TESTING_DIR" "$previous"; then
      hm_die "$HM_EX_IO" "Cannot move the testing workspace aside."
    fi
  fi

  if ! mv -- "$stage" "$HM_TESTING_DIR"; then
    if [[ -n "$previous" && -d "$previous" ]]; then
      mv -- "$previous" "$HM_TESTING_DIR" 2>/dev/null || true
    fi
    hm_die "$HM_EX_IO" "Cannot install the new testing workspace, the project was left unchanged."
  fi

  _DISCARD_STAGE=""
  trap - EXIT

  if [[ -n "$previous" ]]; then
    hm_rm_rf_under "$HM_TMP_DIR" "$previous" 2>/dev/null || true
  fi

  hm_log_success "The testing workspace was reset."

  return 0
}
