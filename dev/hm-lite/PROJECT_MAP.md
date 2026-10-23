# PROJECT_MAP — HM-Lite

> External memory for the HM-Lite project. Source of truth for architecture context.
> Last updated: 2026-10-23 (system date verified via `date`).

---

## [TECH_STACK]

| Component | Choice | Version (system) | Version (upstream latest stable) | Notes |
|---|---|---|---|---|
| Shell | Bash | 5.3.0 (2024-05-24) | 5.3.x | `#!/usr/bin/env bash`, `set -euo pipefail` |
| DB | SQLite (CLI) | 3.53.4 (2026-07-24) | 3.54.1 (2026-10-16) | Local CLI is 3.53.4 — no syntax newer than that. No deprecated features. |
| Hashing | `sha256sum` (GNU coreutils) | 9.4 | 9.x | Content identity = SHA-256 of file bytes |
| Locking | `flock` (util-linux) | 2.41.4 | 2.41.x | Project-level exclusive lock for mutating commands |
| Colour | ANSI SGR, `printf -v` palettes | — | — | Bright palette (`91`–`97`): bold bright cyan headings (`1;96`), dim labels (`2`), magenta pending. `HM_COLOR` (auto/always/never) plus a non-empty `NO_COLOR`; one palette per stream (stderr for diagnostics, stdout for the human readable output); auto = `[[ -t FD ]]`. The pseudo terminal tests use `script` (util-linux 2.41.4) and print `SKIP` when it is absent. |
| Files | `find` 4.10.0, `install`/`stat`/`readlink`/`mv` coreutils 9.4, `tar` 1.35 | — | — | NUL-delimited traversal (`-print0`) |
| Static analysis | ShellCheck | **0.11.0 (installed)** | 0.11.0 (2025-08-03) | Installed and **running** in the test suite: 0 findings. The runner still skips the step gracefully when the binary is absent. |
| Completion | Bash builtins (`compgen`/`mapfile`/`compopt`), Zsh `compinit`/`compadd`/`_describe`, Fish `complete` | Bash 5.3.0, Fish 4.9.3, Zsh 5.9 (verified in a container) | — | Three self-contained files in `completions/`, **no shared library and no installer**. Bash does not need the `bash-completion` package. Zsh is not installed on the host, so the suite skips its two tests with an explicit `SKIP` line. |
| OS | Void Linux, kernel 7.2.3 | — | — | Target: POSIX-ish Linux, GNU userland |

---

## [SYSTEM_FLOW]

