# Architecture

This document explains how HM-Lite is put together: where the state lives,
which module owns which responsibility, and how the data flows from the
filesystem into the database and back.

---

## 1. Two roots

HM-Lite separates the **code** from the **state**. The two are resolved
independently and are never mixed.

| Root | Environment variable | Default | Contents |
|---|---|---|---|
| Runtime | `HM_DIR` | `$HOME/.config/hm-lite` | `db.sqlite`, `store/objects/`, `current/`, `testing/`, `backup/`, `logs/`, `tmp/`, `config`, `hm.lock` |
| Code | `HM_CODE_DIR` | real path of the `hm` script | `hm`, `core/`, `lib/`, `db/schema.sql`, `config`, `tests/`, `docs/` |

The runtime directory holds **every** piece of mutable state. The code
directory is completely immutable at runtime: HM-Lite never writes into
its own installation directory. That separation is what makes the code
directory shareable and the runtime directory backupable.

### The runtime directory

```
$HM_DIR/
├── db.sqlite          the database, the single source of truth for the metadata
├── store/objects/     the content addressable store, ab/abcd… (2 hex prefix)
├── current/           the materialised tree of the selected generation
├── testing/           the scratch workspace, reset with `hm discard`
├── backup/            the archives of `hm backup` and the per file backups of `hm apply`
├── logs/hm.log        the operational log
├── tmp/               the scratch space of the running command
├── config             the configuration file
└── hm.lock            the project lock
```

---

## 2. The layers

```
                  ┌───────────────────────────────────────────┐
  user shell ───► │ hm  (dispatcher)                          │
                  │   resolves the roots, loads the libraries │
                  │   loads the configuration, dispatches     │
                  └───────────────┬───────────────────────────┘
                                  │
              ┌───────────────────┴───────────────────┐
              │                                       │
   ┌──────────▼───────────┐              ┌────────────▼─────────────┐
   │ core/<command>.sh    │              │ lib/*.sh                  │
   │ the behaviour of     │─────────────►│ the reusable primitives   │
   │ one command          │              │ (db, store, hashing, …)   │
   └──────────────────────┘              └───────────────────────────┘
```

**The rule of the layering:** `core/` never implements a primitive twice.
Anything that a second command would need lives in `lib/`. `lib/` never
knows which command calls it and never prompts the user, except
`hm_confirm`, which is deliberately a primitive so that the behaviour
stays testable.

### Module map

| File | Responsibility |
|---|---|
| `hm` | Dispatcher only. Bootstrap aware: `hm init` works with no configuration and no database present. It also owns the exit code constants, so that the dispatcher reports its own bootstrap failures with the same contract as the commands. |
| `config` | Default `KEY=VALUE` configuration template. Parsed as data, never executed. |
| `core/init.sh` | Create the directories, write the configuration, apply `db/schema.sql`, validate the result. Idempotent. |
| `core/add.sh` | Registration only: discovery → dedupe → preview → confirm → one transaction. |
| `core/gen.sh` | Content capture: lock, stage, hash, store, one transaction, clear the pending set. |
| `core/list.sh` | Read only views: generations, entries, tracked paths, pending paths, store statistics. |
| `core/switch.sh` | Select a generation and materialise it into `current/`. Never touches the live filesystem. |
| `core/apply.sh` | The live filesystem write path: preview → backup → confirm → write → verify → rollback. |
| `core/discard.sh` | Reset `testing/` from `current/`. Only touches the HM owned workspace. |
| `core/backup.sh` | Consistent backup: `sqlite3 .backup` + store + manifest with checksums. |
| `core/restore.sh` | Validate → stage → verify → activate the restored state. |
| `core/clean.sh` | Garbage collection: exact reference analysis → preview → confirm → delete. |
| `lib/common.sh` | Error and report helpers, `require_cmd`, `confirm`, temporary files, configuration parsing. The exit code constants live in the dispatcher, there is no second definition. |
| `lib/logging.sh` | The levels `ERROR`/`WARN`/`INFO`/`DEBUG`, the append only log file, the colour handling. |
| `lib/paths.sh` | Path normalisation, validation, containment checks, safe joins, the runtime paths. |
| `lib/database.sh` | The `sqlite3` invocation, the SQL quoting, the transaction helper, the schema version, the hex codec. |
| `lib/hashing.sh` | The SHA-256 of a file and of staged bytes. |
| `lib/storage.sh` | The content store: put, get, verify, the prefix layout, the removal. |
| `lib/generations.sh` | The creation of a generation, the materialisation, the listing of the entries. |
| `lib/validation.sh` | The validation of the runtime directory, the database, the schema version and the store. |
| `lib/locking.sh` | The `flock` wrapper for `<runtime>/hm.lock`. |

### Every query is checked

A result set is never read through a process substitution:

```bash
while IFS= read -r row; do … done < <(hm_db_query "SELECT …")   # wrong
```

Bash discards the exit status of the command inside a process
substitution. A failing query would look exactly like an empty result and
the command would act on a state that does not exist. In `hm clean` that
would have meant: every content object of the store looks unreferenced,
so every object is deleted.

Every read therefore goes through a helper that writes the rows into a
variable of the caller **and** returns the status of the query:

| Helper | Fills with |
|---|---|
| `hm_db_rows SQL VARIABLE` | the rows of an arbitrary statement |
| `hm_gen_entries GENERATION_ID VARIABLE` | the entries of a generation |
| `hm_gen_missing_objects GENERATION_ID VARIABLE` | the objects a generation needs but that are missing |
| `hm_store_object_hashes VARIABLE` | the hashes of the objects in the store |

