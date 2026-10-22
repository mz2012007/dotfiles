# PROJECT_MAP — HM-Lite

> External memory for the HM-Lite project. Source of truth for architecture context.
> Last updated: 2026-10-22 (system date verified via `date`).

---

## [TECH_STACK]

| Component | Choice | Version (system) | Version (upstream latest stable) | Notes |
|---|---|---|---|---|
| Shell | Bash | 5.3.0 (2024-05-24) | 5.3.x | `#!/usr/bin/env bash`, `set -euo pipefail` |
| DB | SQLite (CLI) | 3.53.4 (2026-07-24) | 3.54.1 (2026-10-16) | Local CLI is 3.53.4 — no syntax newer than that. No deprecated features. |
| Hashing | `sha256sum` (GNU coreutils) | 9.4 | 9.x | Content identity = SHA-256 of file bytes |
| Locking | `flock` (util-linux) | 2.41.4 | 2.41.x | Project-level exclusive lock for mutating commands |
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
        ├── hm add   ──► discover (find -print0) ──► normalize ──► dedupe
        │                   ──► preview ──► confirm ──► TX: paths + pending_paths
        │                   (NO hashing, NO store write, NO generation)
        │
        ├── hm gen   ──► LOCK ──► read pending manifest ──► stat each path
        │                   ──► stage copy ──► sha256 ──► store object (verify)
        │                   ──► TX: files + generations + generation_entries
        │                   ──► clear pending (inside the same TX)
        │
        ├── hm list  ──► read-only (shared lock): generations / entries / pending
        │                   (every query is checked: a failing query = exit 5, never an empty table)
        │
        ├── hm switch <gen> ──► validate gen + objects ──► materialize staging
        │                   ──► atomic rename ──► current/  (live FS untouched)
        │
        ├── hm apply ──► classify (CREATE/UPDATE/MODE/UNCHANGED/CONFLICT)
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
        │                      ├── static tables: 10 commands + help + -h/--help/--version,
        │                      │                   and the options of the current command only
        │                      └── paths: filesystem completion + tracked paths
        │                                (SELECT path FROM paths ORDER BY path)
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
| `core/add.sh` | Registration only. Discovery → preview → confirm → TX(insert paths + pending). |
| `core/gen.sh` | Content capture. Lock, stage, hash, store, TX, clear pending, verify. |
| `core/list.sh` | Read-only views: generations, entries, pending, store stats. |
| `core/switch.sh` | Select generation + materialize into `current/` (atomic). Never touches live FS. |
| `core/apply.sh` | Live-filesystem write path. Preview → backup → confirm → stage → verify → rollback. |
| `core/discard.sh` | Reset `testing/` from `current/`. HM-owned workspace only. |
| `core/backup.sh` | Consistent backup: `sqlite3 .backup` + store + manifest + checksums. |
| `core/restore.sh` | Validate → stage → verify → activate restored runtime state. |
| `core/clean.sh` | GC: exact reference analysis → preview → confirm → delete. |
| `lib/common.sh` | Error/report, `require_cmd`, `confirm`, temp files, run helpers. (The exit codes live in the dispatcher.) |
| `lib/logging.sh` | Levels ERROR/WARN/INFO/DEBUG; append-only file log; colour auto-disable. |
| `lib/paths.sh` | Path normalization, validation, containment checks, safe join. |
| `lib/database.sh` | sqlite3 invocation, `sql_quote` escaping, TX helper, migrations, `PRAGMA`s. |
| `lib/hashing.sh` | `sha256` of a file / of staged bytes. |
| `lib/storage.sh` | Content store: put / get / verify / prefix layout. |
| `lib/generations.sh` | Generation creation, materialization, entry listing. |
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
`db/schema.sql` and `lib/` are that one-line query and
`SELECT path FROM paths ORDER BY path`, deliberately duplicated in the
three files: a shared library would have to be sourced by three different
shells.

### Data model (schema v1 — authoritative file `db/schema.sql`)

```
paths(id PK, path UNIQUE, kind, created_at)
   │
   ├── pending_paths(path_id PK/FK, added_at)
   │
   └── generation_entries(generation_id PK/FK, path_id PK/FK, file_id FK, entry_type,
                          mode, owner_uid, group_gid, mtime, size)
              │                        │
      generations(id PK, name, comment, created_at, parent_id)   files(id PK, hash UNIQUE, size, created_at)
                                                          └──► store/objects/<2-hex>/<sha256>
state(key PK, value)  ── 'selected_generation'
```