```
hm <command> [args]
        │
        ▼
[Dispatcher: hm]  ── resolves HM_DIR (runtime) + HM_CODE_DIR (code, via realpath of $0)
        │              collects the HM_* environment (the env wins over the config file)
        │              loads lib/*.sh, then core/<command>.sh
        │
        ├── hm init  ──► dirs + config + db/schema.sql ──► db.sqlite  (idempotent)
        │
        ├── hm profile add|list|show|use|rename|delete ──► profile rows + active_profile state
        │                   (add reuses the add pipeline; use/rename/delete are TX or locked writes)
        │
        ├── hm add [--profile N] ──► context: --profile > HM_PROFILE > active > default
        │                   ──► discover (find -print0) ──► normalize ──► dedupe
        │                   ──► preview ──► confirm ──► TX: paths (+ profile membership) + pending_paths
        │                   (NO hashing, NO store write, NO generation; only an explicit --profile creates)
        │
        ├── hm gen [--profile N] ──► LOCK ──► read pending manifest of the profile ──► stat each path
        │                   ──► stage copy ──► sha256 ──► store object (verify)
        │                   ──► TX: files + generations (profile_id) + generation_entries
        │                   ──► clear the pending set of the profile (inside the same TX)
        │
        ├── hm list [--profile N] ──► read-only (shared lock): generations / entries / pending / paths
        │                   (every query is checked: a failing query = exit 5, never an empty table)
        │
        ├── hm status [--profile N] ──► read-only (shared lock): project + store space + profile/size/comment
        │                   ──► one pass over the store: referenced / unreferenced / missing
        │                   ──► generation size = distinct content objects (shared bytes counted once)
        │                   (a damaged store is reported, never repaired; missing = warning)
        │
        ├── hm show [--profile N] <gen> ──► read-only (shared lock): metadata + rich entry table
        │                   ──► reuses hm_gen_entries + hm_gen_missing_objects
        │                   (missing store objects are reported, never repaired)
        │
        ├── hm diff [--profile N] <gen...> ──► read-only (shared lock): consecutive pairs in the given order
        │                   ──► type / content hash / mode / owner / gid / size
        │                   ──► mtime ignored (apply ignores it too)
        │                   ──► never opens the store; a difference is exit 0
        │
        ├── hm edit [--profile N] <gen> ──► LOCK ──► preview old -> new ──► confirm
        │                   ──► one TX: UPDATE generations.name + comment
        │                   (entries, parent and selection untouched)
        │
        ├── hm switch [--profile N] <gen> ──► validate gen + objects ──► materialize staging
        │                   ──► atomic rename ──► current/  (live FS untouched)
        │
        ├── hm delete [--profile N] <gen> ──► LOCK ──► refuse a generation selected in any profile (exit 3)
        │                   ──► preview + confirm ──► TX: delete entries, delete generation
        │                   ──► children keep their rows, parent_id becomes empty
        │                   ──► orphan objects stay in the store until hm clean
        │
        ├── hm apply [gen] [--profile N] ──► classify (CREATE/UPDATE/MODE/UNCHANGED/CONFLICT)
        │                   ──► conflict? refuse (exit 3), nothing changed
        │                   ──► preview ──► confirm ──► back up live files + manifest
        │                   ──► staged copy ──► verify ──► rollback on failure
        │
        ├── hm discard ──► reset testing/ from current/  (only HM-owned workspace)
        │
        ├── hm backup ──► sqlite .backup + store copy ──► manifest + checksums
        │                   (never changes the project state → never prompts)
        │
        ├── hm restore <bk> ──► validate members + checksums + schema version
        │                   ──► stage ──► activate (old state moved aside)
        │
        └── hm clean  ──► LOCK ──► referenced hashes (exact) ──► candidates
                            ──► preview ──► confirm ──► delete objects + rows
                            (a failing query = exit 5, an unreadable store = exit 9,
                             nothing is removed in either case)

[Completion — outside the dispatcher]

hm <TAB>, hm <cmd> <TAB>   ──► completions/hm.{bash,zsh,fish}  (sourced by the shell, never by hm)
        │                      ├── static tables: 16 commands + help + -h/--help/--version,
        │                      │                   profile subcommands and the options of the
        │                      │                   current command only
        │                      └── paths: filesystem completion + tracked paths
        │                                (SELECT path FROM paths ORDER BY path)
        │                                profiles: SELECT name FROM profiles ORDER BY name
        │
        └── dynamic ──► sqlite3 -readonly -noheader -list <runtime>/db.sqlite
                           'SELECT id FROM generations ORDER BY created_at DESC, id DESC;'
                        (newest first, like hm list; no hm invocation, no project lock,
                         no write of any kind; any failure = no suggestion, exit 0)

A declined confirmation ends every command that asks for one with exit
code **7**. A script can therefore tell "the user said no" apart from "the
command did its work".
```

---

## [ARCHITECTURE]

### Two roots (resolved independently, never mixed)

| Root | Env | Default | Contains |
|---|---|---|---|
| **Runtime dir** | `HM_DIR` | `~/.config/hm-lite` | `db.sqlite`, `store/objects/`, `current/`, `testing/`, `backup/`, `logs/`, `tmp/`, `config`, `hm.lock` |
| **Code dir** | `HM_CODE_DIR` | realpath of the `hm` script | `hm`, `core/`, `lib/`, `completions/`, `db/schema.sql`, `db/migrations/`, `tests/`, `docs/` |

Schema resolution order (single authoritative file, never duplicated in Bash):
`$HM_SCHEMA_FILE` → `<code_dir>/db/schema.sql` → `<runtime_dir>/db/schema.sql`

### Module map

