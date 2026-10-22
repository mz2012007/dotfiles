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
| Static analysis | ShellCheck | **not installed** | 0.11.0 (2025-08-03) | Void package `shellcheck-0.11.0_1` exists; install requires root → **not done automatically**; test suite runs it only if present |
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
        │
        ├── hm restore <bk> ──► validate members + checksums + schema version
        │                   ──► stage ──► activate (old state moved aside)
        │
        └── hm clean  ──► LOCK ──► referenced hashes (exact) ──► candidates
                            ──► preview ──► confirm ──► delete objects + rows
```

---

## [ARCHITECTURE]

### Two roots (resolved independently, never mixed)

| Root | Env | Default | Contains |
|---|---|---|---|
| **Runtime dir** | `HM_DIR` | `~/.config/hm-lite` | `db.sqlite`, `store/objects/`, `current/`, `testing/`, `backup/`, `logs/`, `tmp/`, `config`, `hm.lock` |
| **Code dir** | `HM_CODE_DIR` | realpath of the `hm` script | `hm`, `core/`, `lib/`, `db/schema.sql`, `db/migrations/`, `tests/`, `docs/` |

Schema resolution order (single authoritative file, never duplicated in Bash):
`$HM_SCHEMA_FILE` → `<code_dir>/db/schema.sql` → `<runtime_dir>/db/schema.sql`

### Module map

| File | Responsibility |
|---|---|
| `hm` | Dispatcher only. Bootstrap-aware: `init` works with no config/db present. |
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
| `lib/common.sh` | Exit codes, error/report, `require_cmd`, `confirm`, temp files, run helpers. |
| `lib/logging.sh` | Levels ERROR/WARN/INFO/DEBUG; append-only file log; colour auto-disable. |
| `lib/paths.sh` | Path normalization, validation, containment checks, safe join. |
| `lib/database.sh` | sqlite3 invocation, `sql_quote` escaping, TX helper, migrations, `PRAGMA`s. |
| `lib/hashing.sh` | `sha256` of a file / of staged bytes. |
| `lib/storage.sh` | Content store: put / get / verify / prefix layout. |
| `lib/generations.sh` | Generation creation, materialization, entry listing. |
| `lib/validation.sh` | Validate runtime dir, db, schema version, store integrity. |
| `lib/locking.sh` | `flock` wrapper (exclusive / shared) on `<runtime_dir>/hm.lock`. |

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

---

## [ORPHANS & PENDING]

**Status: closed.** No orphan code, no unimplemented command, no pending
decision. Every command of the table in `[SYSTEM_FLOW]` is implemented and
covered by the test suite. The subsections below record the closed
decisions and the documented limits, they are not open work.

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

### Legacy artifacts

- `dev/hm/` — the abandoned **C prototype**. Its schema was
  `tracked(root_path)` + `paths(tracked_id, rel_path, type)`, it had no
  content store and no generations.
  **Not reused.** Nothing of it is referenced by HM-Lite, and it is not
  part of this project. The git history keeps the old code, the working
  tree of `dev/hm/` was left untouched by the HM-Lite work.

### Implementation status

| Phase | Scope | Status |
|---|---|---|
| 1 | Bootstrap: dispatcher, `init`, schema, libs | DONE — `tests/cases/01_init.sh` (11 tests) |
| 2 | DB helpers, path validation, `add` | DONE — `tests/cases/02_add.sh` (15 tests) |
| 3 | Hashing, content store, `gen` | DONE — `tests/cases/03_gen.sh` (15 tests) |
| 4 | `list` + verification | DONE — `tests/cases/04_list.sh` (10 tests) |
| 5 | `current/`, `testing/`, `switch`, `discard` | DONE — `tests/cases/05_switch.sh` (13 tests) |
| 6 | `apply` (live FS policy) | DONE — `tests/cases/06_apply.sh` (16 tests) |
| 7 | `backup` / `restore` | DONE — `tests/cases/07_backup.sh` (10 tests) |
| 8 | `clean` (GC) | DONE — `tests/cases/08_clean.sh` (8 tests) |
| 9 | Hardening, static analysis, documentation | DONE — `docs/`, `README.md`, `db/migrations/README.md`, 99 checks green |

Test totals: **99 checks, 99 passing** (`./tests/run.sh`), 100 when
ShellCheck is installed.

### Documentation

| Document | Content |
|---|---|
| `README.md` | Overview, installation, quick start, configuration, exit codes, limits. |
| `docs/architecture.md` | The two roots, the layers, the module map, the data flow, the locking model. |
| `docs/database-schema.md` | The tables, the relations, the indexes, the invariants. |
| `docs/commands.md` | Every command with its options, its output and its errors. |
| `docs/safety.md` | The safety model, the live write path, the backup, the known limits. |
| `docs/testing.md` | The harness, the assertions, the test inventory, the static analysis. |
| `db/migrations/README.md` | The naming convention and the rules of a schema migration. |

### Known gaps / documented limits (not pending work)

- `shellcheck` is not installed on the system (root required) → the static
  analysis step of the test suite reports `SKIP`. The suite runs it
  automatically as soon as the binary is available.
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
