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
| `core/status.sh` | Read only dashboard: the project, the store space (referenced, unreferenced, missing) and the size of every generation. |
| `core/show.sh` | Read only detail view of one generation: metadata and the rich entry table. |
| `core/diff.sh` | Read only comparison of two or more generations: consecutive pairs, type/content hash/mode/owner/group/size, modification time ignored, never opens the store. |
| `core/edit.sh` | Metadata edit of one generation: exclusive lock, preview, one `UPDATE`; the entries, the parent and the store are untouched. |
| `core/switch.sh` | Select a generation and materialise it into `current/`. Never touches the live filesystem. |
| `core/delete.sh` | Remove one generation and its entries in one transaction; the selected generation is refused. |
| `core/apply.sh` | The live filesystem write path: preview → backup → confirm → write → verify → rollback. |
| `core/discard.sh` | Reset `testing/` from `current/`. Only touches the HM owned workspace. |
| `core/backup.sh` | Consistent backup: `sqlite3 .backup` + store + manifest with checksums. |
| `core/restore.sh` | Validate → stage → verify → activate the restored state. |
| `core/clean.sh` | Garbage collection: exact reference analysis → preview → confirm → delete. |
| `lib/common.sh` | Error and report helpers, `require_cmd`, `confirm`, temporary files, configuration parsing. The exit code constants live in the dispatcher, there is no second definition. |
| `lib/logging.sh` | The levels `ERROR`/`WARN`/`INFO`/`DEBUG`, the append only log file, the colour handling: `HM_COLOR`, `NO_COLOR` and one palette per stream. |
| `lib/paths.sh` | Path normalisation, validation, containment checks, safe joins, the runtime paths. |
| `lib/database.sh` | The `sqlite3` invocation, the SQL quoting, the transaction helper, the schema version, the hex codec. |
| `lib/hashing.sh` | The SHA-256 of a file and of staged bytes. |
| `lib/storage.sh` | The content store: put, get, verify, the prefix layout, the removal. |
| `lib/generations.sh` | The creation of a generation, the materialisation, the listing of the entries. |
| `lib/validation.sh` | The validation of the runtime directory, the database, the schema version and the store. |
| `lib/locking.sh` | The `flock` wrapper for `<runtime>/hm.lock`. |
| `completions/hm.bash` | Bash completion. Self contained builtins only, no `bash-completion` dependency. |
| `completions/hm.zsh` | Zsh completion. Loaded with `source` or autoloaded as `_hm` by `compinit`. |
| `completions/hm.fish` | Fish completion. Loaded with `source` or by the `completions/` directory of Fish. |

The `completions/` directory is a consumer of the command surface, not a
layer of the application: it is never loaded by `hm`, it never writes, it
never takes the lock and it treats a failed database read as "no dynamic
suggestion" instead of an error. The only schema knowledge outside
`db/schema.sql` and `lib/` are two one-line read-only queries
(`generations.id`, `paths.path`), duplicated in the three files on purpose:
the alternative would be a fourth shared library that none of the shells
could source.

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
* **generation** — the immutable snapshot of all tracked paths. The
  entries are immutable; the name and the comment are labels for the
  human reader and can be changed with `hm edit`.

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

### Deleting a generation

`hm delete` removes a history entry, it never touches a live file:

```
preview (metadata, entries, objects, the objects only this generation uses)
   │
   ▼
confirmation  (--yes skips it)
   │
   ▼
one transaction:
  DELETE FROM generation_entries WHERE generation_id = …
  DELETE FROM generations        WHERE id = …
   │
   ▼
the foreign key clears the parent of the children
the unreferenced content objects stay in the store until hm clean
```

Only the database changes. The content objects are shared by design, so
this command never guesses whether an object is still needed: `hm clean`
reclaims it after the exact reference analysis. A failure of either
statement rolls the transaction back and not one row is lost.

The selected generation is refused, because `current/` and an
argument-less `hm apply` must always resolve to a generation that exists.

### Editing the metadata

`hm edit` changes `generations.name` and `generations.comment` with one
`UPDATE` inside a transaction. It takes the exclusive lock even though the
snapshot itself is immutable: the preview, the confirmation and the write
must see one stable row. The selected generation may be edited, because
`current/` and `hm apply` depend on the selection, not on the label.

### Comparing generations

`hm diff` pairs the generations in the given order and compares the
entries by type, content hash, mode, owner, group and size. The
modification time is ignored, for the same reason `hm apply` ignores it: a
copy changes the timestamp without changing the content. The command is
read only, takes the shared lock and never opens the store; it compares
the recorded hashes. A difference is a result, not an error, so the exit
code is `0`.

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
| `add`, `gen`, `apply`, `backup`, `restore`, `clean`, `delete` | exclusive | They change the state. |
| `switch`, `discard` | exclusive | They rewrite an HM owned workspace. |
| `list`, `status`, `show` | shared | They only read. |

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

`NO_COLOR` is not a configuration key, it is an environment convention: a
non-empty value disables the colours even when `HM_COLOR=always` is set,
and an empty value counts as unset. The diagnostics are coloured when
standard error is a terminal, the human readable output when standard
output is, so a redirected stream never receives an escape sequence.