| File | Responsibility |
|---|---|
| `hm` | Dispatcher only. Bootstrap-aware: `init` works with no config/db present. Owns the `HM_EX_*` exit code constants (single definition). |
| `config` | Default `KEY=VALUE` config template (parsed as **data**, never sourced/executed). |
| `core/init.sh` | Bootstrap dirs, write config, apply `db/schema.sql`, validate. Idempotent. |
| `core/profile.sh` | Profile management (`add`, `list`, `show`, `use`, `rename`, `delete`). Reuses `_add_register` and the read-only list helpers; locks, TX, deletion policy and context updates live here. |
| `core/add.sh` | Registration only. Context resolution (`--profile` > `HM_PROFILE` > active > default), discovery → preview → confirm → TX(insert paths + profile membership + pending). Only an explicit `--profile` creates a missing profile. |
| `core/gen.sh` | Content capture of one profile. Lock, stage, hash, store, TX, clear the pending set of the profile, verify. |
| `core/list.sh` | Read-only views: generations, entries, pending, store stats; optional profile filter, PROFILE columns. |
| `core/status.sh` | Read-only dashboard: project, profile, store space (referenced / unreferenced / missing) and every generation with its profile, distinct-object size and comment. |
| `core/show.sh` | Read-only detail view of one generation: metadata block plus the rich entry table (owner, group, mtime, full path). |
| `core/diff.sh` | Read-only comparison of two or more generations: consecutive pairs in the given order, type/content hash/mode/owner/gid/size, mtime ignored; never opens the store; a difference exits 0. |
| `core/edit.sh` | Metadata edit of one generation: exclusive lock, preview, one `UPDATE` (name + comment); entries, parent and selection untouched. |
| `core/switch.sh` | Select generation + materialize into `current/` (atomic). Never touches live FS. |
| `core/delete.sh` | Delete one generation and its entries in a single TX; refuses a generation selected in any profile; leaves the orphan objects to `hm clean`. |
| `core/apply.sh` | Live-filesystem write path. Preview → backup → confirm → stage → verify → rollback. |
| `core/discard.sh` | Reset `testing/` from `current/`. HM-owned workspace only. |
| `core/backup.sh` | Consistent backup: `sqlite3 .backup` + store + manifest + checksums. |
| `core/restore.sh` | Validate → stage → verify → activate restored runtime state. |
| `core/clean.sh` | GC: exact reference analysis → preview → confirm → delete. |
| `lib/common.sh` | Error/report, `require_cmd`, `confirm`, temp files, run helpers. (The exit codes live in the dispatcher.) |
| `lib/logging.sh` | Levels ERROR/WARN/INFO/DEBUG; append-only file log; colour palettes per stream, `HM_COLOR` + `NO_COLOR`. |
| `lib/paths.sh` | Path normalization, validation, containment checks, safe join. |
| `lib/database.sh` | sqlite3 invocation, `sql_quote` escaping, TX helper, migrations, `PRAGMA`s. |
| `lib/hashing.sh` | `sha256` of a file / of staged bytes. |
| `lib/storage.sh` | Content store: put / get / verify / prefix layout. |
| `lib/profiles.sh` | Profile helpers: name validation, existence, lookup, ensure/require, active context (`hm_profile_active/scope/context_name`), context guards, profile of a generation, selection state key and selection count. |
| `lib/generations.sh` | Generation creation, materialization, entry listing, profile-aware selection and parent lookup. |
| `lib/validation.sh` | Validate runtime dir, db, schema version, store integrity. |
| `lib/locking.sh` | `flock` wrapper (exclusive / shared) on `<runtime_dir>/hm.lock`. |
| `completions/hm.bash` | Bash completion: `_hm` + `complete -o filenames -F _hm hm`. Builtins only, self-contained. |
| `completions/hm.zsh` | Zsh completion: `#compdef hm`, `_hm`. Works through `source` and through autoload as `_hm`. |
| `completions/hm.fish` | Fish completion: `complete -c hm` rules, no helper file. |

The `completions/` directory is a **consumer of the command surface**, not a
layer of the application. It is never loaded by `hm`, never writes, never
takes the project lock and never runs a command. The generation ids come
from one read-only `sqlite3` query against `<runtime>/db.sqlite` (the same
`ORDER BY created_at DESC, id DESC` as `hm list`); anything that fails —
missing file, unreadable file, damaged file — is treated as "no dynamic
suggestion" and not as an error. The only schema knowledge outside
`db/schema.sql` and `lib/` are three one-line queries
(`generations.id`, `paths.path`, `profiles.name`), deliberately
duplicated in the three files: a shared library would have to be sourced
by three different shells.

### Data model (schema v2 — authoritative file `db/schema.sql`)

```
profiles(id PK, name UNIQUE, created_at)
   │
   ├──< path_profiles >── paths(id PK, path UNIQUE, kind, created_at)
   │                         │
   │                         ├──< pending_paths(path_id, profile_id, added_at)
   │                         │
   │                         └──< generation_entries(generation_id, path_id, file_id,
   │                                                   entry_type, mode, owner_uid,
   │                                                   group_gid, mtime, size)
   │                                              │
   └──< generations(id PK, name, comment, created_at, parent_id, profile_id) >──┘
                                                              │
                                    files(id PK, hash UNIQUE, size, created_at)
                                                              └──► store/objects/<2-hex>/<sha256>

state(key PK, value)  ── 'active_profile' + 'selected_generation' +
                        'selected_generation:<profile>'
```

Invariants:
- `paths.path` UNIQUE; `profiles.name` UNIQUE; `files.hash` UNIQUE;
  `path_profiles` PK `(path_id, profile_id)`; `pending_paths` PK
  `(path_id, profile_id)`; `generation_entries` PK `(generation_id, path_id)`.
