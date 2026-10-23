#!/usr/bin/env bash
#
# tests/cases/17_profile_commands.sh - profile management and context.
#
# A profile is the primary unit of HM-Lite: it owns its paths, pending set,
# generations and selection. This file covers the management commands, the
# active context, the precedence of --profile and the safety of deletion.
# shellcheck disable=SC2034

TESTS=(
  test_profile_add_creates_an_empty_profile
  test_profile_add_registers_paths
  test_profile_add_rejects_existing_and_invalid_names
  test_profile_list_shows_counts_and_the_active_marker
  test_profile_show_prints_paths_and_generations
  test_profile_use_sets_the_active_context
  test_profile_use_without_a_name_prints_the_context
  test_active_context_scopes_add_and_gen
  test_active_context_scopes_list_and_status
  test_explicit_profile_beats_the_active_context
  test_the_environment_context_is_used_and_overridden
  test_invalid_or_unknown_contexts_are_rejected
  test_active_context_scopes_generation_commands
  test_explicit_profile_scopes_generation_commands
  test_active_context_applies_the_profile_selection
  test_profile_rename_moves_the_context_and_selection
  test_profile_delete_protects_the_default_and_the_active_profile
  test_profile_delete_requires_force_for_history
  test_profile_delete_force_keeps_shared_paths
  test_profile_delete_removes_the_orphan_paths
  test_no_active_context_keeps_the_existing_behaviour
  test_profile_help_is_available
  test_profile_output_respects_the_colour_mode
)

# _profile_commands_fixture - two independent profiles with one generation
# each. The identifiers are deterministic: alpha owns 1, beta owns 2.
_profile_commands_fixture() {
  _test_setup profile_commands_fixture
  mkdir -p "$SRC_DIR/alpha" "$SRC_DIR/beta"
  printf 'alpha\n' > "$SRC_DIR/alpha/a.txt"
  printf 'beta\n' > "$SRC_DIR/beta/b.txt"

  run_hm_input 'y\n' add --profile alpha "$SRC_DIR/alpha/a.txt"
  run_hm_input 'y\n' gen --profile alpha --name "alpha-1"
  run_hm_input 'y\n' add --profile beta "$SRC_DIR/beta/b.txt"
  run_hm_input 'y\n' gen --profile beta --name "beta-1"
}

test_profile_add_creates_an_empty_profile() {
  _test_setup profile_add_empty

  run_hm_input 'y\n' profile add staging

  assert_rc 0 "$HM_STATUS" "profile add succeeds"
  assert_sql "1" "SELECT COUNT(*) FROM profiles WHERE name = 'staging';" \
    "the profile was created"
  assert_sql "0" "SELECT COUNT(*) FROM path_profiles;" \
    "the new profile has no paths"
  assert_sql "0" "SELECT COUNT(*) FROM state WHERE key = 'active_profile';" \
    "creating a profile does not select it"
  assert_contains "$HM_OUTPUT" "staging" "the output names the created profile"
}

test_profile_add_registers_paths() {
  _test_setup profile_add_paths
  printf 'a\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y\n' profile add alpha "$SRC_DIR/a.txt"

  assert_rc 0 "$HM_STATUS" "profile add with a path succeeds"
  assert_sql "1" "SELECT COUNT(*) FROM profiles WHERE name = 'alpha';" \
    "the profile was created"
  assert_sql "1" \
    "SELECT COUNT(*) FROM path_profiles x
       JOIN profiles pr ON pr.id = x.profile_id
      WHERE pr.name = 'alpha';" \
    "the path belongs to the new profile"
  assert_sql "1" \
    "SELECT COUNT(*) FROM pending_paths pp
       JOIN profiles pr ON pr.id = pp.profile_id
      WHERE pr.name = 'alpha';" \
    "the path is pending in the new profile"
  assert_contains "$HM_OUTPUT" "profile: alpha" "the registration names the profile"
}

