# HM-Lite — Complete Wiki Reference

> **Project:** `hm-lite` — A generation-based file and configuration manager  
> **Version:** 0.1.0  
> **Language / Runtime:** Bash 4.4+ with SQLite CLI  
> **Location:** `/home/mz/dev/hm-lite/`  
> **Author / Source:** Internal development project (`dev/hm-lite/`)  
> **Date compiled:** 2026-10-22

---

## 1. What Is HM-Lite? (Executive Summary)

HM-Lite is a **small, pure-shell generation manager** for files and configurations. It does not use a daemon, compiled binary, or external database server. It uses:

- **Bash** (associative arrays, `printf -v`, process substitution awareness)
- **SQLite CLI** (local `.db.sqlite` file)
- **Coreutils / util-linux** (`sha256sum`, `find -print0`, `flock`, `tar`, `stat`)

### Core Concept

A **generation** is an immutable snapshot of tracked filesystem paths. To make a snapshot:

1. You register paths with `hm add` (registration only — no hashing, no storage).
2. You capture content with `hm gen` — the command hashes every file with SHA-256, stores unique bytes in a content-addressable store (`store/objects/ab/abcdef...`), and records the state in the database.
3. Every generation is complete: pending paths are captured fresh, other tracked paths carry their parent generation's content forward, and vanished paths are dropped.

The system supports:
- Read-only inspection (`list`, `status`, `show`, `diff`)
- Workspace materialization (`switch` writes to `current/`, `discard` resets `testing/`)
- Live filesystem writes (`apply` with previews, backups, verification, rollback)
- Backup and restore (`backup` creates `.tar.gz`; `restore` validates checksums and schema)
- Garbage collection (`clean` removes unreferenced content objects)
- Shell completion for Bash, Zsh, and Fish

---

## 2. Project Structure (Directory Tree)

