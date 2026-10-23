#!/usr/bin/env bash
#
# core/profile.sh - profile management.
#
# A profile is the primary unit of HM-Lite: it owns its tracked paths, its
# pending set, its generations and its selection. The content store,
# current/ and testing/ stay shared.
#
# The "profile" command is a namespace for the management subcommands. The
# commands that work on generations keep their own names and accept
# --profile, so no operation is duplicated.
#
# The module only defines the profile function. Sourcing it does not run
# the command.
#

# The add pipeline and the read-only list helpers are reused by the profile
# commands instead of being copied here.
# shellcheck source=/dev/null
source "$HM_CODE_DIR/core/add.sh"
# shellcheck source=/dev/null
source "$HM_CODE_DIR/core/list.sh"

# --- Help ------------------------------------------------------------------

# _profile_usage
_profile_usage() {
  cat <<'EOF'
Usage: hm profile <subcommand> [arguments...]

Manage the profiles of the project.

Subcommands:
  profile create <name> <root>  Create a profile with a root directory
  profile add <name> [path...]  Create a legacy profile (root /) and optionally register paths
  profile list                  List the profiles, roots and counts
  profile show [name]           Show the root, paths and generations of a profile
  profile use [name]            Select the active profile, or print it
  profile rename <old> <new>    Rename a profile and its context
  profile delete <name>         Delete a profile after a confirmation

Options:
  -h, --help                    Show this help

The active profile is the context of the commands that do not name a
profile. The precedence is --profile, HM_PROFILE, the active profile and
then the default profile.
EOF
}

# _profile_create_usage
_profile_create_usage() {
  cat <<'EOF'
Usage: hm profile create <name> <root>

Create a profile whose paths are confined to ROOT. The root is normalized
against the current directory, a leading ~ is expanded and the directory
must already exist.

Options:
  -h, --help     Show this help
EOF
}

# _profile_add_usage
_profile_add_usage() {
  cat <<'EOF'
Usage: hm profile add <name> [path...]

Create a legacy profile with root / and optionally register paths in it.
Use "hm profile create NAME ROOT" for a rooted profile.

Options:
  -h, --help     Show this help
EOF
}

# _profile_list_usage
_profile_list_usage() {
  cat <<'EOF'
Usage: hm profile list

List the profiles with their root, path, pending and generation counts.

Options:
  -h, --help     Show this help
EOF
}

# _profile_show_usage
_profile_show_usage() {
  cat <<'EOF'
Usage: hm profile show [name]

Show the root, the paths and the generations of a profile. Without a name
the effective context is shown, falling back to the default profile.

Options:
  -h, --help     Show this help
EOF
}

# _profile_use_usage
_profile_use_usage() {
  cat <<'EOF'
Usage: hm profile use [name]

Select the active profile for the commands that do not use --profile. A
missing name prints the current context. HM_PROFILE overrides the stored
context in the current process.

Options:
  -h, --help     Show this help
EOF
}

# _profile_rename_usage
_profile_rename_usage() {
  cat <<'EOF'
Usage: hm profile rename <old> <new> [options]

Rename a profile. The paths, the generations and the selection follow the
profile; the active context and the selection key are updated as well.

Options:
  --yes, -y      Do not ask for a confirmation
  -h, --help     Show this help
EOF
}

# _profile_delete_usage
_profile_delete_usage() {
  cat <<'EOF'
Usage: hm profile delete <name> [options]

Delete a profile and, with --force, its generations. The content objects
stay in the shared store until "hm clean" runs.

Options:
  --force        Delete a profile that still has generations
  --yes, -y      Do not ask for a confirmation
  -h, --help     Show this help
EOF
}

# --- Helpers ---------------------------------------------------------------

