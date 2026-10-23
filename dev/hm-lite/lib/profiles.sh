#!/usr/bin/env bash
#
# lib/profiles.sh - profile helpers.
#
# A profile is an independent namespace. The tracked paths, the pending
# set, the generations and the selection belong to a profile, the content
# store is shared. A project always has the default profile, so the
# commands that do not name a profile keep working.
#
# The file only defines functions. Sourcing it has no side effects.
#

# The profile that a command uses when no --profile option is given.
HM_DEFAULT_PROFILE=default

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
  local name="$1" id

  hm_profile_valid "$name" ||
    hm_die "$HM_EX_USAGE" "Invalid profile name: $name"

  id="$(hm_profile_id "$name")" ||
    hm_die "$HM_EX_VALIDATION" "There is no profile named $name. Run 'hm add --profile $name <path>' to create it."

  printf '%s\n' "$id"
}

# hm_profile_ensure NAME
# Validate the name and create the profile when it does not exist yet.
# Print the id.
hm_profile_ensure() {
  local name="$1" id

  hm_profile_valid "$name" ||
    hm_die "$HM_EX_USAGE" "Invalid profile name: $name"

  id="$(hm_profile_id "$name")" || true
  if [[ -z "$id" ]]; then
    hm_db_exec "INSERT INTO profiles (name, created_at) VALUES ($(hm_sql_quote "$name"), $(hm_now_epoch));" ||
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