The caller checks the status and stops with a clear error:

```bash
local rows
if ! hm_db_rows "SELECT …" rows; then
  hm_die "$HM_EX_DB" "Cannot read the referenced content objects, nothing was removed."
fi
```

The single row reads follow the same rule: `hm_db_scalar` is only used when
its status was checked, and the helpers of `lib/generations.sh`
(`hm_gen_selected`, `hm_gen_latest`, `hm_gen_exists`) report a database
failure themselves instead of returning an empty value.

---

## 3. The data flow of a generation

```
hm add <paths>
   │
   │  find -print0 → normalise → deduplicate
   ▼
paths        (the location)                 pending_paths   (the selection)
   │                                            │
   │  hm gen                                    │
   ▼                                            ▼
stage a copy → sha256 → store/objects/… → files (the content)
   │
   ▼
generation_entries (the recorded state: path + content + metadata)
   │
   ▼
generations (the immutable snapshot)
```

The four concepts are four different tables:

* **path** — *where* a thing lives. A path is not a content.
* **content object** — *what* the bytes are. It is identified by the SHA-256
  of its bytes and nothing else.
* **generation entry** — the recorded state of a path inside a generation:
  the content, the mode, the owner, the timestamps.
* **generation** — the immutable snapshot of all tracked paths.

Because the content object is shared, the metadata can never be shared:
the mode of a file belongs to the generation entry, not to the object.

### A generation is a complete snapshot

When `hm gen` runs:

1. Every **pending** path is captured fresh: its content is hashed and
   stored.
2. Every **other tracked path** carries the content of the parent
   generation forward. If the path vanished in the meantime, it is
   dropped from the new generation.
3. The parent of the new generation is the newest existing generation
   (`ORDER BY created_at DESC, id DESC`). The history is linear.

The consequence is simple and predictable: a generation always describes
the complete state of the tracked paths, and two generations can be
compared without any hidden context.

### The transaction boundary

`hm gen` performs the whole capture in one transaction:

* the staged copies are written to `tmp/` and hashed **before** the
  transaction opens,
* the objects are written to the store and verified by reading them back,
* one transaction inserts the `files`, the `generations` and the
  `generation_entries` rows and clears the pending set,
* only after the commit succeeds the pending set is considered gone.

A failure at any point leaves the previous state completely intact: either
the transaction was not committed, or the pending paths are still pending
and the next `hm gen` repeats the work.

---

## 4. The workspaces

```
       hm switch <generation>
                 │
                 ▼
          $HM_DIR/current/          the materialised tree of the generation
                 │
                 │  hm discard
                 ▼
          $HM_DIR/testing/          the scratch workspace
```

`current/` and `testing/` are **copies**, never hard links and never
symbolic links. A hard link would let an edit of the workspace corrupt the
content store, a symbolic link would make the workspace depend on the
live filesystem.

`hm switch` writes into a staging directory first and then renames it into
place, so `current/` is always complete and never half written.

`hm discard` resets `testing/` from `current/`. It only touches the HM
owned workspace and can never reach the live filesystem.

---

## 5. The live write path

`hm apply` is the only command that writes outside of the runtime
directory, so it is the most defensive one:

```
 classify every entry          CREATE | UPDATE | MODE | UNCHANGED | CONFLICT
        │
        ├── a conflict (a symbolic link, a type mismatch, a path outside
        │   of $HOME) → refuse, nothing is changed
        │
        ▼
 preview + confirmation
        │
        ▼
 back up every file that will be overwritten   → $HM_DIR/backup/apply-…/
 write a manifest of the planned changes       → manifest.tsv
        │
        ▼
 write the directories, then the files (temporary file + atomic rename)
        │
        ▼
 verify every written file against the expected hash
        │
        ├── a mismatch → roll back → exit 9
        ▼
 report the backup directory
```

The rollback reads the manifest in reverse order, so a child is always
removed or restored before its parent.

See [safety.md](safety.md) for the full model.

---

## 6. The locking model

| Command | Lock | Reason |
|---|---|---|
| `add`, `gen`, `apply`, `backup`, `restore`, `clean` | exclusive | They change the state. |
| `switch`, `discard` | exclusive | They rewrite an HM owned workspace. |
| `list` | shared | It only reads. |

The lock lives in `<runtime>/hm.lock` and is held with `flock`. A command
that cannot acquire it within `HM_LOCK_TIMEOUT` seconds fails with exit
code `8` instead of waiting forever.

---

## 7. The schema versioning

`db/schema.sql` is the single authoritative definition of the schema. The
shell code never contains a second copy of a `CREATE TABLE` statement, it
only applies the file.

The version is stored in `PRAGMA user_version`. The current version is `1`.

Resolution order of the schema file:

```
$HM_SCHEMA_FILE → <code_dir>/db/schema.sql → <runtime_dir>/db.sqlite's directory
```

A database whose version is newer than the version of the running code is
refused, never migrated silently.

---

## 8. The configuration

The configuration file is parsed as **data**:

```
KEY=VALUE
```

The file is never sourced and never evaluated, so a corrupted or hostile
configuration file cannot execute code. Only the seven documented keys are
recognised, every other key is ignored with a warning.

The precedence is:

```
environment variable  >  configuration file  >  built in default
```

The environment wins because it is the more specific instruction of the
user in that moment. The dispatcher collects the `HM_*` variables of the
process before the libraries load their own defaults, so a value that was
exported is never overwritten by the configuration file.