# _profile_remove_if_empty NAME
# Remove a profile that was created by a failed "profile add" and that owns
# nothing. Best effort: the caller reports the original failure.
_profile_remove_if_empty() {
  local name="$1"

  hm_db_exec "
    DELETE FROM profiles
     WHERE name = $(hm_sql_quote "$name")
       AND NOT EXISTS (SELECT 1 FROM path_profiles x WHERE x.profile_id = profiles.id)
       AND NOT EXISTS (SELECT 1 FROM pending_paths pp WHERE pp.profile_id = profiles.id)
       AND NOT EXISTS (SELECT 1 FROM generations g WHERE g.profile_id = profiles.id);" ||
    true
}

# _profile_print_created NAME [ROOT]
_profile_print_created() {
  local name="$1" root="${2:-}"

  printf '%sProfile created%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %s%-11s%s %s%s%s\n' "$HM_C_OUT_LABEL" "Name:" "$HM_C_OUT_RESET" \
    "$HM_C_OUT_CYAN" "$name" "$HM_C_OUT_RESET"
  if [[ -n "$root" ]]; then
    printf '  %s%-11s%s %s\n' "$HM_C_OUT_LABEL" "Root:" "$HM_C_OUT_RESET" \
      "$(hm_path_display "$root")"
  fi
}

# --- Subcommands -----------------------------------------------------------

# _profile_create NAME ROOT - create a profile with a root directory.
_profile_create() {
  local name="" root_arg="" root argument

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      -h | --help)
        _profile_create_usage
        return 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          if [[ -z "$name" ]]; then
            name="$1"
          elif [[ -z "$root_arg" ]]; then
            root_arg="$1"
          else
            hm_die "$HM_EX_USAGE" "Usage: hm profile create <name> <root>"
          fi
          shift
        done
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm profile create': $argument"
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$argument"
        elif [[ -z "$root_arg" ]]; then
          root_arg="$argument"
        else
          hm_die "$HM_EX_USAGE" "Usage: hm profile create <name> <root>"
        fi
        shift
        ;;
    esac
  done

  [[ -n "$name" && -n "$root_arg" ]] ||
    hm_die "$HM_EX_USAGE" "Usage: hm profile create <name> <root>"
  hm_profile_valid "$name" || hm_die "$HM_EX_USAGE" "Invalid profile name: $name"

  root="$(hm_profile_normalize_root "$root_arg")" ||
    hm_die "$HM_EX_VALIDATION" "Invalid profile root: $root_arg"

  hm_require_initialized
  hm_lock_acquire exclusive

  if hm_profile_exists "$name"; then
    hm_die "$HM_EX_VALIDATION" "The profile $name already exists."
  fi

  if [[ ! -d "$root" ]]; then
    hm_die "$HM_EX_VALIDATION" "The profile root must be an existing directory: $(hm_path_display "$root")"
  fi

  hm_db_exec "INSERT INTO profiles (name, root, created_at) VALUES ($(hm_sql_quote "$name"), $(hm_sql_quote "$root"), $(hm_now_epoch));" ||
    hm_die "$HM_EX_DB" "Cannot create the profile $name."

  hm_log_success "Created the profile $name with the root $(hm_path_display "$root")."
  _profile_print_created "$name" "$root"

  return 0
}