test_profile_add_rejects_existing_and_invalid_names() {
  _test_setup profile_add_rejects

  run_hm_input 'y\n' profile add default
  assert_rc 3 "$HM_STATUS" "an existing profile is refused"
  assert_contains "$HM_OUTPUT" "already exists" "the error explains the conflict"

  run_hm_input 'y\n' profile add "bad name"
  assert_rc 2 "$HM_STATUS" "an invalid name is a usage error"
  assert_sql "0" "SELECT COUNT(*) FROM profiles WHERE name = 'bad name';" \
    "the invalid profile was not created"
}

test_profile_list_shows_counts_and_the_active_marker() {
  _profile_commands_fixture

  run_hm profile use alpha
  assert_rc 0 "$HM_STATUS" "the active profile is selected"

  run_hm profile list

  assert_rc 0 "$HM_STATUS" "profile list succeeds"
  assert_contains "$HM_OUTPUT" "NAME" "the table has a name column"
  assert_contains "$HM_OUTPUT" "PATHS" "the table has a paths column"
  assert_contains "$HM_OUTPUT" "GENERATIONS" "the table has a generations column"
  assert_contains "$HM_OUTPUT" "ACTIVE" "the table has an active column"
  assert_contains "$HM_OUTPUT" "alpha" "the first profile is listed"
  assert_contains "$HM_OUTPUT" "beta" "the second profile is listed"
  assert_contains "$HM_OUTPUT" "yes" "the active profile is marked"
}

test_profile_show_prints_paths_and_generations() {
  _profile_commands_fixture

  run_hm profile show alpha

  assert_rc 0 "$HM_STATUS" "profile show succeeds"
  assert_contains "$HM_OUTPUT" "Profile alpha" "the profile heading is printed"
  assert_contains "$HM_OUTPUT" "Paths:" "the path count is printed"
  assert_contains "$HM_OUTPUT" "Generations:" "the generation count is printed"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/alpha/a.txt" "the tracked path is printed"
  assert_contains "$HM_OUTPUT" "alpha-1" "the generation is printed"
  assert_not_contains "$HM_OUTPUT" "beta-1" "the other profile is not printed"
}

test_profile_use_sets_the_active_context() {
  _profile_commands_fixture

  run_hm profile use alpha

  assert_rc 0 "$HM_STATUS" "profile use succeeds"
  assert_sql "alpha" "SELECT value FROM state WHERE key = 'active_profile';" \
    "the active profile is stored"
  assert_contains "$HM_OUTPUT" "alpha" "the output names the active profile"

  run_hm profile use beta

  assert_rc 0 "$HM_STATUS" "the context can be switched"
  assert_sql "beta" "SELECT value FROM state WHERE key = 'active_profile';" \
    "the new active profile is stored"
}

test_profile_use_without_a_name_prints_the_context() {
  _test_setup profile_use_print

  run_hm profile use
  assert_rc 0 "$HM_STATUS" "profile use without a name succeeds"
  assert_contains "$HM_OUTPUT" "No active profile" "the empty context is reported"

  run_hm profile use default
  run_hm profile use
  assert_rc 0 "$HM_STATUS" "profile use without a name succeeds after a selection"
  assert_contains "$HM_OUTPUT" "default" "the active profile is reported"
}

test_active_context_scopes_add_and_gen() {
  _profile_commands_fixture
  printf 'two\n' > "$SRC_DIR/alpha/two.txt"

  run_hm profile use alpha
  run_hm_input 'y\n' add "$SRC_DIR/alpha/two.txt"
  assert_rc 0 "$HM_STATUS" "add uses the active profile"
  assert_sql "1" \
    "SELECT COUNT(*) FROM pending_paths pp
       JOIN profiles pr ON pr.id = pp.profile_id
      WHERE pr.name = 'alpha';" \
    "the path is pending in the active profile"
  assert_sql "0" \
    "SELECT COUNT(*) FROM pending_paths pp
       JOIN profiles pr ON pr.id = pp.profile_id
      WHERE pr.name = 'beta';" \
    "the other profile is untouched"

  run_hm_input 'y\n' gen --name "alpha-2"
  assert_rc 0 "$HM_STATUS" "gen uses the active profile"
  assert_sql "alpha" \
    "SELECT pr.name FROM generations g JOIN profiles pr ON pr.id = g.profile_id
      ORDER BY g.id DESC LIMIT 1;" \
    "the new generation belongs to the active profile"
  assert_sql "2" \
    "SELECT COUNT(*) FROM generations g JOIN profiles pr ON pr.id = g.profile_id
      WHERE pr.name = 'alpha';" \
    "the active profile has both generations"
  assert_sql "1" \
    "SELECT COUNT(*) FROM generations g JOIN profiles pr ON pr.id = g.profile_id
      WHERE pr.name = 'beta';" \
    "the other profile keeps its single generation"
}