- Foreign keys ON on every connection. `files` referenced by entries → `ON DELETE RESTRICT`.
- A profile is an independent namespace: tracked paths, pending set,
  generations and selection are profile scoped; the content store,
  `current/` and `testing/` are shared. Every project has the profile
  `default`; `hm profile add` and `hm add --profile` create a missing one,
  the other commands require an existing one. The effective context is
  resolved by decision W.
- A path can belong to several profiles through `path_profiles`; it still
  has one row in `paths`.
- Generations are immutable snapshots: entries are never rewritten, only inserted.
  The name and the comment are labels for the human reader and can be changed
  with `hm edit` (decision T); the entries and the content objects stay untouched.
- The history is linear **per profile**: the parent of a new generation is the
  newest generation of the same profile.
- Deleting a generation is one TX (`generation_entries`, then `generations`): a
  generation selected in any profile is refused (exit 3), `parent_id ON DELETE SET NULL`
  keeps the children readable, and the released content objects are reclaimed only by `hm clean`.
- Generation ordering = `ORDER BY created_at DESC, id DESC` (IDs are identifiers, not order).
- `state` keeps the persisted `active_profile`, the global
  `selected_generation` and one `selected_generation:<profile>` per
  profile; `hm switch` writes both selection keys, `hm apply` uses the
  context selection or the global one. `hm profile rename` moves the
  selection key and `active_profile` to the new name in the same TX;
  `hm profile delete` protects `default` and both the effective and the
  persisted active profile.

### The checked-read rule (no silent empty state)

Bash discards the exit status of a command inside a process substitution
(`done < <(cmd)`), so a failed query would look exactly like an empty
result. Every result set is therefore read through a helper that writes
into a variable of the caller **and** returns the status of the query:

| Helper | Fills with |
|---|---|
| `hm_db_rows SQL VARIABLE` | the rows of an arbitrary statement |
| `hm_gen_entries GENERATION_ID VARIABLE` | the entries of a generation |
| `hm_gen_missing_objects GENERATION_ID VARIABLE` | the objects a generation needs but that are missing |
| `hm_store_object_hashes VARIABLE` | the hashes of the objects in the store |

`hm_gen_selected`, `hm_gen_latest`, `hm_gen_exists`, `hm_profile_exists`,
`hm_profile_id` and `hm_profile_require` report a database failure
themselves instead of returning an empty value. `hm clean` stops
with exit 5 (database) or exit 9 (store) **before** removing anything.

### Exit codes (public contract, defined once in `hm`)

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | generic runtime failure (bootstrap) |
| 2 | invalid command line usage |
| 3 | validation or precondition failure |
| 4 | inconsistent state (for example a vanished source path) |
| 5 | database failure |
| 6 | content store failure |
| 7 | **the user declined a confirmation** |
| 8 | the project lock could not be acquired |
| 9 | filesystem or input/output failure |

---

## [ORPHANS & PENDING]

**Status: closed.** No orphan code, no unimplemented command, no pending
decision. Every command of the table in `[SYSTEM_FLOW]` is implemented and
covered by the test suite, every function of `lib/` and `core/` is used,
every constant is referenced. The subsections below record the closed
decisions and the documented limits, they are not open work.

The last hardening round closed the remaining silent-failure paths: every
database and store read is checked (decision P), a declined confirmation
returns exit code 7 (decision M), `hm backup` lost its inert `--yes` flag
(decision N) and the exit code constants moved into the dispatcher
(decision O). ShellCheck is installed and the project has **0 findings**.

The completion phase added three optional shell files (decision Q). It
added no command, no option, no runtime dependency and no installation
step to the application: the completion is a consumer that the user sources
manually, and `hm` is unchanged by it.

The inspection/deletion round added `hm show` (read only) and `hm delete`
(one transaction, the selected generation refused, the orphan objects
handed to `hm clean`) and made the colour handling honour `NO_COLOR` with
one palette per stream (decision R). It added no schema change and no new
runtime dependency; the only new test dependency is optional (`script` for
the pseudo terminal checks).

The status round added `hm status` (read only dashboard, decision S) and
`hm_format_bytes` in `lib/common.sh`. It added no schema change, no new
runtime dependency and no second store walker: the command reuses
`hm_store_object_hashes`, `hm_store_path`, `hm_db_rows` and
`hm_db_scalar`. The generation size is the size of the **distinct**
content objects a generation references, so shared content is counted once
and a generation never appears larger than the store.