# _profile_add [NAME] [PATH...] - create a profile.
_profile_add() {
  local name="" argument
  local -a paths=()
  local profile_id rc

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      -h | --help)
        _profile_add_usage
        return 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          if [[ -z "$name" ]]; then
            name="$1"
          else
            paths+=("$1")
          fi
          shift
        done
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm profile add': $argument"
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$argument"
        else
          paths+=("$argument")
        fi
        shift
        ;;
    esac
  done

  [[ -n "$name" ]] || hm_die "$HM_EX_USAGE" "Usage: hm profile add <name> [path...]"
  hm_profile_valid "$name" || hm_die "$HM_EX_USAGE" "Invalid profile name: $name"

  hm_require_initialized
  hm_lock_acquire exclusive

  if hm_profile_exists "$name"; then
    hm_die "$HM_EX_VALIDATION" "The profile $name already exists."
  fi

  if [[ ${#paths[@]} -gt 0 ]]; then
    profile_id="$(hm_profile_ensure "$name")" || exit $?
    rc=0
    _add_register "$name" "$profile_id" "${paths[@]}" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      _profile_remove_if_empty "$name"
      return "$rc"
    fi
    return 0
  fi

  printf '%sCreate profile%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %s%-11s%s %s%s%s\n' "$HM_C_OUT_LABEL" "Name:" "$HM_C_OUT_RESET" \
    "$HM_C_OUT_CYAN" "$name" "$HM_C_OUT_RESET"
  printf '\n'

  if ! hm_confirm "Create the profile $name? [y/N]"; then
    hm_log_info "Cancelled, nothing was changed."
    return "$HM_EX_DECLINED"
  fi

  hm_profile_ensure "$name" > /dev/null
  hm_log_success "Created the profile $name."
  _profile_print_created "$name" "/"

  return 0
}

# _profile_list - print every profile with its counts.
_profile_list() {
  local argument rows row name root created paths pending generations selected
  local active context marker

  for argument in "$@"; do
    case "$argument" in
      -h | --help)
        _profile_list_usage
        return 0
        ;;
      *)
        hm_die "$HM_EX_USAGE" "Usage: hm profile list"
        ;;
    esac
  done

  hm_require_initialized
  hm_lock_acquire shared

  active="$(hm_profile_active)"
  if [[ -n "${HM_PROFILE:-}" ]]; then
    context="$HM_PROFILE"
  else
    context="$active"
  fi

  if ! hm_db_rows "
    SELECT pr.name,
           pr.root,
           pr.created_at,
           (SELECT COUNT(*) FROM path_profiles x WHERE x.profile_id = pr.id),
           (SELECT COUNT(*) FROM pending_paths pp WHERE pp.profile_id = pr.id),
           (SELECT COUNT(*) FROM generations g WHERE g.profile_id = pr.id),
           COALESCE((SELECT g.number
                       FROM generations g
                      WHERE g.id = CAST((SELECT value FROM state
                                          WHERE key = 'selected_generation:' || pr.name)
                                        AS INTEGER)), '')
      FROM profiles pr
     ORDER BY pr.name;" rows; then
    hm_die "$HM_EX_DB" "Cannot read the profiles from the database."
  fi

  printf '%sProfiles%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  printf '\n'
  printf '%s%-20s %-36s %8s %8s %12s %10s %s%s\n' "$HM_C_OUT_HEADING" \
    "NAME" "ROOT" "PATHS" "PENDING" "GENERATIONS" "SELECTED" "ACTIVE" "$HM_C_OUT_RESET"

  while IFS="$HM_FIELD_SEP" read -r name root created paths pending generations selected; do
    [[ -n "$name" ]] || continue
    marker="no"
    if [[ -n "$context" && "$name" == "$context" ]]; then
      marker="yes"
    fi
    printf '%-20s %-36s %8s %8s %12s %10s %s\n' \
      "$name" "$(hm_path_display "$root")" "$paths" "$pending" "$generations" \
      "${selected:--}" "$marker"
  done <<< "$rows"

  printf '\n'
  if [[ -n "${HM_PROFILE:-}" ]]; then
    printf '  %sEnvironment context:%s %s%s%s\n' "$HM_C_OUT_LABEL" "$HM_C_OUT_RESET" \
      "$HM_C_OUT_YELLOW" "$HM_PROFILE" "$HM_C_OUT_RESET"
  elif [[ -n "$active" ]]; then
    printf '  %sActive profile:%s %s%s%s\n' "$HM_C_OUT_LABEL" "$HM_C_OUT_RESET" \
      "$HM_C_OUT_GREEN" "$active" "$HM_C_OUT_RESET"
  else
    printf '  %sNo active profile.%s\n' "$HM_C_OUT_DIM" "$HM_C_OUT_RESET"
  fi

  return 0
}

