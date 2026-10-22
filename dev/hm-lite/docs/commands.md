# Command reference

Every command is `hm <command> [options]`.

* Commands that change something ask for a confirmation. `--yes` (`-y`)
  skips the prompt, `--dry-run` shows the preview without changing
  anything.
* The exit codes are documented in the [README](../README.md#exit-codes).
* All commands require an initialised project (`hm init`) except `init`
  itself.

---

## `hm init`

Create the project directory, the configuration file and the database.

```
Usage: hm init
```

* The command is idempotent: running it on an existing project reports the
  existing state and changes nothing.
* The schema is applied from `db/schema.sql`, the single authoritative
  definition.
* After the initialisation the directories, the database and the store are
  validated.

---

## `hm add <file|directory…>`

Register paths for the next generation.

```
Usage: hm add <file|directory...>
```

`add` is a **registration only** command. It does not hash a file, does not
write to the content store, does not create a generation and never changes
the file that was registered.

What it does:

1. Expand every argument. A directory is expanded into its regular files
   and its subdirectories. Symbolic links and special files are **skipped
   with a warning** and are never followed.
2. Normalise every path lexically (no `realpath`, so a symbolic link in
   the path cannot change the identity of the path) and deduplicate it.
3. Show a preview that classifies every path:
   `NEW`, `TRACKED`, `PENDING` or `REMOVED`.
4. Ask for a confirmation.
5. Write everything in a single transaction.

```
Paths selected for registration:

  [NEW]      /home/user/.bashrc

1 paths discovered
1 new paths
0 paths queued again
0 paths already pending
0 paths removed from the pending set

Continue? [y/N]
```

A path that was registered before and is queued again is moved back into
the pending set. A path that was registered before and vanished from the
filesystem is removed from the tracked set.

---

## `hm gen [options]`

Capture the pending paths into a new generation.

```
Usage: hm gen [options]

Options:
  --name NAME        Give the generation a name
  --comment TEXT     Attach a comment to the generation
  --yes, -y          Do not ask for a confirmation
```

What it does:

1. Take the **exclusive** project lock.
2. Read the pending set.
3. For every pending path that no longer exists the command **fails hard**
   with exit code `4`. The remedy is to run `hm add` again, which prunes
   the paths that vanished.
4. Stage a copy of every pending file in `tmp/`, hash it with SHA-256 and
   store the unique contents in the content store. A stored object is read
   back and verified.
5. Carry the other tracked paths forward from the parent generation and
   drop the ones that vanished.
6. Insert the `files`, `generations` and `generation_entries` rows in one
   transaction and clear the pending set in the same transaction.

```
Generation preview:

  1 path(s) captured
  1 new content object(s)
  0 content object(s) reused
  0 path(s) carried forward
  0 path(s) dropped, they no longer exist

Captured paths:
  /home/user/.bashrc

Create the generation? [y/N]
```

---

## `hm list [options]`

Show the state of the project. The command is read only.

```
Usage: hm list [options]

Options:
  --generation ID   Show the entries of a single generation
  --pending         Show the paths that are queued for the next generation
  --paths           Show the tracked paths
  --store           Show the statistics of the content store
```

Without an option the overview of all generations is shown:

```
ID     CREATED                ENTRIES  OBJECTS  NAME
1      2026-10-22T14:01:44Z         1        1  (unnamed)
```

The generations are ordered by `created_at DESC, id DESC`.

---

## `hm switch <generation>`

Select a generation and materialise it into `<runtime>/current`.

```
Usage: hm switch <generation>
```

* The generation and every content object it needs are validated first.
* The tree is built in a staging directory and then renamed into place,
  so `current/` is never half written.
* The live filesystem is **not** touched. `current/` is a copy, never a
  hard link and never a symbolic link.
* The selected generation is recorded in the `state` table and is used by
  `hm apply` when no generation is named.

---

## `hm apply [generation]`

Write a generation to the live filesystem.

```
Usage: hm apply [generation] [options]

Options:
  --dry-run      Show the preview only, change nothing
  --yes, -y      Do not ask for a confirmation
```

Without an argument the selected generation (the one `hm switch`
selected) is applied.

Every entry of the generation is classified:

| Action | Meaning |
|---|---|
| `CREATE` | The path does not exist yet. |
| `UPDATE` | The path exists with a different content. |
| `MODE` | The content is correct but the permissions differ. |
| `UNCHANGED` | The path is already exactly as recorded. |
| `CONFLICT` | The path cannot be written safely. |

A conflict stops the command with exit code `3` and **nothing is
changed**. A conflict is:

* the path is a symbolic link,
* a file exists where the generation holds a directory, or the other way
  round,
* the parent of the path is not a directory,
* the path is not absolute or it is the root of the filesystem,
* the path is outside of `$HOME` and `HM_ALLOW_OUTSIDE_HOME` is not `1`.

The write itself:

1. every file that will be overwritten is copied into
   `<runtime>/backup/apply-<timestamp>-<pid>/files/`,
2. a manifest of the planned changes is written next to it,
3. the directories are created first, then the files, each one through a
   temporary file and an atomic rename,
4. the recorded modes are applied at the very end, so a directory without
   write permission cannot block its own children,
5. every written file is hashed again and compared with the expected hash,
6. a mismatch rolls the whole operation back and fails with exit code `9`.

The backup directory is printed at the end. It stays on disk, so a change
can be undone by hand.

---

## `hm discard`

Reset the `testing/` workspace from `current/`.

```
Usage: hm discard
```

The command only touches the HM owned workspace `<runtime>/testing/`. The
live filesystem is never affected.

---

## `hm backup`

Create a consistent backup of the project state.

```
Usage: hm backup [options]

Options:
  --yes, -y      Do not ask for a confirmation
```

The archive is a single compressed file in `<runtime>/backup/`:

```
hm-backup-20261022T140215Z.tar.gz
├── db.sqlite      a consistent copy of the database (sqlite .backup)
├── store/         the content store
├── manifest.tsv   the SHA-256 checksum of every archived file
└── meta.txt       the version, the creation time and the counters
```

The manifest uses the format of `sha256sum`, so the integrity of an
archive can be checked with:

```sh
tar -xzf hm-backup-*.tar.gz -C /tmp/check && cd /tmp/check && sha256sum -c manifest.tsv
```

The database is copied with the SQLite backup command while the project
lock is held, therefore the copy is consistent with the store.

---

## `hm restore <archive>`

Restore a backup that was created with `hm backup`.

```
Usage: hm restore <backup> [options]

Options:
  --yes, -y      Do not ask for a confirmation
```

The archive is validated **before** anything is changed:

1. every member name must be relative and must not escape the archive,
2. the extracted tree must not contain a symbolic link,
3. every file must match the checksum of the manifest,
4. the schema version of the restored database must be the supported one.

Only then the current state is replaced: the current database and the
current store are moved aside first, so a failure restores them. The
`current/` and `testing/` workspaces are cleared, because they belong to
the state that was replaced.

---

## `hm clean`

Remove the content objects that no generation uses any more.

```
Usage: hm clean [options]

Options:
  --dry-run      Show what would be removed, change nothing
  --yes, -y      Do not ask for a confirmation
```

The reference analysis is exact:

* an object is removed when **no** generation entry points at it,
* the database rows of the unreferenced contents are removed with it,
* an object that a generation needs but that is missing from the store is
  reported as `MISSING` and is never touched, because it is the symptom
  of a damaged project.

```
Clean preview:

  1 unreferenced object(s) in the store
  1 unreferenced row(s) in the database
  0 missing object(s) that a generation needs

  REMOVE  5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03

Remove the unreferenced content objects? [y/N]
```

---

## Global options

```
hm --help        show the overview of the commands
hm --version     show the version of HM-Lite
hm <command> --help
```

The environment variables `HM_DIR` and `HM_CODE_DIR` select the runtime
and the code directory.