test_active_context_scopes_list_and_status() {
  _profile_commands_fixture

  run_hm profile use alpha

  run_hm list
  assert_rc 0 "$HM_STATUS" "list succeeds in a context"
  assert_contains "$HM_OUTPUT" "alpha-1" "the active profile is shown"
  assert_not_contains "$HM_OUTPUT" "beta-1" "the other profile is hidden"

  run_hm status
  assert_rc 0 "$HM_STATUS" "status succeeds in a context"
  assert_contains "$HM_OUTPUT" "alpha-1" "the active profile is shown"
  assert_not_contains "$HM_OUTPUT" "beta-1" "the other profile is hidden"
}

test_explicit_profile_beats_the_active_context() {
  _profile_commands_fixture
  printf 'extra\n' > "$SRC_DIR/beta/extra.txt"

  run_hm profile use alpha
  run_hm_input 'y\n' add --profile beta "$SRC_DIR/beta/extra.txt"

  assert_rc 0 "$HM_STATUS" "an explicit profile wins for add"
  assert_sql "1" \
    "SELECT COUNT(*) FROM pending_paths pp
       JOIN profiles pr ON pr.id = pp.profile_id
      WHERE pr.name = 'beta';" \
    "the explicit profile received the path"
  assert_sql "0" \
    "SELECT COUNT(*) FROM pending_paths pp
       JOIN profiles pr ON pr.id = pp.profile_id
      WHERE pr.name = 'alpha';" \
    "the active profile was not touched"

  run_hm list --profile beta
  assert_rc 0 "$HM_STATUS" "list accepts the explicit profile"
  assert_contains "$HM_OUTPUT" "beta-1" "the explicit profile is shown"
  assert_not_contains "$HM_OUTPUT" "alpha-1" "the active profile is hidden"
}

test_the_environment_context_is_used_and_overridden() {
  _profile_commands_fixture

  HM_PROFILE=alpha run_hm list
  assert_rc 0 "$HM_STATUS" "the environment context is accepted"
  assert_contains "$HM_OUTPUT" "alpha-1" "the environment profile is shown"
  assert_not_contains "$HM_OUTPUT" "beta-1" "the other profile is hidden"

  HM_PROFILE=alpha run_hm list --profile beta
  assert_rc 0 "$HM_STATUS" "an explicit profile wins over the environment"
  assert_contains "$HM_OUTPUT" "beta-1" "the explicit profile is shown"
  assert_not_contains "$HM_OUTPUT" "alpha-1" "the environment profile is hidden"

  HM_PROFILE=alpha run_hm profile use beta
  assert_rc 0 "$HM_STATUS" "the persisted context can change while the environment is set"
  assert_sql "beta" "SELECT value FROM state WHERE key = 'active_profile';" \
    "the persisted context is independent of the environment"
}

test_invalid_or_unknown_contexts_are_rejected() {
  _profile_commands_fixture

  HM_PROFILE=missing run_hm list
  assert_rc 3 "$HM_STATUS" "an unknown environment profile is a validation error"
  assert_contains "$HM_OUTPUT" "missing" "the error names the unknown profile"

  HM_PROFILE="bad name" run_hm list
  assert_rc 2 "$HM_STATUS" "an invalid environment profile is a usage error"

  printf 'more\n' > "$SRC_DIR/alpha/more.txt"
  HM_PROFILE=missing run_hm_input 'y\n' add --profile alpha "$SRC_DIR/alpha/more.txt"
  assert_rc 0 "$HM_STATUS" "an explicit profile wins over an invalid environment"
  assert_sql "2" \
    "SELECT COUNT(*) FROM path_profiles x JOIN profiles pr ON pr.id = x.profile_id
      WHERE pr.name = 'alpha';" \
    "the explicit profile was used"

  run_hm profile use missing
  assert_rc 3 "$HM_STATUS" "an unknown profile cannot become active"
}