The colour/metadata/diff round coloured the standard output of every
command with the stdout palette, added `hm edit` (decision T) and
`hm diff` (decision U). It added no command to the store path, no schema
change and no new runtime dependency: `edit` performs one `UPDATE`,
`diff` reuses `hm_gen_entries` and never opens the content store. The only
new test dependency remains optional (`script` for the pseudo terminal
check).

The profile round moved the project from schema v1 to **schema v2**
(decision V): `profiles`, `path_profiles`, a profile column on
`pending_paths` and `generations`, the per-profile selections and the
migration `0002_profiles.sql`. It added `lib/profiles.sh` as the shared
profile layer, made `add`/`gen`/`list`/`status`/`show`/`switch`/`delete`/
`apply` profile aware and redesigned the palette in `lib/logging.sh`
(bright ANSI colours, bold bright cyan headings, dim labels). It added no
runtime dependency and no new command. The content store, `current/` and
`testing/` stayed global; the v1 data migrates into the profile `default`.

The profile-management/context round added `hm profile add|list|show|use|
rename|delete` and the `active_profile` context (decision W). It reuses the
existing tables: no schema change, no migration and no new runtime
dependency. Context precedence is explicit `--profile`, then
`HM_PROFILE`, then the persisted active profile; only an explicit
`--profile` on `add` (or `profile add` itself) creates a profile. All
profile-aware generation commands validate ownership when a context is
present and keep the legacy unscoped behaviour otherwise. The completion
files learned the profile subcommands, profile names and new `--profile`
options.

### Closed decisions

