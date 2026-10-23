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
Usage: hm discard [--profile NAME]

Reset the testing workspace from the current tree.

Options:
  --profile NAME  Use the profile of the current tree
  -h, --help      Show this help
EOF
}

# discard - reset the testing workspace.
discard() {
  local argument
  local profile_arg="" profile
  local current_dir testing_dir

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
        _discard_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm discard': $argument"
        ;;
      *)
        hm_die "$HM_EX_USAGE" "Unknown argument for 'hm discard': $argument"
        ;;
    esac
  done

  hm_require_initialized
  hm_lock_acquire exclusive

  profile="$(hm_profile_context_name "$profile_arg")" || exit $?
  hm_profile_require "$profile" > /dev/null
  hm_profile_workspace_prepare "$profile"

  current_dir="$(hm_profile_current_dir "$profile")"
  testing_dir="$(hm_profile_testing_dir "$profile")"

  if [[ ! -d "$current_dir" ]]; then
    hm_die "$HM_EX_STATE" "There is no current tree. Run 'hm switch <generation>' first."
  fi

  if [[ -z "$(find "$current_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    hm_die "$HM_EX_STATE" "The current tree is empty. Run 'hm switch <generation>' first."
  fi

  local selected selected_label
  selected="$(hm_gen_selected "$profile")"
  if [[ -z "$selected" ]]; then
    hm_die "$HM_EX_STATE" "No generation is selected. Run 'hm switch <generation>' first."
  fi
  selected_label="$(hm_gen_label "$selected")" || selected_label="$selected"

  printf 'The testing workspace is reset from generation %s%s%s.\n' \
    "$HM_C_OUT_CYAN" "$selected_label" "$HM_C_OUT_RESET"
  printf 'The live filesystem is not touched.\n'
  printf '\n'

  # --- Copy the current tree into a staging directory ----------------------
  local stage
  stage="$(hm_mktemp_dir "discard.XXXXXXXX")" || hm_die "$HM_EX_IO" "Cannot create the staging directory."
  _DISCARD_STAGE="$stage"
  trap '_discard_cleanup_stage' EXIT

  if ! cp -a -- "$current_dir/." "$stage/"; then
    hm_die "$HM_EX_IO" "Cannot copy the current tree, the testing workspace was not changed."
  fi

  # --- Replace the testing workspace --------------------------------------
  local previous=""

  if [[ -e "$testing_dir" ]]; then
    previous="$HM_TMP_DIR/testing.previous.$$"
    rm -rf -- "$previous"
    if ! mv -- "$testing_dir" "$previous"; then
      hm_die "$HM_EX_IO" "Cannot move the testing workspace aside."
    fi
  fi

  if ! mv -- "$stage" "$testing_dir"; then
    if [[ -n "$previous" && -d "$previous" ]]; then
      mv -- "$previous" "$testing_dir" 2>/dev/null || true
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