test_active_context_scopes_generation_commands() {
  _profile_commands_fixture

  run_hm profile use alpha

  run_hm show 1
  assert_rc 0 "$HM_STATUS" "show reads a generation of the active profile"

  run_hm show 2
  assert_rc 3 "$HM_STATUS" "show rejects a generation of another profile"
  assert_contains "$HM_OUTPUT" "does not belong" "the error explains the scope"

  run_hm diff 1 2
  assert_rc 3 "$HM_STATUS" "diff rejects a generation of another profile"

  run_hm edit 2 --name "changed" --yes
  assert_rc 3 "$HM_STATUS" "edit rejects a generation of another profile"

  run_hm delete 2 --yes
  assert_rc 3 "$HM_STATUS" "delete rejects a generation of another profile"

  run_hm switch 2
  assert_rc 3 "$HM_STATUS" "switch rejects a generation of another profile"

  assert_sql "2" "SELECT COUNT(*) FROM generations;" "no generation was removed"
  assert_sql "beta-1" "SELECT name FROM generations WHERE id = 2;" \
    "the rejected edit changed nothing"
}

test_explicit_profile_scopes_generation_commands() {
  _profile_commands_fixture
  printf 'two\n' > "$SRC_DIR/alpha/two.txt"
  run_hm_input 'y\n' add --profile alpha "$SRC_DIR/alpha/two.txt"
  run_hm_input 'y\n' gen --profile alpha --name "alpha-2"

  run_hm profile use beta

  run_hm show --profile alpha 1
  assert_rc 0 "$HM_STATUS" "show accepts an explicit profile"
  assert_contains "$HM_OUTPUT" "alpha-1" "the requested generation is shown"

  run_hm diff --profile alpha 1 3
  assert_rc 0 "$HM_STATUS" "diff accepts an explicit profile"

  run_hm edit --profile alpha 3 --name "alpha-2b" --yes
  assert_rc 0 "$HM_STATUS" "edit accepts an explicit profile"
  assert_sql "alpha-2b" "SELECT name FROM generations WHERE id = 3;" \
    "the generation was edited"

  run_hm switch --profile alpha 1
  assert_rc 0 "$HM_STATUS" "switch accepts an explicit profile"
  assert_sql "1" "SELECT value FROM state WHERE key = 'selected_generation:alpha';" \
    "the profile selection was recorded"

  run_hm delete --profile alpha 3 --yes
  assert_rc 0 "$HM_STATUS" "delete accepts an explicit profile"
  assert_sql "0" "SELECT COUNT(*) FROM generations WHERE id = 3;" \
    "the generation was deleted"
}

test_active_context_applies_the_profile_selection() {
  _profile_commands_fixture

  run_hm switch 1
  run_hm switch 2
  run_hm profile use alpha

  run_hm apply --dry-run
  assert_rc 0 "$HM_STATUS" "apply succeeds in a context"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/alpha/a.txt" \
    "the selection of the active profile is applied"
  assert_not_contains "$HM_OUTPUT" "$SRC_DIR/beta/b.txt" \
    "the other profile is not applied"

  run_hm apply --profile beta --dry-run
  assert_rc 0 "$HM_STATUS" "apply accepts an explicit profile"
  assert_contains "$HM_OUTPUT" "$SRC_DIR/beta/b.txt" \
    "the explicit profile selection is applied"
  assert_not_contains "$HM_OUTPUT" "$SRC_DIR/alpha/a.txt" \
    "the active profile is not applied"
}