Invariants:
- `paths.path` UNIQUE; `files.hash` UNIQUE; `generation_entries` PK `(generation_id, path_id)`.
- Foreign keys ON on every connection. `files` referenced by entries → `ON DELETE RESTRICT`.
- Generations are immutable: entries are never rewritten, only inserted.
- Generation ordering = `ORDER BY created_at DESC, id DESC` (IDs are identifiers, not order).

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

`hm_gen_selected`, `hm_gen_latest` and `hm_gen_exists` report a database
failure themselves instead of returning an empty value. `hm clean` stops
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
| J | Schema versioning via `PRAGMA user_version` + numbered SQL migrations in `db/migrations/` | DECIDED — `user_version=1`, `db/schema.sql` is the single authoritative file |
| K | The configuration file is parsed as **data**, never sourced; the environment wins over the file | DECIDED — implemented in `lib/common.sh` and the dispatcher |
| L | `apply` refuses every destination outside `$HOME` unless `HM_ALLOW_OUTSIDE_HOME=1` | DECIDED — implemented in `core/apply.sh` |
| M | A declined confirmation ends the command with exit code **7** (`HM_EX_DECLINED`) instead of 0 | DECIDED — implemented in `add`, `gen`, `apply`, `clean`, `restore`; a script can tell "declined" from "done" |
| N | `hm backup` has **no** `--yes` flag: the backup never changes the project state and therefore never prompts (it must stay scriptable for cron) | DECIDED — implemented in `core/backup.sh`; the flag is rejected with exit 2 |
| O | The exit code constants live in the dispatcher (`hm`), the libraries use them, there is no second definition | DECIDED — implemented in `hm`; `HM_EX_OK`/`HM_EX_ERROR` are used for the bootstrap failures |
| P | Every database and store read is checked; a failed query is never an empty result | DECIDED — implemented via the out-variable helpers; `clean` refuses to remove anything when a read fails |
| Q | Completion = three independent, self-contained files (`completions/hm.bash`, `hm.zsh`, `hm.fish`) with **no** shared library and **no** installer. The dynamic part is a direct read-only `sqlite3` query, not `hm list`: no lock, no write, no `PRAGMA integrity_check`, and every failure degenerates to "no suggestion" with exit 0. Commands and options are hard-coded from the real CLI surface (`backup` has no `--yes`), positional arguments are only completed while they are still valid. | DECIDED — implemented; covered by `tests/cases/09_completion.sh` (18 tests). Zsh is verified in a container because it is not installed on the host (documented limit) |

### Legacy artifacts

- `dev/hm/` — the abandoned **C prototype**. Its schema was
  `tracked(root_path)` + `paths(tracked_id, rel_path, type)`, it had no
  content store and no generations.
  **Not reused.** Nothing of it is referenced by HM-Lite, and it is not
  part of this project. The git history keeps the old code, the working
  tree of `dev/hm/` was left untouched by the HM-Lite work.
- **Nothing is committed.** The whole HM-Lite project lives in the working
  tree of `dev/hm-lite/`. The repository also holds unrelated unstaged
  changes (`dev/hm/test/k1`) that were not touched.

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

Test totals: **123 checks, 123 passing** (`./tests/run.sh`) = 121 test
cases + `bash -n` syntax check + ShellCheck (0 findings). The runner
reports 122 checks when ShellCheck is not on the `PATH`. On this host the
two Zsh tests print an explicit `SKIP` line (Zsh is not installed) and
count as passed without exercising the Zsh completion; a missing
interpreter never fails the suite.

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
- The parent of a new generation is always the newest generation (`created_at DESC, id DESC`),
  the history is linear.
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
- Completion reads `generations.id` and `paths.path` directly. A schema
  migration has to update `completions/hm.bash`, `hm.zsh` and `hm.fish`
  together (decision Q).
- Zsh is not installed on the development host. The Zsh completion was
  verified with `zsh -n`, a `compinit` registration check, a behavioural
  harness with stubbed completion primitives and a real interactive
  pseudo terminal inside a Debian container (Zsh 5.9); on the host the
  suite prints `SKIP` for its two Zsh tests.