```
hm-lite/
├── hm                          # Main dispatcher / entry point
├── config                      # Default configuration template (data, never sourced)
├── README.md                   # User-facing overview and quick start
├── PROJECT_MAP.md              # Architecture, decision log, test inventory
├── detailed.md                 # This file
│
├── core/                       # Command modules (one per command)
│   ├── init.sh                 # Bootstrap: dirs, config, database
│   ├── add.sh                  # Register paths for next generation
│   ├── gen.sh                  # Capture pending paths into generation
│   ├── list.sh                 # Read-only views (generations, entries, pending, store)
│   ├── status.sh               # Dashboard: project + store + per-gen size
│   ├── show.sh                 # Detailed metadata + entry table of one generation
│   ├── diff.sh                 # Compare consecutive pairs of generations
│   ├── edit.sh                 # Change name/comment of a generation
│   ├── switch.sh               # Select + materialize into current/
│   ├── delete.sh               # Delete generation (refuses selected; one TX)
│   ├── apply.sh                # Write generation to live filesystem
│   ├── discard.sh              # Reset testing/ from current/
│   ├── backup.sh               # Consistent archive of db + store + manifest
│   ├── restore.sh              # Validate + activate backup archive
│   └── clean.sh                # Garbage collect unreferenced store objects
│
├── lib/                        # Reusable primitives (never prompt/user-facing alone)
│   ├── common.sh               # Error reporting (`hm_die`), confirmation (`hm_confirm`),
│   │                          # config parsing (`hm_config_load`), time helpers,
│   │                          # safe removal (`hm_rm_rf_under`), byte formatting
│   ├── logging.sh              # Color palettes per stream (stderr/stdout),
│   │                          # log levels (ERROR/WARN/INFO/DEBUG), file logging
│   ├── paths.sh                # Normalization (lexical, not `realpath`),
│   │                          # containment checks, safe targets (`/` refused)
│   ├── database.sh             # SQLite invocation (`sqlite3 -bail`),
│   │                          # SQL quoting (`hm_sql_quote`), hex encoding/decoding,
│   │                          # transaction helper (`hm_db_tx`), migrations
│   ├── hashing.sh              # SHA-256 file/hash (`sha256sum`), validation
│   ├── storage.sh              # Content store: put/get/verify/remove,
│   │                          # prefix layout (`ab/`), object listing
│   ├── generations.sh          # Generation queries, materialization,
│   │                          # entry listing (`hm_gen_entries`)
│   ├── validation.sh           # Runtime validation (dirs, DB integrity,
│   │                          # foreign keys, schema version, store)
│   └── locking.sh              # `flock` wrapper (exclusive / shared) on `hm.lock`
│
├── db/
│   ├── schema.sql              # Authoritative schema (version 1, PRAGMA user_version)
│   └── migrations/
│       └── README.md           # Migration naming rules (`00NN_*.sql`)
│
├── completions/                # Self-contained, never loaded by `hm`
│   ├── hm.bash                 # Bash (`_hm`, `complete -F _hm`)
│   ├── hm.zsh                  # Zsh (`#compdef hm`, `_hm`)
│   └── hm.fish                 # Fish (`complete -c hm` rules)
│
├── docs/                       # Reference documentation
│   ├── architecture.md         # Two roots, module map, data flow, locking
│   ├── commands.md             # Full command reference (all options, errors)
│   ├── database-schema.md      # Tables, relations, indexes, invariants
│   ├── testing.md              # Harness, assertions, test inventory
│   ├── safety.md               # Safety rules, live write path, backups, rollback
│   └── completion.md          # Activation, scope, dynamic suggestions, limits
│
├── tests/
│   ├── run.sh                  # Test runner (filter by name substring)
│   ├── lib/
│   │   └── harness.sh          # Isolation, assertions (`assert_eq`, `assert_rc`, `assert_sql`, ...)
│   └── cases/
│       ├── 01_init.sh         # 11 tests — bootstrap
│       ├── 02_add.sh          # 15 tests — registration
│       ├── 03_gen.sh          # 15 tests — capture
│       ├── 04_list.sh         # 12 tests — read-only views
│       ├── 05_switch.sh       # 13 tests — materialization
│       ├── 06_apply.sh        # 16 tests — live write
│       ├── 07_backup.sh       # 11 tests — archive
│       ├── 08_clean.sh        # 10 tests — GC
│       ├── 09_completion.sh   # 18 tests — Bash/Zsh/Fish
│       ├── 10_show.sh         # 12 tests — detail view
│       ├── 11_delete.sh       # 15 tests — deletion
│       ├── 12_color.sh        # 8 tests — colour detection
│       ├── 13_status.sh       # 15 tests — dashboard
│       └── ...
│
└── detailed.md                 # You are reading this
```

---

## 3. The Two Roots (Critical Design Decision)

HM-Lite separates **code** from **state** permanently.

| Root | Environment | Default | What It Holds |
|---|---|---|---|
| **Runtime** (`HM_DIR`) | `HM_DIR` | `~/.config/hm-lite` | `db.sqlite`, `store/objects/`, `current/`, `testing/`, `backup/`, `logs/`, `tmp/`, `config`, `hm.lock` |
| **Code** (`HM_CODE_DIR`) | `HM_CODE_DIR` | `realpath` of `hm` script | `hm`, `core/`, `lib/`, `db/schema.sql`, `completions/`, `tests/`, `docs/` |

- The dispatcher (`hm`) resolves both independently via `hm_resolve_code_dir()` (uses `readlink -f` then `pwd -P`).
- The code directory is **never written to** at runtime. It can be shared, symlinked, or copied freely.
- The runtime directory is created by `init` and holds all mutable state.

---

## 4. Exit Codes (Public Contract — Defined Once in `hm`)

Every library and every command module uses these constants from `hm`. There is **no second definition** anywhere.

| Code | Name (constant) | Meaning |
|---|---|---|
| 0 | `HM_EX_OK` | Success |
| 1 | `HM_EX_ERROR` | Generic runtime failure |
| 2 | `HM_EX_USAGE` | Invalid command line usage |
| 3 | `HM_EX_VALIDATION` | Validation or precondition failure |
| 4 | `HM_EX_STATE` | Inconsistent state (e.g., vanished source path) |
| 5 | `HM_EX_DB` | Database failure |
| 6 | `HM_EX_STORE` | Content store failure |
| 7 | `HM_EX_DECLINED` | **User declined confirmation** (key for scripts) |
| 8 | `HM_EX_LOCK` | Project lock could not be acquired |
| 9 | `HM_EX_IO` | Filesystem / I/O failure |

**Special note:** A declined confirmation exits with `7`, not `0`. A script can distinguish "user said no" from "command succeeded." `hm backup` never asks (it only writes a new archive, never changes state) and thus can run from cron.

---

## 5. Database Schema (Authoritative: `db/schema.sql`)

Schema version: `1` (`PRAGMA user_version = 1`). Foreign keys are `ON` on every connection.

### Tables

| Table | Key Columns | Purpose |
|---|---|---|
| `schema_meta` | `key`, `value` | Project metadata (`created_at`, `hm_version`) |
| `paths` | `id` (PK), `path` (UNIQUE), `kind` (`file`/`dir`), `created_at` | Tracked filesystem locations |
| `pending_paths` | `path_id` (PK, FK→paths ON DELETE CASCADE), `added_at` | Paths queued for next `gen` |
| `files` | `id` (PK), `hash` (UNIQUE, 64 hex chars), `size`, `created_at` | Content objects (addressed by SHA-256) |
| `generations` | `id` (PK), `name`, `comment`, `created_at`, `parent_id` (FK, ON DELETE SET NULL) | Immssible snapshots |
| `generation_entries` | `(generation_id, path_id)` PK, `file_id` (FK→files ON DELETE RESTRICT), `entry_type`, `mode`, `owner_uid`, `group_gid`, `mtime`, `size` | Recorded state of a path inside a generation |
| `state` | `key` (PK), `value` | Pointers (`selected_generation`) |

### Invariants

- `paths.path` UNIQUE — same path never registered twice.
- `files.hash` UNIQUE — content stored once.
- `generation_entries` PK = `(generation_id, path_id)` — a path appears at most once per generation.
- Entries are **never updated**; a new state is always a new generation.
- `ON DELETE RESTRICT` on `file_id` prevents accidental deletion of referenced content objects.
- Generation order = `ORDER BY created_at DESC, id DESC`. The identifier is not the order.

---

## 6. The Content Store (`store/objects/`)

- Layout: `<store_root>/<2-hex-prefix>/<full-64-char-sha256>`
- Example: `store/objects/4e/07408562be...`
- Objects are **immutable** — never modified in place, only created or removed.
- A stored object is verified by hashing it again (`hm_store_verify`).
- `hm_store_put()` writes to a temp file inside the prefix directory, verifies, then `mv` into place (atomic, never partial).
- `clean` removes only objects with **no** `generation_entries` pointing at them (exact reference analysis; failing query = exit `5`; unreadable store = exit `9`; **nothing removed** in either case).

---

## 7. Command Reference (Every Command)

### `hm init`
Idempotent. Creates directories (`HM_DIR` + subdirs), writes `config` from template (if missing), applies `db/schema.sql`, validates. Works with no config and no DB (bootstrap aware).

### `hm add <path...>`
**Registration only.** Expands directories with `find -print0`; skips symlinks and special files (warning, never followed); normalizes lexically (not `realpath`); deduplicates; classifies as `NEW`/`TRACKED`/`PENDING`/`REMOVED`; previews; asks; writes in one transaction (`paths` + `pending_paths`). No hashing. No store write.

### `hm gen [options]`
Takes **exclusive lock**. Reads pending manifest (must exist; missing = exit `4`). Stages copies in `tmp/`; hashes with SHA-256; stores objects; verifies by reading back; carries parent generation entry forward; drops vanished paths; inserts `files` + `generations` + `generation_entries`; clears `pending_paths` in **same TX**.

Options: `--name`, `--comment`, `--yes`/`-y`

### `hm list [options]`
Read-only (shared lock). Shows generations overview (`--generation` for entries, `--pending`, `--paths`, `--store`). Every query is checked — a failed query = exit `5`, never an empty result.

### `hm status`
Read-only dashboard. Reports: project info, store classification (`Referenced`/`Unreferenced`/`Missing`), generation sizes (distinct objects, shared bytes counted once). Colors per stream.

### `hm show <generation>`
Read-only detail. Metadata block + rich entry table (path, type, mode, owner, size, mtime, hash). Reports missing objects (warning, never repairs).

### `hm diff <gen> <gen> [...]`
Compare consecutive pairs. Compares by `type` + `hash` + `mode` + `owner` + `group`; `mtime` ignored (same reason as `apply`). Always exits `0` — a difference is a result, not an error.

### `hm edit <generation> [options]`
Changes `generations.name`/`comment` only (`UPDATE` inside TX). Exclusive lock. At least one option required. Empty value rejected (use `--clear-name`). Preview shows old → new.

### `hm switch <generation>`
Validates all objects present; materializes into staging; atomic rename to `current/`; records in `state`; never touches live filesystem.

### `hm delete <generation>`
Refuses the **selected** generation (exit `3`). One TX (`DELETE entries` then `DELETE generation`). `ON DELETE SET NULL` clears parent of children. Content objects stay until `clean`.

### `hm apply [generation]`
Only command writing outside `HM_DIR`. Classifies every entry: `CREATE`/`UPDATE`/`MODE`/`UNCHANGED`/`CONFLICT`. Conflicts stop everything (exit `3`, nothing changed). Conflicts: symlink, type mismatch, non-dir parent, absolute/root, outside `$HOME` (unless `HM_ALLOW_OUTSIDE_HOME=1`).

Writes: backup every overwritten file (+ manifest), temp + atomic rename, directories first, modes at end, verify hash after write, rollback (manifest reversed) on mismatch (exit `9`).

### `hm discard`
Resets `testing/` from `current/`. Only touches HM-owned workspace.

### `hm backup`
Exclusive lock. `sqlite3 .backup` + store copy + `manifest.tsv` (sha256sum format) + `meta.txt`. Never changes project state → never prompts → cron-safe.

### `hm restore <archive>`
Validates: relative members, no symlinks, checksums match (`sha256sum -c`), schema version supported. Moves current state aside first; failure restores it. Clears `current/` and `testing/`.

### `hm clean`
Exact reference analysis. Removes unreferenced objects + DB rows. Reports `MISSING` (never touches). Failing query = exit `5`; unreadable store = exit `9`; nothing removed unless all reads succeed.

---

## 8. Safety Model (Critical)

| Rule | Enforcement |
|---|---|
| No privilege escalation | No `sudo`, `su`, setuid, daemon anywhere |
| No blind deletion | Only `hm_rm_rf_under` (refuses root/non-contained targets) |
| No raw path in SQL | `hm_sql_quote` (double single quote) + hex encoding for paths |
| No half-applied state | Every write inside `hm_db_tx` (`BEGIN IMMEDIATE`; rollback on failure) |
| No surprise changes | Preview + confirmation for every mutating command; `--yes` skips; `--dry-run` stops |
| No silent empty state | Every query checked via `hm_db_rows` / `hm_db_scalar`; empty ≠ failed |
| One writer at a time | `flock` on `hm.lock`; exclusive for mutators, shared for readers; timeout = `HM_LOCK_TIMEOUT` (default 10s); failure = exit `8` |

---

## 9. Configuration (`<runtime>/config`)

Parsed as **data** (`KEY=VALUE`), never sourced/executed. Unknown keys ignored with warning.

| Key | Default | Meaning |
|---|---|---|
| `HM_LOG_LEVEL` | `INFO` | `ERROR`/`WARN`/`INFO`/`DEBUG` |
| `HM_LOG_FILE` | `1` | Write to `<runtime>/logs/hm.log` |
| `HM_COLOR` | `auto` | `auto`/`always`/`never` |
| `HM_HASH_ALGORITHM` | `sha256` | Only `sha256` implemented |
| `HM_STORE_PREFIX_LEN` | `2` | Directory prefix length in store |
| `HM_LOCK_TIMEOUT` | `10` | Seconds to wait for lock |
| `HM_ALLOW_OUTSIDE_HOME` | `0` | Allow `apply` outside `$HOME` |

**Precedence:** Environment variable > config file > built-in default. `NO_COLOR` (non-empty) always disables colors, even when `HM_COLOR=always`.

---

## 10. Shell Completion (`completions/`)

- **Self-contained:** No shared library, no installer, never loaded by `hm`.
- **Never writes, never takes lock, never runs `hm`.**
- Dynamic suggestions come from **one read-only `sqlite3` query** (`SELECT id FROM generations ORDER BY created_at DESC, id DESC;`). Failure = no suggestion, exit `0`.
- Tracks: commands, options per command (static tables), generation ids, tracked paths, backup archives.
- Bash uses builtins only (`compgen`, `mapfile`, `compopt`) — no `bash-completion` package needed.
- Zsh verified in Debian container (Zsh 5.9) because not installed on host.
- Fish verified with `complete -C`.
- All covered by `tests/cases/09_completion.sh` (18 tests).

---

## 11. Testing Overview

- **171 test cases** + `bash -n` syntax check + ShellCheck (`0` findings on host).
- Runner reports `173` checks when ShellCheck installed, `172` when missing.
- Fully isolated: each case builds its own project in `$TMPDIR`; `$HOME` never touched.
- Assertions include `assert_sql` — tests never trust code to check its own DB work.
- Optional dependencies (`fish`, `zsh`, `script`) skip gracefully with `SKIP`.

---

## 12. Key Design Decisions (Closed — From PROJECT_MAP.md)

| ID | Decision | Status |
|---|---|---|
| A | `pending_paths` dedicated table | Implemented |
| B | Only regular files + dirs tracked; symlinks skipped | Implemented |
| C | Generation = complete snapshot (pending fresh, others carried from parent, vanished dropped) | Implemented (supersedes original manifest-at-add proposal) |
| D | Missing pending path at `gen` = hard fail (exit `4`) | Implemented |
| E | `current/` = materialized copies, never hardlinks | Implemented |
| F | `switch` = select + materialize; never touches live FS | Implemented |
| G | `apply` = copy-based live write with backup + rollback | Implemented |
| H | Metadata = mode/uid/gid/mtime/size; no ACL/xattr/capabilities/hardlinks | Documented limit |
| I | DB = `<runtime>/db.sqlite`; store = `<runtime>/store/objects/`; root = `$HM_DIR` | Implemented |
| J | Schema version via `PRAGMA user_version` + `db/migrations/` | Implemented (`user_version=1`) |
| K | Config parsed as data; env wins over file | Implemented |
| L | `apply` refuses outside `$HOME` unless `HM_ALLOW_OUTSIDE_HOME=1` | Implemented |
| M | Declined confirmation = exit `7` (`HM_EX_DECLINED`) | Implemented |
| N | `backup` has **no** `--yes` flag (scriptable for cron) | Implemented (flag rejected with exit `2`) |
| O | Exit constants live only in dispatcher (`hm`) | Implemented |
| P | Every DB/store read checked; failed query ≠ empty result | Implemented (checked-read rule via out-variable helpers) |
| Q | Completion = 3 independent files, no shared library, direct `sqlite3` queries | Implemented (18 tests) |
| R | `show` = read-only detail; `delete` = one TX (refuses selected); colors honor `NO_COLOR`; each stream own palette | Implemented |
| S | `status` = read-only dashboard; generation size = distinct objects; store classified in one pass | Implemented (15 tests) |

---

## 13. Known Limits (Deliberate, Not Bugs)

- Only regular files and directories tracked; symlinks and special files skipped with warning; never followed.
- Metadata does not include ACLs, extended attributes, file capabilities, or hard links.
- Generation history is linear (`parent_id` always newest); deleting creates a gap (`ON DELETE SET NULL`).
- `apply` refuses symbolic links, type mismatches, non-absolute paths, root `/`, and paths outside `$HOME` (unless configured).
- `hm apply` never escalates privileges; no `sudo`, setuid, or daemon.
- Content objects grow until `hm clean` runs; no background GC.
- ShellCheck is optional; suite skips gracefully when missing.
- Completion is a snapshot at `<TAB>` time; new generations in other terminals don't appear in open menus.
- Schema migrations must update all 3 completion files together (deliberate duplication to avoid shared library that 3 shells can't source).

---

## 14. Quick Commands (For Readers of This Doc)

```bash
# Initialize
hm init

