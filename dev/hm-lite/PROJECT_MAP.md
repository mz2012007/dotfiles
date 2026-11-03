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
        │
        ├── hm init  ──► bootstrap: dirs + config + schema.sql ──► db.sqlite
        │
        ├── hm add   ──► discover (find -print0) ──► normalize ──► dedupe
        │                   ──► preview ──► confirm ──► TX: paths + pending_paths
        │                   (NO hashing, NO store write, NO generation)
        │
        ├── hm gen   ──► LOCK ──► read pending manifest ──► stat each path
        │                   ──► stage copy ──► sha256 ──► store object (verify)
        │                   ──► TX: files + generations + generation_entries
        │                   ──► clear pending (only after COMMIT)
        │
        ├── hm list  ──► read-only (shared lock): generations / entries / pending
        │
        ├── hm switch <gen> ──► validate gen + objects ──► materialize staging
        │                   ──► atomic rename ──► current/  (live FS untouched)
        │
        ├── hm apply ──► preview conflicts ──► back up live files ──► confirm
        │                   ──► staged copy ──► verify ──► rollback on failure
        │
        ├── hm discard ──► reset testing/ from current/  (only HM-owned workspace)
        │
        ├── hm backup ──► sqlite .backup + store copy ──► manifest + checksums
        │
        ├── hm restore <bk> ──► validate format ──► stage ──► verify ──► activate
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
| `config` | Default `KEY=VALUE` config template (sourced as trusted shell code). |
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

### Open decisions (must be answered before the related code is written)

| ID | Decision | Status |
|---|---|---|
| A | Pending representation = dedicated `pending_paths` table | PROPOSED |
| B | Supported entry types = regular file + directory; symlink/special = skipped w/ warning | PROPOSED |
| C | Generation scope = manifest snapshot taken at `add` time; content captured at `gen` | PROPOSED |
| D | Missing pending path at `gen` time = hard fail (exit 4); remedy = re-`add` to refresh manifest | PROPOSED |
| E | `current/` = materialized working tree of the selected generation (copies, not hardlinks) | PROPOSED |
| F | `switch` = select + materialize into `current/`; never writes the live FS | PROPOSED |
| G | `apply` = copy-based live write with per-file backup, manifest, rollback | PROPOSED (needs approval) |
| H | Metadata = type, mode, uid, gid, mtime, size. NOT ACL/xattr/capabilities/hardlinks | PROPOSED |
| I | DB = `<runtime_dir>/db.sqlite`; store = `<runtime_dir>/store/objects/`; root = `$HM_DIR` | PROPOSED |
| J | Schema versioning via `PRAGMA user_version` + numbered SQL migrations in `db/migrations/` | PROPOSED |

### Legacy artifacts

- `dev/hm/` — abandoned **C prototype** (sources deleted in worktree, still in git at `a50b4a6`).
  Schema was `tracked(root_path)` + `paths(tracked_id, rel_path, type)`. No content store, no generations.
  **Not reused.** Keep or delete — pending user decision.

### Implementation status

| Phase | Scope | Status |
|---|---|---|
| 1 | Bootstrap: dispatcher, `init`, schema, libs | PLANNED |
| 2 | DB helpers, path validation, `add` | PLANNED |
| 3 | Hashing, content store, `gen` | PLANNED |
| 4 | `list` + verification | PLANNED |
| 5 | `current/`, `testing/`, `switch`, `discard` | PLANNED |
| 6 | `apply` (live FS policy) | PLANNED |
| 7 | `backup` / `restore` | PLANNED |
| 8 | `clean` (GC) | PLANNED |
| 9 | Hardening, shellcheck, docs | PLANNED |

### Known gaps / not implemented (honest list)

- Nothing is implemented yet. No code has been written for HM-Lite at the time of this map.
- `shellcheck` is not installed on the system (root required) → static analysis step pending.
- Upstream SQLite is 3.54.1 but the local CLI is 3.53.4 → SQL must stay within 3.53.4 syntax.