# _profile_show [NAME] - print the details, paths and generations.
_profile_show() {
  local name="" argument
  local row root created paths pending generations selected active marker

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      -h | --help)
        _profile_show_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm profile show': $argument"
        ;;
      *)
        [[ -z "$name" ]] || hm_die "$HM_EX_USAGE" "Usage: hm profile show [name]"
        name="$argument"
        shift
        ;;
    esac
  done

  hm_require_initialized
  hm_lock_acquire shared

  if [[ -z "$name" ]]; then
    name="$(hm_profile_context_name "")" || exit $?
  fi
  hm_profile_require "$name" > /dev/null

  if ! hm_db_rows "
    SELECT pr.root,
           pr.created_at,
           (SELECT COUNT(*) FROM path_profiles x WHERE x.profile_id = pr.id),
           (SELECT COUNT(*) FROM pending_paths pp WHERE pp.profile_id = pr.id),
           (SELECT COUNT(*) FROM generations g WHERE g.profile_id = pr.id),
           COALESCE((SELECT g.number
                       FROM generations g
                      WHERE g.id = CAST((SELECT value FROM state
                                          WHERE key = 'selected_generation:' || pr.name)
                                        AS INTEGER)), '')
      FROM profiles pr
     WHERE pr.name = $(hm_sql_quote "$name");" row; then
    hm_die "$HM_EX_DB" "Cannot read the profile $name from the database."
  fi

  [[ -n "$row" ]] || hm_die "$HM_EX_VALIDATION" "There is no profile named $name."
  IFS="$HM_FIELD_SEP" read -r root created paths pending generations selected <<< "$row"

  if hm_profile_is_context "$name"; then
    active="yes"
  else
    active="no"
  fi

  printf '%sProfile %s%s\n' "$HM_C_OUT_HEADING" "$name" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %s%-13s %s\n' "$HM_C_OUT_LABEL" "Root:" "$(hm_path_display "$root")"
  printf '  %s%-13s %s%s\n' "$HM_C_OUT_LABEL" "Created:" \
    "$(hm_format_epoch "$created" || printf '%s' "$created")" "$HM_C_OUT_RESET"
  printf '  %s%-13s %s%s\n' "$HM_C_OUT_LABEL" "Active:" "$active" "$HM_C_OUT_RESET"
  printf '  %s%-13s %s\n' "$HM_C_OUT_LABEL" "Paths:" "$paths"
  printf '  %s%-13s %s\n' "$HM_C_OUT_LABEL" "Pending:" "$pending"
  printf '  %s%-13s %s\n' "$HM_C_OUT_LABEL" "Generations:" "$generations"
  printf '  %s%-13s %s\n' "$HM_C_OUT_LABEL" "Selected:" "${selected:--}"
  printf '\n'

  printf '%sPaths%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  printf '\n'
  _list_paths "$name"
  printf '\n'

  printf '%sGenerations%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  printf '\n'
  _list_generations "$name"

  return 0
}

