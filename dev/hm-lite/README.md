# HM-Lite

HM-Lite is a small, generation based file and configuration manager.
It registers filesystem paths, stores every unique file content once in a
content addressable store and records historical states as **generations**.
A generation can be materialised in a workspace or written back to the live
filesystem, always with a preview, a backup and a rollback.

The whole system is plain Bash plus the SQLite CLI. There is no daemon, no
compiled component and no runtime dependency beyond a POSIX-ish Linux
userland.

---

## Features

| Capability | How it works |
|---|---|
| Registration | `hm add` records *paths only*. It never hashes, never writes to the store and never creates a generation. |
| Content store | Every file is stored once, addressed by the SHA-256 of its bytes (`store/objects/ab/abcdef…`). |
| Generations | An immutable snapshot of all tracked paths: pending paths are captured fresh, the other tracked paths carry the content of the parent generation forward. |
| Workspaces | `hm switch` materialises a generation into `current/`, `hm discard` resets `testing/` from it. The live filesystem is never touched. |
| Live writes | `hm apply` writes a generation to the real paths with a preview, a per file backup, a manifest, a verification and an automatic rollback. |
| Backup | `hm backup` creates one consistent archive (database, store, checksum manifest). `hm restore` validates and activates it. |
| Garbage collection | `hm clean` removes the content objects that no generation uses any more. |
| Safety | No `sudo`, no blind `rm -rf`, no raw path interpolation into SQL, an exclusive lock for every mutating command, and a confirmation before anything is changed. |

---

## Requirements

* Bash 4.4 or newer (the code uses associative arrays and `printf -v`)
* `sqlite3` 3.53 or newer
* coreutils, `find`, `tar`, `flock` (util-linux)

Verified on Void Linux with Bash 5.3.0, SQLite 3.53.4, coreutils 9.4,
`find` 4.10.0, `tar` 1.35 and `flock` 2.41.4.

---

## Installation

HM-Lite has no build step. Copy the directory somewhere and run the script:

```sh
git clone <repository> ~/.local/share/hm-lite
ln -s ~/.local/share/hm-lite/hm ~/.local/bin/hm
```

The runtime directory is created by the first `hm init`:

```
$HOME/.config/hm-lite/          # HM_DIR, overridable with the environment
```

---

## Quick start

```sh
hm init                              # create the project directory
hm add ~/.bashrc ~/.config/nvim    # register the paths
hm gen                              # capture the content into a generation
hm list                             # show the state
hm switch 1                         # materialise the generation in current/
hm apply 1                          # write it to the live filesystem
```

A complete tour with the safety features enabled:

```sh
hm add ~/dotfiles                   # register a directory
hm gen --name "dotfiles-2026-10"    # create a named generation
hm list --generation 1              # show what it contains
hm apply 1 --dry-run                # preview the live changes
hm apply 1                          # write them, with a backup and a rollback
hm backup                           # create a consistent archive
hm restore ~/.config/hm-lite/backup/hm-backup-20261022T120000Z.tar.gz
hm clean --dry-run                  # show the garbage of the content store
```

---

## Commands

| Command | Purpose |
|---|---|
| `hm init` | Create the project directory, the configuration and the database. |
| `hm add <path…>` | Register paths for the next generation. |
| `hm gen` | Capture the pending paths into a new generation. |
| `hm list` | Show the generations, the tracked paths, the pending paths and the store. |
| `hm switch <generation>` | Select a generation and materialise it into `current/`. |
| `hm apply [generation]` | Write a generation to the live filesystem. |
| `hm discard` | Reset the `testing/` workspace from `current/`. |
| `hm backup` | Create a consistent backup of the project state. |
| `hm restore <archive>` | Restore a backup that was created with `hm backup`. |
| `hm clean` | Remove the content objects that no generation uses any more. |

The detailed reference lives in [docs/commands.md](docs/commands.md).

Every command that changes the project state asks for a confirmation before
it does anything. A declined confirmation ends the command with exit code
`7`, so a script can tell "the user said no" apart from "the command did
its work". `hm backup` is the exception: it only writes a new archive and
never changes the project state, so it never asks and can be run from a
cron job.

---

## Configuration

The configuration file is `<runtime>/config`. It is parsed as **data**,
never sourced, so it cannot execute code. Unknown keys are ignored with a
warning.

| Key | Default | Meaning |
|---|---|---|
| `HM_LOG_LEVEL` | `INFO` | `ERROR`, `WARN`, `INFO` or `DEBUG`. |
| `HM_LOG_FILE` | `1` | Write the operational log to `<runtime>/logs/hm.log`. |
| `HM_COLOR` | `auto` | `auto`, `always` or `never`. |
| `HM_HASH_ALGORITHM` | `sha256` | Only `sha256` is implemented. |
| `HM_STORE_PREFIX_LEN` | `2` | Length of the directory prefix in the store. |
| `HM_LOCK_TIMEOUT` | `10` | Seconds a command waits for the project lock. |
| `HM_ALLOW_OUTSIDE_HOME` | `0` | Let `hm apply` write outside of `$HOME`. |

An environment variable always wins over the configuration file:

```sh
HM_LOG_LEVEL=DEBUG HM_ALLOW_OUTSIDE_HOME=1 hm apply 1
```

---

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success. |
| `1` | Generic runtime failure. |
| `2` | Invalid command line usage. |
| `3` | Validation or precondition failure. |
| `4` | Inconsistent state, for example a source path that vanished. |
| `5` | Database failure. |
| `6` | Content store failure. |
| `7` | The user declined a confirmation. |
| `8` | The project lock could not be acquired. |
| `9` | Filesystem or input/output failure. |

A database that cannot be read stops a command with exit code `5` and an
unreadable content store stops it with exit code `9`. An empty result and
a failed query are never confused with each other, the command always
reports the failure instead of acting on an empty state.

---

## Tests

```sh
./tests/run.sh            # the whole suite
./tests/run.sh 06_apply   # only the suites that match the filter
```

The suite is completely isolated: every test builds its own project in a
temporary directory and the real home directory is never touched.

See [docs/testing.md](docs/testing.md).

---

## Documentation

| Document | Content |
|---|---|
| [docs/architecture.md](docs/architecture.md) | The two roots, the module map, the data flow, the design decisions. |
| [docs/database-schema.md](docs/database-schema.md) | The tables, the relations, the invariants. |
| [docs/commands.md](docs/commands.md) | Every command, its options, its output and its errors. |
| [docs/safety.md](docs/safety.md) | The safety model, the backups, the rollback and the known limits. |
| [docs/testing.md](docs/testing.md) | The test harness and the test inventory. |

---

## Known limits

* Only regular files and directories are tracked. Symbolic links and
  special files are skipped with a warning and are never followed.
* The recorded metadata is type, mode, uid, gid, mtime and size. ACLs,
  extended attributes, file capabilities and hard links are **not** tracked.
* The generation history is linear: the parent of a new generation is
  always the newest existing generation.
* `hm apply` refuses a destination that is a symbolic link, whose type
  does not match the generation, that is not absolute or that is the root
  of the filesystem. It never writes through a link.
* `hm apply` refuses every destination outside of `$HOME` unless
  `HM_ALLOW_OUTSIDE_HOME=1` is set.
* HM-Lite never escalates privileges. There is no `sudo`, no setuid helper
  and no daemon.
