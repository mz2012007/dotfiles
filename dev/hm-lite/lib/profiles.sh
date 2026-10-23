#!/usr/bin/env bash
#
# lib/profiles.sh - profile helpers.
#
# A profile is an independent namespace. The tracked paths, the pending
# set, the generations, the selection and the root directory belong to a
# profile, the content store is shared. A project always has the default
# profile, so the commands that do not name a profile keep working.
#
# The file only defines functions. Sourcing it has no side effects.
#

# The profile that a command uses when no --profile option and no active
# context are present.
HM_DEFAULT_PROFILE=default

# The state key that stores the active profile of the project.
HM_ACTIVE_PROFILE_KEY=active_profile

# hm_profile_valid NAME
# Return 0 when NAME is a valid profile name. A name starts with a letter
# or a digit and continues with letters, digits, dots, underscores or
# hyphens.
hm_profile_valid() {
  local name="$1"

  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

# hm_profile_exists NAME
hm_profile_exists() {
  local name="$1" count

  count="$(hm_db_scalar "SELECT COUNT(*) FROM profiles WHERE name = $(hm_sql_quote "$name");")" ||
    hm_die "$HM_EX_DB" "Cannot read the profiles from the database."

  [[ "$count" != "0" ]]
}

# hm_profile_active
# Print the profile stored as the active context, or nothing when none is
# set. A database failure aborts the command.
hm_profile_active() {
  local value

  value="$(hm_db_scalar "SELECT value FROM state WHERE key = $(hm_sql_quote "$HM_ACTIVE_PROFILE_KEY");")" ||
    hm_die "$HM_EX_DB" "Cannot read the active profile from the database."

  printf '%s\n' "$value"
}

# hm_profile_scope [EXPLICIT]
# Print the profile that scopes a command: the explicit --profile value,
# otherwise HM_PROFILE, otherwise the active profile. A missing context
# prints nothing. The caller validates and resolves the name.
hm_profile_scope() {
  local explicit="${1:-}" active

  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi

  if [[ -n "${HM_PROFILE:-}" ]]; then
    printf '%s\n' "$HM_PROFILE"
    return 0
  fi

  active="$(hm_profile_active)" || return $?
  printf '%s\n' "$active"
}

# hm_profile_context_name [EXPLICIT]
# Print the profile for a command that needs one. The precedence is:
# --profile, HM_PROFILE, the active profile, the default profile.
hm_profile_context_name() {
  local explicit="${1:-}" profile

  profile="$(hm_profile_scope "$explicit")" || return $?
  printf '%s\n' "${profile:-$HM_DEFAULT_PROFILE}"
}

# hm_profile_is_active NAME
# Return 0 when NAME is the persisted active profile, regardless of the
# process environment. Destructive commands use it together with
# hm_profile_is_context so that the stored context can never dangle.
hm_profile_is_active() {
  local name="$1" active

  active="$(hm_profile_active)" || return 1
  [[ -n "$active" && "$active" == "$name" ]]
}

# hm_profile_is_context NAME
# Return 0 when NAME is the effective context: HM_PROFILE when it is set,
# otherwise the active profile. The persisted context is deliberately
# ignored while HM_PROFILE is set, because the environment wins.
hm_profile_is_context() {
  local name="$1"

  if [[ -n "${HM_PROFILE:-}" ]]; then
    [[ "$HM_PROFILE" == "$name" ]]
    return
  fi

  hm_profile_is_active "$name"
}

# hm_profile_id NAME
# Print the identifier of NAME. An unknown profile prints nothing and
# returns 1, a database error aborts the command.
hm_profile_id() {
  local name="$1" id

  id="$(hm_db_scalar "SELECT id FROM profiles WHERE name = $(hm_sql_quote "$name");")" ||
    hm_die "$HM_EX_DB" "Cannot read the profiles from the database."

  [[ -n "$id" ]] || return 1
  printf '%s\n' "$id"
}

# hm_profile_require NAME
# Validate the name and require an existing profile. An invalid name is a
# usage error, an unknown profile is a validation error. Print the id.
hm_profile_require() {
  local name="$1" id status

  hm_profile_valid "$name" ||
    hm_die "$HM_EX_USAGE" "Invalid profile name: $name"

  status=0
  id="$(hm_profile_id "$name")" || status=$?
  if (( status == 1 )); then
    hm_die "$HM_EX_VALIDATION" "There is no profile named $name. Run 'hm profile create $name <root>' to create it."
  fi
  (( status == 0 )) || return "$status"

  printf '%s\n' "$id"
}

# hm_profile_normalize_root ROOT
# Expand a leading ~ and normalize ROOT. Relative roots are resolved
# against the current directory. Print the absolute normalized path.
hm_profile_normalize_root() {
  local root="$1" home="${HOME%/}" tilde='~'

  if [[ "$root" == "$tilde" ]]; then
    root="$home"
  elif [[ "${root:0:2}" == "$tilde/" ]]; then
    root="$home/${root:2}"
  fi

  hm_path_normalize "$root"
}

# hm_profile_root NAME
# Print the root directory of NAME. A legacy row without a usable root is
# treated as unrestricted, which preserves the behaviour of the profiles
# that existed before roots were introduced.
hm_profile_root() {
  local name="$1" root

  root="$(hm_db_scalar "SELECT root FROM profiles WHERE name = $(hm_sql_quote "$name");")" ||
    hm_die "$HM_EX_DB" "Cannot read the root of the profile $name."

  printf '%s\n' "${root:-/}"
}

# hm_profile_ensure NAME
# Validate the name and create the profile when it does not exist yet.
# Print the id.
hm_profile_ensure() {
  local name="$1" id status

  hm_profile_valid "$name" ||
    hm_die "$HM_EX_USAGE" "Invalid profile name: $name"

  status=0
  id="$(hm_profile_id "$name")" || status=$?
  if (( status != 0 && status != 1 )); then
    return "$status"
  fi
  if [[ -z "$id" ]]; then
    hm_db_exec "INSERT INTO profiles (name, root, created_at) VALUES ($(hm_sql_quote "$name"), '/', $(hm_now_epoch));" ||
      hm_die "$HM_EX_DB" "Cannot create the profile $name."
    id="$(hm_profile_id "$name")" ||
      hm_die "$HM_EX_DB" "Cannot read the created profile $name."
    hm_log_info "Created the profile $name."
  fi

  printf '%s\n' "$id"
}

# hm_profile_of_generation GENERATION_ID
# Print the name of the profile that owns the generation. A legacy row
# without a profile belongs to the default profile.
hm_profile_of_generation() {
  local id name

  id="$(hm_sql_int "$1")"
  name="$(hm_db_scalar "
    SELECT COALESCE(pr.name, '')
      FROM generations g
      LEFT JOIN profiles pr ON pr.id = g.profile_id
     WHERE g.id = $id;")" ||
    hm_die "$HM_EX_DB" "Cannot read the generation $id from the database."

  printf '%s\n' "${name:-$HM_DEFAULT_PROFILE}"
}

# hm_profile_state_key NAME
# Print the state key that holds the selection of NAME. An empty name is
# the global selection.
hm_profile_state_key() {
  local name="$1"

  if [[ -n "$name" ]]; then
    printf 'selected_generation:%s\n' "$name"
  else
    printf 'selected_generation\n'
  fi
}

# hm_profile_selection_count GENERATION_ID
# Print the number of profiles (including the global selection) that select
# the generation. Used by "hm delete" before removing a generation.
hm_profile_selection_count() {
  local id="$1" count

  count="$(hm_db_scalar "
    SELECT COUNT(*)
      FROM state
     WHERE value = $(hm_sql_quote "$id")
       AND (key = 'selected_generation' OR key GLOB 'selected_generation:*');")" ||
    hm_die "$HM_EX_DB" "Cannot read the selection from the database."

  printf '%s\n' "$count"
}