test_profile_rename_moves_the_context_and_selection() {
  _profile_commands_fixture

  run_hm profile use alpha
  run_hm switch 1

  run_hm_input 'y\n' profile rename alpha gamma

  assert_rc 0 "$HM_STATUS" "profile rename succeeds"
  assert_sql "1" "SELECT COUNT(*) FROM profiles WHERE name = 'gamma';" \
    "the new name exists"
  assert_sql "0" "SELECT COUNT(*) FROM profiles WHERE name = 'alpha';" \
    "the old name is gone"
  assert_sql "gamma" "SELECT value FROM state WHERE key = 'active_profile';" \
    "the active context follows the rename"
  assert_sql "1" "SELECT value FROM state WHERE key = 'selected_generation:gamma';" \
    "the profile selection follows the rename"
  assert_sql "0" "SELECT COUNT(*) FROM state WHERE key = 'selected_generation:alpha';" \
    "the old selection key is gone"

  run_hm list
  assert_rc 0 "$HM_STATUS" "the renamed context works"
  assert_contains "$HM_OUTPUT" "alpha-1" "the generation stayed in the renamed profile"

  run_hm_input 'y\n' profile rename default other
  assert_rc 3 "$HM_STATUS" "the default profile cannot be renamed"
}

test_profile_delete_protects_the_default_and_the_active_profile() {
  _profile_commands_fixture

  run_hm profile delete default --yes
  assert_rc 3 "$HM_STATUS" "the default profile cannot be deleted"
  assert_contains "$HM_OUTPUT" "default" "the error names the protected profile"

  run_hm profile use alpha
  run_hm profile delete alpha --yes
  assert_rc 3 "$HM_STATUS" "the active profile cannot be deleted"
  assert_contains "$HM_OUTPUT" "active" "the error explains the active context"
  assert_sql "1" "SELECT COUNT(*) FROM profiles WHERE name = 'alpha';" \
    "the active profile was kept"

  HM_PROFILE=beta run_hm profile delete alpha --yes
  assert_rc 3 "$HM_STATUS" "a stored active profile is protected behind an environment context"
  assert_sql "1" "SELECT COUNT(*) FROM profiles WHERE name = 'alpha';" \
    "the stored active profile was kept"

  HM_PROFILE=beta run_hm profile delete beta --yes
  assert_rc 3 "$HM_STATUS" "the environment profile cannot be deleted"
  assert_sql "1" "SELECT COUNT(*) FROM profiles WHERE name = 'beta';" \
    "the environment profile was kept"
}

test_profile_delete_requires_force_for_history() {
  _profile_commands_fixture

  run_hm profile delete alpha --yes
  assert_rc 3 "$HM_STATUS" "history requires an explicit force"
  assert_contains "$HM_OUTPUT" "force" "the error explains the force option"
  assert_sql "1" "SELECT COUNT(*) FROM profiles WHERE name = 'alpha';" \
    "the profile was kept"
  assert_sql "1" "SELECT COUNT(*) FROM generations WHERE id = 1;" \
    "the generation was kept"

  run_hm_input 'n\n' profile delete alpha --force
  assert_rc 7 "$HM_STATUS" "the confirmation can decline the forced deletion"
  assert_sql "1" "SELECT COUNT(*) FROM profiles WHERE name = 'alpha';" \
    "the declined deletion changed nothing"
}

test_profile_delete_force_keeps_shared_paths() {
  _test_setup profile_delete_shared
  printf 'shared\n' > "$SRC_DIR/shared.txt"

  run_hm_input 'y\n' add --profile alpha "$SRC_DIR/shared.txt"
  run_hm_input 'y\n' gen --profile alpha
  run_hm_input 'y\n' add --profile beta "$SRC_DIR/shared.txt"
  run_hm_input 'y\n' gen --profile beta
  local object_count
  object_count="$(find "$STORE_DIR" -type f | wc -l)"

  run_hm profile delete alpha --force --yes

  assert_rc 0 "$HM_STATUS" "the forced deletion succeeds"
  assert_sql "0" "SELECT COUNT(*) FROM profiles WHERE name = 'alpha';" \
    "the profile was deleted"
  assert_sql "1" "SELECT COUNT(*) FROM profiles WHERE name = 'beta';" \
    "the other profile was kept"
  assert_sql "1" "SELECT COUNT(*) FROM generations;" \
    "only the other generation remains"
  assert_sql "1" "SELECT COUNT(*) FROM paths WHERE path = '$SRC_DIR/shared.txt';" \
    "the shared path row is kept"
  assert_sql "1" \
    "SELECT COUNT(*) FROM path_profiles x JOIN profiles pr ON pr.id = x.profile_id
      WHERE pr.name = 'beta';" \
    "the shared path is still a member of the other profile"
  assert_eq "$object_count" "$(find "$STORE_DIR" -type f | wc -l)" \
    "the content objects remain until hm clean"
}