# Register paths (no hashing yet)
hm add ~/.bashrc ~/.config/nvim

# Create generation (hashes, stores, records)
hm gen --name "dotfiles-2026-10" --comment "working config"

# Inspect
hm list
hm status
hm show 1

# Compare
hm diff 1 2

# Materialize (into current/)
hm switch 1

# Write to live filesystem (with backup, verify, rollback)
hm apply 1

# Backup / restore
hm backup
hm restore ~/.config/hm-lite/backup/hm-backup-*.tar.gz

# Garbage collect
hm clean --dry-run
hm clean
```

---

## 15. File References (Where Each Concept Lives)

| Concept | File(s) |
|---|---|
| Dispatcher / bootstrap / exit codes | `hm` |
| Command behavior | `core/*.sh` |
| Shared primitives | `lib/*.sh` |
| Database definition | `db/schema.sql` |
| Schema migrations | `db/migrations/README.md` |
| Config template / parsing | `config`, `lib/common.sh` |
| Logging / colors | `lib/logging.sh` |
| Path normalization / validation | `lib/paths.sh` |
| Content store operations | `lib/storage.sh` |
| Hashing | `lib/hashing.sh` |
| Generation helpers / materialize | `lib/generations.sh` |
| DB access / quoting / hex / TX / migrations | `lib/database.sh` |
| Runtime validation | `lib/validation.sh` |
| Locking | `lib/locking.sh` |
| Completion (Bash/Zsh/Fish) | `completions/` |
| Tests / harness | `tests/lib/harness.sh`, `tests/run.sh` |
| User docs | `README.md`, `docs/*.md` |
| Architecture / decisions / inventory | `PROJECT_MAP.md` |
| This reference | `detailed.md` |

---

*End of HM-Lite Wiki Reference (`detailed.md`). All descriptions derived directly from the source tree at `/home/mz/dev/hm-lite/` on 2026-10-22. Every file, function, table, option, and safety rule mentioned above exists exactly as described in the working tree.*