# _profile_use [NAME] - select the active profile.
_profile_use() {
  local name="" argument active

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      -h | --help)
        _profile_use_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm profile use': $argument"
        ;;
      *)
        [[ -z "$name" ]] || hm_die "$HM_EX_USAGE" "Usage: hm profile use [name]"
        name="$argument"
        shift
        ;;
    esac
  done

  hm_require_initialized

  if [[ -z "$name" ]]; then
    hm_lock_acquire shared
    active="$(hm_profile_active)"
    if [[ -n "$active" ]]; then
      printf '%sActive profile:%s %s%s%s\n' "$HM_C_OUT_LABEL" "$HM_C_OUT_RESET" \
        "$HM_C_OUT_GREEN" "$active" "$HM_C_OUT_RESET"
    else
      printf '%sNo active profile.%s\n' "$HM_C_OUT_DIM" "$HM_C_OUT_RESET"
    fi
    if [[ -n "${HM_PROFILE:-}" ]]; then
      printf '%sEnvironment context:%s %s%s%s\n' "$HM_C_OUT_LABEL" "$HM_C_OUT_RESET" \
        "$HM_C_OUT_YELLOW" "$HM_PROFILE" "$HM_C_OUT_RESET"
    fi
    return 0
  fi

  hm_lock_acquire exclusive
  hm_profile_require "$name" > /dev/null
  active="$(hm_profile_active)"

  hm_db_exec "
    INSERT INTO state (key, value)
    VALUES ($(hm_sql_quote "$HM_ACTIVE_PROFILE_KEY"), $(hm_sql_quote "$name"))
    ON CONFLICT(key) DO UPDATE SET value = excluded.value;" ||
    hm_die "$HM_EX_DB" "Cannot store the active profile."

  if [[ -n "${HM_PROFILE:-}" && "$HM_PROFILE" != "$name" ]]; then
    hm_log_warn "HM_PROFILE=$HM_PROFILE overrides the stored context in this process."
  fi

  if [[ "$active" == "$name" ]]; then
    hm_log_info "The profile $name is already active."
  else
    hm_log_success "Active profile is now $name."
  fi
  printf '%sActive profile:%s %s%s%s\n' "$HM_C_OUT_LABEL" "$HM_C_OUT_RESET" \
    "$HM_C_OUT_GREEN" "$name" "$HM_C_OUT_RESET"

  return 0
}

# _profile_rename OLD NEW - rename a profile.
_profile_rename() {
  local old="" new="" argument assume_yes=0 old_id generations

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      --yes | -y)
        assume_yes=1
        shift
        ;;
      -h | --help)
        _profile_rename_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm profile rename': $argument"
        ;;
      *)
        if [[ -z "$old" ]]; then
          old="$argument"
        elif [[ -z "$new" ]]; then
          new="$argument"
        else
          hm_die "$HM_EX_USAGE" "Usage: hm profile rename <old> <new> [options]"
        fi
        shift
        ;;
    esac
  done

  [[ -n "$old" && -n "$new" ]] ||
    hm_die "$HM_EX_USAGE" "Usage: hm profile rename <old> <new> [options]"
  hm_profile_valid "$new" || hm_die "$HM_EX_USAGE" "Invalid profile name: $new"

  hm_require_initialized
  hm_lock_acquire exclusive

  old_id="$(hm_profile_require "$old")" || exit $?
  if [[ "$old" == "$HM_DEFAULT_PROFILE" ]]; then
    hm_die "$HM_EX_VALIDATION" "The default profile cannot be renamed."
  fi
  if [[ "$old" == "$new" ]]; then
    hm_die "$HM_EX_VALIDATION" "The new name is the same as the old name."
  fi
  if hm_profile_exists "$new"; then
    hm_die "$HM_EX_VALIDATION" "The profile $new already exists."
  fi

  generations="$(hm_db_scalar "SELECT COUNT(*) FROM generations WHERE profile_id = $old_id;")" ||
    hm_die "$HM_EX_DB" "Cannot read the generations of the profile $old."

  printf '%sRename profile%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %s%-13s %s -> %s%s%s\n' "$HM_C_OUT_LABEL" "Name:" \
    "$old" "$HM_C_OUT_GREEN" "$new" "$HM_C_OUT_RESET"
  printf '  %s%-13s %s\n' "$HM_C_OUT_LABEL" "Generations:" "$generations"
  printf '\n'

  if [[ $assume_yes -eq 0 ]]; then
    if ! hm_confirm "Rename the profile? [y/N]"; then
      hm_log_info "Cancelled, nothing was changed."
      return "$HM_EX_DECLINED"
    fi
  fi

  {
    printf 'UPDATE profiles SET name = %s WHERE id = %s;\n' \
      "$(hm_sql_quote "$new")" "$old_id"
    printf "UPDATE state SET key = 'selected_generation:' || %s WHERE key = 'selected_generation:' || %s;\n" \
      "$(hm_sql_quote "$new")" "$(hm_sql_quote "$old")"
    printf 'UPDATE state SET value = %s WHERE key = %s AND value = %s;\n' \
      "$(hm_sql_quote "$new")" "$(hm_sql_quote "$HM_ACTIVE_PROFILE_KEY")" \
      "$(hm_sql_quote "$old")"
  } | hm_db_tx || hm_die "$HM_EX_DB" "The rename failed, nothing was changed."

  hm_log_success "Renamed the profile $old to $new."
  printf '%s%s -> %s%s\n' "$HM_C_OUT_GREEN" "$old" "$new" "$HM_C_OUT_RESET"

  if [[ -n "${HM_PROFILE:-}" && "$HM_PROFILE" == "$old" ]]; then
    hm_log_warn "HM_PROFILE still names $old; update it for the new name."
  fi

  return 0
}