test_profile_delete_removes_the_orphan_paths() {
  _test_setup profile_delete_orphan
  printf 'only\n' > "$SRC_DIR/only.txt"

  run_hm_input 'y\n' add --profile alpha "$SRC_DIR/only.txt"
  run_hm_input 'y\n' gen --profile alpha

  run_hm profile delete alpha --force --yes

  assert_rc 0 "$HM_STATUS" "the forced deletion succeeds"
  assert_sql "0" "SELECT COUNT(*) FROM paths WHERE path = '$SRC_DIR/only.txt';" \
    "the path of the deleted profile was removed"
  assert_sql "0" "SELECT COUNT(*) FROM path_profiles;" \
    "no membership was left behind"
  assert_sql "0" "SELECT COUNT(*) FROM pending_paths;" \
    "no pending row was left behind"
}

test_no_active_context_keeps_the_existing_behaviour() {
  _profile_commands_fixture
  printf 'default\n' > "$SRC_DIR/default.txt"

  run_hm list
  assert_rc 0 "$HM_STATUS" "list succeeds without a context"
  assert_contains "$HM_OUTPUT" "alpha-1" "every profile is shown"
  assert_contains "$HM_OUTPUT" "beta-1" "every profile is shown"

  run_hm_input 'y\n' add "$SRC_DIR/default.txt"
  assert_rc 0 "$HM_STATUS" "add succeeds without a context"
  assert_sql "1" \
    "SELECT COUNT(*) FROM path_profiles x JOIN profiles pr ON pr.id = x.profile_id
      WHERE pr.name = 'default';" \
    "the default profile is the fallback"
}

test_profile_help_is_available() {
  _test_setup profile_help raw

  run_hm profile --help
  assert_rc 0 "$HM_STATUS" "profile help succeeds"
  assert_contains "$HM_OUTPUT" "profile add" "the help documents add"
  assert_contains "$HM_OUTPUT" "profile list" "the help documents list"
  assert_contains "$HM_OUTPUT" "profile show" "the help documents show"
  assert_contains "$HM_OUTPUT" "profile use" "the help documents use"
  assert_contains "$HM_OUTPUT" "profile rename" "the help documents rename"
  assert_contains "$HM_OUTPUT" "profile delete" "the help documents delete"

  run_hm profile
  assert_rc 2 "$HM_STATUS" "a missing subcommand is a usage error"

  run_hm profile unknown
  assert_rc 2 "$HM_STATUS" "an unknown subcommand is a usage error"
}

test_profile_output_respects_the_colour_mode() {
  _profile_commands_fixture

  HM_COLOR=always run_hm profile list
  assert_rc 0 "$HM_STATUS" "the coloured listing succeeds"
  assert_contains "$HM_OUTPUT" $'\033[' "the forced colour emits an escape sequence"

  HM_COLOR=never run_hm profile list
  assert_rc 0 "$HM_STATUS" "the uncoloured listing succeeds"
  assert_not_contains "$HM_OUTPUT" $'\033[' "the disabled colour emits no escape sequence"

  NO_COLOR=1 HM_COLOR=always run_hm profile list
  assert_rc 0 "$HM_STATUS" "the NO_COLOR listing succeeds"
  assert_not_contains "$HM_OUTPUT" $'\033[' "NO_COLOR wins over HM_COLOR"
}