| ID | Decision | Status |
|---|---|---|
| A | Pending representation = dedicated `pending_paths` table | DECIDED — implemented in `db/schema.sql` |
| B | Supported entry types = regular file + directory; symlink/special = skipped w/ warning | DECIDED — implemented in `core/add.sh` (never followed) |
| C | Generation scope = **complete snapshot** (pending captured fresh, other tracked paths carried forward from the parent, vanished paths dropped) | DECIDED — supersedes the original "manifest at add time" proposal, implemented in `core/gen.sh` |
| D | Missing pending path at `gen` time = hard fail (exit 4); remedy = re-`add` to refresh manifest | DECIDED — implemented in `core/gen.sh` |
| E | `current/` = materialized working tree of the selected generation (copies, not hardlinks) | DECIDED — implemented in `lib/generations.sh` |
| F | `switch` = select + materialize into `current/`; never writes the live FS | DECIDED — implemented in `core/switch.sh` |
| G | `apply` = copy-based live write with per-file backup, manifest, rollback | DECIDED — implemented in `core/apply.sh` |
| H | Metadata = type, mode, uid, gid, mtime, size. NOT ACL/xattr/capabilities/hardlinks | DECIDED — documented limitation |
| I | DB = `<runtime_dir>/db.sqlite`; store = `<runtime_dir>/store/objects/`; root = `$HM_DIR` | DECIDED — implemented in `lib/paths.sh` |
| J | Schema versioning via `PRAGMA user_version` + numbered SQL migrations in `db/migrations/` | DECIDED — `user_version=2`, `db/schema.sql` is the single authoritative file; `0002_profiles.sql` migrates v1 into the profile `default` |
| K | The configuration file is parsed as **data**, never sourced; the environment wins over the file | DECIDED — implemented in `lib/common.sh` and the dispatcher |
| L | `apply` refuses every destination outside `$HOME` unless `HM_ALLOW_OUTSIDE_HOME=1` | DECIDED — implemented in `core/apply.sh` |
| M | A declined confirmation ends the command with exit code **7** (`HM_EX_DECLINED`) instead of 0 | DECIDED — implemented in `add`, `gen`, `apply`, `clean`, `restore`; a script can tell "declined" from "done" |
| N | `hm backup` has **no** `--yes` flag: the backup never changes the project state and therefore never prompts (it must stay scriptable for cron) | DECIDED — implemented in `core/backup.sh`; the flag is rejected with exit 2 |
| O | The exit code constants live in the dispatcher (`hm`), the libraries use them, there is no second definition | DECIDED — implemented in `hm`; `HM_EX_OK`/`HM_EX_ERROR` are used for the bootstrap failures |
| P | Every database and store read is checked; a failed query is never an empty result | DECIDED — implemented via the out-variable helpers; `clean` refuses to remove anything when a read fails |
| Q | Completion = three independent, self-contained files (`completions/hm.bash`, `hm.zsh`, `hm.fish`) with **no** shared library and **no** installer. The dynamic part is a direct read-only `sqlite3` query, not `hm list`: no lock, no write, no `PRAGMA integrity_check`, and every failure degenerates to "no suggestion" with exit 0. Commands and options are hard-coded from the real CLI surface (`backup` has no `--yes`), positional arguments are only completed while they are still valid. | DECIDED — implemented; covered by `tests/cases/09_completion.sh` (23 tests). Zsh is verified in a container because it is not installed on the host (documented limit) |
| R | `hm show` = read-only detail view (shared lock, metadata + rich entry table, reuses `hm_gen_entries`); `hm delete` = one transaction (`generation_entries`, then `generations`), refuses the selected generation (exit 3), lets `ON DELETE SET NULL` clear the children and leaves the unreferenced objects to `hm clean`; colours: a non-empty `NO_COLOR` always disables, otherwise `HM_COLOR=always/never` wins over the `auto` detection, and each stream gets its own palette (stderr diagnostics, stdout output) | DECIDED — implemented in `core/show.sh`, `core/delete.sh`, `lib/logging.sh`; covered by `10_show.sh` (12), `11_delete.sh` (15), `12_color.sh` (8) |
| S | `hm status` = read-only dashboard (shared lock, no argument except `-h/--help`). Store space is the on-disk byte sum, classified in one pass as referenced (used by ≥1 generation), unreferenced (garbage for `hm clean`) or missing (needed but absent). A generation's size is the sum of its **distinct** content objects (`files.size` once per hash), so shared content is never double counted. Sizes are human readable with the exact byte count next to the store totals (`hm_format_bytes`, binary units, locale-safe integer arithmetic). Colours reuse the stdout palette: bold headings, cyan selection, yellow unreferenced, red missing, green clean. | DECIDED — implemented in `core/status.sh` + `lib/common.sh`; covered by `13_status.sh` (15 tests) |
| T | `hm edit` = metadata edit of an **existing** generation (the name and the comment already existed at creation time via `hm gen --name/--comment`). At least one of `--name`, `--comment`, `--clear-name`, `--clear-comment` is required; an empty value is refused and removal has an explicit flag; `--name`+`--clear-name` (and the comment pair) conflict. Exclusive lock, preview + confirmation, one `UPDATE` in one transaction. The selected generation may be edited: the entries, the parent, the selection and the store are untouched, because a generation is immutable as a snapshot and the labels are not part of the snapshot. Unknown generation = exit 4 (same as show/delete/switch), declined = 7, failing update = 5. | DECIDED — implemented in `core/edit.sh`; covered by `14_edit.sh` (20 tests) |
| U | `hm diff` = compare two or more generations, every consecutive pair in the **given** order (`hm diff 1 2 3` = 1→2 and 2→3). An entry is compared by type, content hash, mode, owner, group and size; mtime is deliberately ignored because `hm apply` ignores it too and a copy updates it without changing the content. Markers `+`/`-`/`~`/`=` (`=` only with `--all`), with a per-pair summary. Read-only shared lock, never opens the store (recorded hashes), duplicate ids rejected, unknown generation = 4. A difference is a normal result: the command always exits 0; exit 1 stays reserved for generic runtime failures. | DECIDED — implemented in `core/diff.sh`; covered by `15_diff.sh` (19 tests) |
| V | Profiles are a real schema feature, not separate projects: `profiles`, the M2M `path_profiles`, a profile column on `pending_paths` and `generations`, one `selected_generation:<profile>` state key per profile, and a shared content store. `hm init` seeds `default`; v1 data migrates into it. `hm add --profile` creates a missing profile, the other commands require an existing one (invalid name = 2, unknown profile = 3). Without a context, `add`/`gen` use `default` and `list`/`status` show every profile (PROFILE columns); decision W adds the active context and the profile management commands. `switch` writes the per-profile and the global selection; `apply --profile` uses the profile selection; `delete` refuses a generation selected in any profile. Profile names are `[A-Za-z0-9][A-Za-z0-9._-]*`. The palette uses bright ANSI colours (`91`–`97`), bold bright cyan headings (`1;96`) and dim labels (`2`), with the stdout/stderr separation preserved. | DECIDED — implemented in `db/schema.sql`, `db/migrations/0002_profiles.sql`, `lib/profiles.sh`, the profile-aware commands, `lib/logging.sh` and the three completion files; covered by `16_profiles.sh` (19 tests) |
| W | Profile management + active context: `hm profile add|list|show|use|rename|delete` and the persisted `active_profile` state key. Context precedence = explicit `--profile` > `HM_PROFILE` > active > command default (`default` for `add`/`gen`; every profile for `list`/`status`; unscoped legacy for generation commands). Only explicit `--profile` on `add` or `profile add` creates a profile; env/active contexts require an existing one. `profile use` is a project-global persisted switch; `HM_PROFILE` is the per-process script override. `default` cannot be renamed/deleted; the effective and persisted active profiles are protected; history requires `--force`. Rename moves the selection key and active context; delete keeps shared paths, removes orphan paths only when no generation entry references them, and leaves content objects to `hm clean`. | DECIDED — implemented in `core/profile.sh`, `lib/profiles.sh`, the profile-aware command modules, dispatcher/help and all three completion files; covered by `17_profile_commands.sh` (23 tests) and the expanded `09_completion.sh` (23 tests) |