# _profile_delete NAME - delete a profile.
_profile_delete() {
  local name="" argument force=0 assume_yes=0 id
  local row created paths pending generations selected objects

  while [[ $# -gt 0 ]]; do
    argument="$1"
    case "$argument" in
      --force)
        force=1
        shift
        ;;
      --yes | -y)
        assume_yes=1
        shift
        ;;
      -h | --help)
        _profile_delete_usage
        return 0
        ;;
      -*)
        hm_die "$HM_EX_USAGE" "Unknown option for 'hm profile delete': $argument"
        ;;
      *)
        [[ -z "$name" ]] || hm_die "$HM_EX_USAGE" "Usage: hm profile delete <name> [options]"
        name="$argument"
        shift
        ;;
    esac
  done

  [[ -n "$name" ]] || hm_die "$HM_EX_USAGE" "Usage: hm profile delete <name> [options]"

  hm_require_initialized
  hm_lock_acquire exclusive

  id="$(hm_profile_require "$name")" || exit $?

  if [[ "$name" == "$HM_DEFAULT_PROFILE" ]]; then
    hm_die "$HM_EX_VALIDATION" "The default profile cannot be deleted."
  fi

  if hm_profile_is_context "$name" || hm_profile_is_active "$name"; then
    hm_die "$HM_EX_VALIDATION" "The profile $name is the active context. Select another profile before deleting it."
  fi

  if ! hm_db_rows "
    SELECT pr.created_at,
           (SELECT COUNT(*) FROM path_profiles x WHERE x.profile_id = pr.id),
           (SELECT COUNT(*) FROM pending_paths pp WHERE pp.profile_id = pr.id),
           (SELECT COUNT(*) FROM generations g WHERE g.profile_id = pr.id),
           COALESCE((SELECT value FROM state
                      WHERE key = 'selected_generation:' || pr.name), ''),
           (SELECT COUNT(DISTINCT ge.file_id)
              FROM generation_entries ge
              JOIN generations g ON g.id = ge.generation_id
             WHERE g.profile_id = pr.id
               AND ge.file_id IS NOT NULL)
      FROM profiles pr
     WHERE pr.id = $id;" row; then
    hm_die "$HM_EX_DB" "Cannot read the profile $name from the database."
  fi

  [[ -n "$row" ]] || hm_die "$HM_EX_VALIDATION" "There is no profile named $name."
  IFS="$HM_FIELD_SEP" read -r created paths pending generations selected objects <<< "$row"

  if [[ "$generations" -gt 0 && $force -eq 0 ]]; then
    hm_die "$HM_EX_VALIDATION" "The profile $name has $generations generation(s). Use --force to delete them as well."
  fi

  printf '%sDelete profile%s\n' "$HM_C_OUT_HEADING" "$HM_C_OUT_RESET"
  printf '\n'
  printf '  %s%-13s %s%s%s\n' "$HM_C_OUT_LABEL" "Name:" \
    "$HM_C_OUT_CYAN" "$name" "$HM_C_OUT_RESET"
  printf '  %s%-13s %s\n' "$HM_C_OUT_LABEL" "Created:" \
    "$(hm_format_epoch "$created" || printf '%s' "$created")"
  printf '  %s%-13s %s\n' "$HM_C_OUT_LABEL" "Paths:" "$paths"
  printf '  %s%-13s %s\n' "$HM_C_OUT_LABEL" "Pending:" "$pending"
  printf '  %s%-13s %s\n' "$HM_C_OUT_LABEL" "Generations:" "$generations"
  printf '  %s%-13s %s\n' "$HM_C_OUT_LABEL" "Objects:" "$objects"
  printf '\n'

  if [[ "$generations" -gt 0 ]]; then
    printf '  %s%s generation(s) and their history will be deleted.%s\n' \
      "$HM_C_OUT_RED" "$generations" "$HM_C_OUT_RESET"
    printf '  The content objects stay in the store until "hm clean" runs.\n'
    printf '\n'
  fi

  if [[ $assume_yes -eq 0 ]]; then
    if ! hm_confirm "Delete the profile? [y/N]"; then
      hm_log_info "Cancelled, nothing was deleted."
      return "$HM_EX_DECLINED"
    fi
  fi

  {
    printf 'DELETE FROM state WHERE key = %s;\n' \
      "$(hm_sql_quote "selected_generation:$name")"
    printf "DELETE FROM state WHERE key = 'selected_generation' AND value IN (SELECT id FROM generations WHERE profile_id = %s);\n" \
      "$id"
    printf "DELETE FROM state
             WHERE key GLOB 'selected_generation:*'
               AND value IN (SELECT id FROM generations WHERE profile_id = %s);\n" \
      "$id"
    if [[ $force -eq 1 ]]; then
      printf 'DELETE FROM generations WHERE profile_id = %s;\n' "$id"
    fi
    printf 'DELETE FROM pending_paths WHERE profile_id = %s;\n' "$id"
    printf 'DELETE FROM paths
             WHERE id IN (SELECT path_id FROM path_profiles WHERE profile_id = %s)
               AND NOT EXISTS (SELECT 1 FROM path_profiles x
                                WHERE x.path_id = paths.id
                                  AND x.profile_id <> %s)
               AND NOT EXISTS (SELECT 1 FROM generation_entries ge
                                WHERE ge.path_id = paths.id);\n' "$id" "$id"
    printf 'DELETE FROM path_profiles WHERE profile_id = %s;\n' "$id"
    printf 'DELETE FROM profiles WHERE id = %s;\n' "$id"
  } | hm_db_tx || hm_die "$HM_EX_DB" "The deletion failed, nothing was changed."

  hm_log_success "Deleted the profile $name."
  if [[ "$generations" -gt 0 ]]; then
    hm_log_info "$objects content object(s) may become unreferenced, run 'hm clean' to remove them."
  fi

  return 0
}

# --- The command -----------------------------------------------------------

# profile SUBCOMMAND [ARGUMENTS...] - manage the profiles.
profile() {
  local subcommand="${1:-}"

  if [[ -z "$subcommand" ]]; then
    _profile_usage >&2
    return "$HM_EX_USAGE"
  fi

  shift

  case "$subcommand" in
    -h | --help | help)
      _profile_usage
      return 0
      ;;
    add)
      _profile_add "$@"
      ;;
    create)
      _profile_create "$@"
      ;;
    list)
      _profile_list "$@"
      ;;
    show)
      _profile_show "$@"
      ;;
    use)
      _profile_use "$@"
      ;;
    rename)
      _profile_rename "$@"
      ;;
    delete)
      _profile_delete "$@"
      ;;
    *)
      hm_die "$HM_EX_USAGE" "Unknown profile subcommand: $subcommand"
      ;;
  esac
}
