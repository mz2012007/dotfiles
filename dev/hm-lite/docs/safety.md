# Safety

HM-Lite writes to the real filesystem. The safety model is therefore
explicit, and every dangerous step is guarded by a preview, a backup and
a rollback.

---

## 1. The rules that never bend

| Rule | How it is enforced |
|---|---|
| **No privilege escalation.** | There is no `sudo`, no `su`, no setuid helper and no daemon anywhere in the code. HM-Lite can only write what the invoking user may write. |
| **No blind deletion.** | `rm -rf` is never called on an unchecked path. Every recursive removal goes through `hm_rm_rf_under`, which refuses a target that is not inside an allowed root and refuses the root itself. |
| **No raw path in SQL.** | Every path is quoted with the SQL quoting helper, or stored as the hexadecimal encoding of its bytes. A path with a quote or a newline in it cannot break out of a statement. |
| **No half applied state.** | Every write that belongs together runs inside one transaction. The database is either fully updated or not updated at all. |
| **No surprise changes.** | Every command that changes something shows a preview and asks for a confirmation. `--yes` skips the prompt, `--dry-run` stops before the change. |
| **No silent empty state.** | Every query is checked. A database that cannot be read stops the command with exit code `5`, an unreadable store with exit code `9`. An empty result and a failed query are never confused. |
| **One writer at a time.** | Every mutating command holds an exclusive `flock` on `<runtime>/hm.lock`. A second writer waits, and fails with exit code `8` after `HM_LOCK_TIMEOUT` seconds. |

---

## 2. The live write path

`hm apply` is the only command that writes outside of the runtime
directory.

### Before the write

* **The generation is validated.** A generation that needs a content
  object that is missing from the store is refused with exit code `6`.
  Nothing is written from an incomplete generation.
* **Every destination is classified.** A path is `CREATE`, `UPDATE`,
  `MODE`, `UNCHANGED` or `CONFLICT`.
* **A conflict stops everything.** The command exits with code `3` and the
  filesystem is untouched. The conflicts are:

  | Conflict | Reason |
  |---|---|
  | a symbolic link | HM-Lite never writes through a link and never replaces a link silently. |
  | a type mismatch | A file where the generation holds a directory, or the other way round. |
  | a parent that is not a directory | The path cannot be created. |
  | an unsafe destination | The path is not absolute, or it is the root of the filesystem. |
  | outside of `$HOME` | Unless `HM_ALLOW_OUTSIDE_HOME=1` is set. |

* **The preview is shown** and the confirmation is requested. The prompt
  is closed on standard input, so a command that runs unattended answers
  "no" instead of blocking forever.

### During the write

* Every file that will be overwritten is **copied into the backup
  directory** first. A file that does not exist yet does not need a
  backup.
* A **manifest** of the planned changes is written before the first
  change, so the state of the run is documented even if the process is
  killed.
* The files are written through a **temporary file in the target
  directory** followed by an atomic `rename`. A reader never sees a
  half written file, and a crash never leaves a truncated file behind.
* The modes are applied **at the very end**, after the content. A
  directory that is recorded without write permission would otherwise
  block its own children.

### After the write

* Every written file is **hashed again** and compared with the hash that
  the generation recorded.
* A mismatch triggers the **rollback**: the manifest is read in reverse
  order, the backed up files are restored, the created files are removed
  and the created directories are removed when they are empty. The
  command then fails with exit code `9`.
* The backup directory is printed, so the change can be undone by hand
  later.

---

## 3. The workspaces are safe by construction

`current/` and `testing/` are HM owned directories inside the runtime
directory. They contain **copies**, never hard links and never symbolic
links:

* a hard link would let an edit of the workspace corrupt the content
  store,
* a symbolic link would make the workspace depend on the live filesystem.

`hm switch` builds the tree in a staging directory and renames it into
place, so `current/` is always complete.

`hm discard` only ever touches `<runtime>/testing/`.

`hm delete` never removes a file either: it removes rows. The preview names
the generation and the content objects that no other generation uses, the
confirmation is mandatory unless `--yes` is given, and both `DELETE`
statements share one transaction. The selected generation is refused,
because `current/` and an argument-less `hm apply` must always resolve to a
generation that exists. The content objects themselves are only removed by
`hm clean`, after its exact reference analysis.

---

## 4. The backup is a real backup

`hm backup` does not copy a live database file, it uses the SQLite backup
command, which produces a consistent copy even while the database is
being written. The project lock is held during the whole operation, so
the database and the store in the archive belong to the same state.

The archive contains a checksum manifest, so a damaged archive is
detected before it is activated:

```sh
tar -xzf hm-backup-*.tar.gz -C /tmp/check && cd /tmp/check && sha256sum -c manifest.tsv
```

`hm restore` validates the member names, refuses symbolic links, verifies
every checksum and refuses a database whose schema version it does not
support.

---

## 5. The lock

| Command | Lock |
|---|---|
| `add`, `gen`, `apply`, `backup`, `restore`, `clean`, `delete` | exclusive |
| `switch`, `discard` | exclusive |
| `list`, `status`, `show` | shared |

The lock is a `flock` on `<runtime>/hm.lock`. A command that cannot
acquire it within `HM_LOCK_TIMEOUT` seconds (default `10`) fails with exit
code `8` instead of waiting indefinitely.

---

## 6. The paths that HM-Lite accepts

* A path is normalised **lexically**. `realpath` is not used, because it
  resolves symbolic links and would change the identity of a path.
* A path that contains a space, an apostrophe or a newline is supported
  everywhere: the traversal is NUL delimited and the paths are stored in
  the hexadecimal form.
* Symbolic links and special files are skipped with a warning and are
  never followed, neither during the discovery nor during the write.

---

## 7. Known limits

These are deliberate limits, not bugs:

* **No ACLs, no extended attributes, no file capabilities, no hard links.**
  The recorded metadata is type, mode, uid, gid, mtime and size.
* **Only regular files and directories are tracked.**
* **The generation history is linear.** The parent of a new generation is
  always the newest existing generation.
* **A symbolic link at a destination is a conflict, never a silent
  replacement.** Remove the link by hand and run `hm apply` again.
* **The root of the filesystem is never a destination.** A recorded path
  that is not absolute, or that is `/`, is a conflict.
* **`hm apply` refuses destinations outside of `$HOME`** unless
  `HM_ALLOW_OUTSIDE_HOME=1` is set. The configuration file cannot
  weaken this by accident, because the environment wins over the file.
* **The content store grows until `hm clean` runs.** Nothing is removed
  in the background, a generation is never broken by a background job.
* **`shellcheck` is optional.** The static analysis step of the test suite
  is skipped when the binary is not installed and runs automatically as
  soon as it is available.