### Legacy artifacts

- `dev/hm/` — the abandoned **C prototype**. Its schema was
  `tracked(root_path)` + `paths(tracked_id, rel_path, type)`, it had no
  content store and no generations.
  **Not reused.** Nothing of it is referenced by HM-Lite, and it is not
  part of this project. The git history keeps the old code, the working
  tree of `dev/hm/` was left untouched by the HM-Lite work.
- **The implementation is committed.** The snapshot commits
  `e9a6271` (`5th-paused hm-lite`) and `3583c69` (`5th hm-lite`) contain
  the code, the tests and the earlier documentation round. The profile
  round (schema v2, profiles, palette, status comments) and the current
  profile-management/context round are **not** committed and live in the
  working tree. The snapshots also captured pre-existing unrelated changes
  (`.config/fish/...`, `dev/hm/test/k1`) that this work did not touch.

### Implementation status

| Phase | Scope | Status |
|---|---|---|
| 1 | Bootstrap: dispatcher, `init`, schema, libs | DONE — `tests/cases/01_init.sh` (11 tests) |
| 2 | DB helpers, path validation, `add` | DONE — `tests/cases/02_add.sh` (15 tests) |
| 3 | Hashing, content store, `gen` | DONE — `tests/cases/03_gen.sh` (15 tests) |
| 4 | `list` + verification | DONE — `tests/cases/04_list.sh` (12 tests) |
| 5 | `current/`, `testing/`, `switch`, `discard` | DONE — `tests/cases/05_switch.sh` (13 tests) |
| 6 | `apply` (live FS policy) | DONE — `tests/cases/06_apply.sh` (16 tests) |
| 7 | `backup` / `restore` | DONE — `tests/cases/07_backup.sh` (11 tests) |
| 8 | `clean` (GC) | DONE — `tests/cases/08_clean.sh` (10 tests) |
| 9 | Hardening, static analysis, documentation | DONE — `docs/`, `README.md`, `db/migrations/README.md`, **105 checks green** |
| 10 | Shell completion (Bash, Zsh, Fish) | DONE — `completions/`, `docs/completion.md`, `tests/cases/09_completion.sh` (18 tests); **123 checks green** on the host, 2 Zsh tests skipped there |
| 11 | `show`, `delete`, automatic colours (`NO_COLOR`) + integration | DONE — `core/show.sh`, `core/delete.sh`, `lib/logging.sh`, `10_show.sh` (12), `11_delete.sh` (15), `12_color.sh` (8); **158 checks green** on the host |
| 12 | `status` (store space + per-generation size, colourful dashboard) + integration | DONE — `core/status.sh`, `lib/common.sh`, `13_status.sh` (15), `09_completion.sh` (18); **173 checks green** on the host |
| 13 | Colour the output of every command + `edit` (metadata of an existing generation) + `diff` (two or more generations) + integration | DONE — `core/edit.sh`, `core/diff.sh`, `14_edit.sh` (20), `15_diff.sh` (19), `12_color.sh` (10); **214 checks green** on the host |
| 14 | Profiles (schema v2, shared store, per-profile paths/pending/generations/selection) + brighter palette + comments in `status` + integration | DONE — `db/schema.sql`, `db/migrations/0002_profiles.sql`, `lib/profiles.sh`, `16_profiles.sh` (19), `04_list.sh` (13), `13_status.sh` (16), `09_completion.sh` (19); **236 checks green** on the host |
| 15 | Profile management (`profile add/list/show/use/rename/delete`) + persisted active context + completion/docs/integration | DONE — `core/profile.sh`, context helpers in `lib/profiles.sh`, profile-aware commands, `hm` dispatcher/help, `17_profile_commands.sh` (23), `09_completion.sh` (23), all three completions and documentation; **263 checks green** on the host |

Test totals: **263 checks, 263 passing** (`HM_COLOR=auto ./tests/run.sh`) =
261 test cases + `bash -n` syntax check + ShellCheck (0 findings). The
runner reports 262 checks when ShellCheck is not on the `PATH`. On this
host the two Zsh tests print an explicit `SKIP` line (Zsh is not
installed) and count as passed without exercising the Zsh completion; the
two pseudo terminal colour tests would print `SKIP` without `script` from
util-linux. A missing optional tool never fails the suite.

> The staged `config` template sets `HM_COLOR=always`, so the suite has to
> be run as `HM_COLOR=auto ./tests/run.sh`: the colour assertions of the
> plain-output tests rely on the automatic detection.

### Documentation

| Document | Content |
|---|---|
| `README.md` | Overview, installation, quick start, configuration, exit codes, limits. |
| `docs/architecture.md` | The two roots, the layers, the module map, the data flow, the locking model. |
| `docs/database-schema.md` | The tables, the relations, the indexes, the invariants. |
| `docs/commands.md` | Every command with its options, its output and its errors. |
| `docs/safety.md` | The safety model, the live write path, the backup, the known limits. |
| `docs/testing.md` | The harness, the assertions, the test inventory, the static analysis. |
| `docs/completion.md` | The Bash, Zsh and Fish completion: activation, scope, dynamic suggestions, requirements, verification, limits. |
| `db/migrations/README.md` | The naming convention and the rules of a schema migration. |

### Known gaps / documented limits (not pending work)

- Upstream SQLite is 3.54.1 but the local CLI is 3.53.4 → the SQL stays
  within the 3.53.4 syntax.
- A generation is a **complete snapshot** of the tracked paths: pending paths are captured
  fresh, every other tracked path carries the content of the parent generation forward and a
  tracked path that no longer exists is dropped. Decision C supersedes the original proposal.
- The parent of a new generation is always the newest generation of the
  same profile (`created_at DESC, id DESC`), the history is linear per
  profile. Generations of different profiles are never compared by the
  history and `hm diff` still accepts any pair of ids.
- A profile name is limited to `[A-Za-z0-9][A-Za-z0-9._-]*`; `hm profile
  rename` can change it and `hm profile delete` can remove it under the
  documented policy. `current/` and `testing/` are global, so
  `hm switch`/`hm discard` always act on the workspace of the last
  selection.
- The active profile context is project-global and persisted in the
  `state` table. Every terminal sees the same value; use `HM_PROFILE` for a
  process-local context. `--profile` remains the strongest override. Only
  an explicit `--profile` on `add` (or `profile add`) creates a missing
  profile; environment and active contexts require an existing one.
- `hm delete` leaves a gap in that linear history: the children keep their rows and their
  `parent_id` becomes empty (`ON DELETE SET NULL`). The content objects that no generation
  uses any more are reclaimed only by `hm clean`, never by the delete itself.
- `hm status` reports a generation size from its **distinct** content objects, not from the
  entry sizes: content that several paths share inside one generation is counted once. The
  unformatted byte counts stay available in the database and in `hm list --store`.
- `hm diff` deliberately ignores the modification time: `hm apply` ignores it too, and a copy
  updates it without changing the content. A difference is a normal result, so `hm diff` always
  exits `0`; exit `1` remains reserved for a generic runtime failure. The command compares the
  recorded hashes and never opens the store, so a missing object does not change its output.
- `hm edit` changes only the name and the comment of a generation. The entries, the parent, the
  selection and the content objects are untouched: the snapshot stays immutable, the labels are
  metadata for the human reader.
- A non-empty `NO_COLOR` disables the colours even when `HM_COLOR=always` is set (decision R);
  an empty `NO_COLOR` counts as unset, following the convention.
- The metadata of an entry is type, mode, uid, gid, mtime and size. ACLs, extended
  attributes, file capabilities and hard links are **not** tracked (decision H).
- Only regular files and directories are tracked. Symbolic links and special files are skipped
  with a warning and are never followed.
- `apply` refuses every destination outside of `$HOME` unless `HM_ALLOW_OUTSIDE_HOME=1`.
- `apply` refuses a destination that is a symbolic link, whose type does not match the
  generation, that is not absolute or that is the root of the filesystem; it never writes
  through a link.
- `hm` never escalates privileges: no `sudo`, no setuid helper, no `su`, no daemon.
- Completion is a snapshot taken at the moment of `<TAB>`; a generation
  created in another terminal afterwards does not appear in an already
  opened menu.
- Completion reads `generations.id`, `paths.path` and `profiles.name`
  directly. A schema migration has to update `completions/hm.bash`,
  `hm.zsh` and `hm.fish` together (decision Q).
- Zsh is not installed on the development host. The Zsh completion was
  verified with `zsh -n`, a `compinit` registration check, a behavioural
  harness with stubbed completion primitives and a real interactive
  pseudo terminal inside a Debian container (Zsh 5.9); on the host the
  suite prints `SKIP` for its two Zsh tests.
