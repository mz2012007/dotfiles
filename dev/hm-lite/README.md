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
| Generations | An immutable snapshot of all tracked paths of a profile: pending paths are captured fresh, the other tracked paths carry the content of the parent generation forward. Numbers are local to the profile and never reused. |
| Inspection | `hm show` prints the metadata and the complete entry list of one generation, read only and without taking the exclusive lock. Generations are addressed by their profile-local number. |
| Comparison | `hm diff` compares two or more generations, pair by pair, and reports added, removed and changed paths with the reason (content, mode, type, owner, size). Read only, and a difference is not an error. |
| Metadata editing | `hm edit` changes the name and the comment of an existing generation after a preview and a confirmation. The entries and the content store are untouched. |
| Status | `hm status` is a read-only dashboard: the project, the store space (referenced, unreferenced and missing objects) and the profile, size and comment of every generation. |
| Profiles | A profile is an independent namespace for paths, pending paths, generations and selections; the content store is shared. `hm profile create NAME ROOT` creates one with a root directory and its own local generation sequence, `hm profile use NAME` makes it the active context, and the other commands then work inside it without repeating `--profile`. An explicit `--profile` always wins. |
| Deletion | `hm delete` removes a generation after a preview and a confirmation. A generation selected in any profile is never deleted, the content objects it releases are reclaimed by `hm clean`. Numbers are not reused after a deletion. |
| Workspaces | `hm switch` materialises a generation into `current/`, `hm discard` resets `testing/` from it. The live filesystem is never touched. |
| Live writes | `hm apply` writes a generation to the real paths with a preview, a per file backup, a manifest, a verification and an automatic rollback. |
| Backup | `hm backup` creates one consistent archive (database, store, checksum manifest). `hm restore` validates and activates it. |
| Garbage collection | `hm clean` removes the content objects that no generation uses any more. |
| Completion | `completions/` completes the commands, their options, the profile names, the profile-local generation numbers, the tracked paths and the backup archives for Bash, Zsh and Fish. It never runs `hm`, never takes the lock and never changes the state. |
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
hm status                           # store space, profiles, sizes and comments
hm switch 1                         # materialise the generation in current/
hm apply 1                          # write it to the live filesystem
```

A complete tour with the safety features enabled:

```sh
hm add ~/dotfiles                   # register a directory
hm gen --name "dotfiles-2026-10"    # create a named generation
hm list --generation 1              # show what it contains
hm show 1                           # the same generation with the full metadata
hm edit 1 --name "dotfiles-2026-10" # label an existing generation
hm diff 1 2                         # compare two generations
hm apply 1 --dry-run                # preview the live changes
hm apply 1                          # write them, with a backup and a rollback
hm backup                           # create a consistent archive
hm restore ~/.config/hm-lite/backup/hm-backup-20261022T120000Z.tar.gz
hm clean --dry-run                  # show the garbage of the content store
```

A second, independent profile (for example a system update set) shares the
same project and content store without interfering with the dotfiles. Each
profile has a root directory and its own generation sequence, so its first
generation is also number `1`. The profile becomes the active context, so
the commands no longer repeat `--profile`:

```sh
hm profile create update-system /etc     # root /etc, local numbers start at 1
hm add --profile update-system /etc/hosts
hm gen --profile update-system --name "system-v1"
hm profile use update-system             # make it the active context
hm gen                                   # its own pending set and history
hm list                                  # only this profile
hm status                                # its dashboard, including comments
hm switch 1                              # select its local generation 1
hm apply                                 # write that selection

hm list --profile default                # explicit profile wins over the context
HM_PROFILE=default hm list               # per-process context for scripts
```

`hm profile create NAME ROOT` creates a profile with an existing root
directory, `hm profile list` shows every profile with its root and counts,
`hm profile show NAME` prints its root, paths and generations, `hm profile
rename OLD NEW` follows the context, and `hm profile delete NAME` has a
defined deletion policy. The active context is stored in the project
database; `HM_PROFILE` overrides it for one process, which is the safe
choice in scripts.

`hm profile add NAME [PATH…]` remains available for compatibility. It
creates a legacy profile whose root is `/`; new profiles should use
`hm profile create`.

---

## Commands

| Command | Purpose |
|---|---|
| `hm init` | Create the project directory, the configuration and the database. |
| `hm profile create <name> <root>` | Create a profile with a root directory and its own local generation sequence. |
| `hm profile add <name> [path…]` | Create a legacy profile with root `/` and optionally register paths in it. |
| `hm profile list` | List every profile with its root, path, pending and generation counts. |
| `hm profile show [name]` | Show the root, paths and generations of a profile. |
| `hm profile use [name]` | Select the active profile, or print the current context. |
| `hm profile rename <old> <new>` | Rename a profile and update the context and selection keys. |
| `hm profile delete <name>` | Delete a profile after a confirmation; history needs `--force`. |
| `hm add [--profile NAME] <path…>` | Register paths for the next generation of a profile. |
| `hm gen [--profile NAME]` | Capture the pending paths of a profile into a new generation. |
| `hm list [--profile NAME]` | Show the generations, the tracked paths, the pending paths and the store. |
| `hm status [--profile NAME]` | Show the project, the store space and the profile, size and comment of every generation. |
| `hm show [--profile NAME] <generation>` | Show the metadata and the entries of one local generation number. |
| `hm diff [--profile NAME] <generation…>` | Compare two or more local generation numbers, pair by pair. |
| `hm edit [--profile NAME] <generation>` | Change the name and the comment of an existing generation. |
| `hm switch [--profile NAME] <generation>` | Select a local generation number and materialise it into `current/`. |
| `hm delete [--profile NAME] <generation>` | Delete a local generation number that is selected in no profile. |
| `hm apply [generation] [--profile NAME]` | Write a local generation number (or the selection of a profile) to the live filesystem. |
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
cron job. `hm show`, `hm list`, `hm status` and `hm profile list/show` only
read the project and never ask. `hm profile use` is a reversible context
switch and does not prompt either.

### Profile context

The precedence is:

1. an explicit `--profile NAME` on a command that accepts it,
2. `HM_PROFILE` in the process environment,
3. the persisted active profile set by `hm profile use NAME`,
4. the `default` profile.

`HM_PROFILE` is an environment variable, never a configuration key: it must
name an existing profile, an invalid name exits `2` and an unknown name
exits `3`. An explicit `--profile` still wins, even when the environment is
set. `hm add`, `hm gen` and every command that addresses an existing
generation use this effective profile. Generation numbers are resolved
inside that profile, so `hm show 1` and `hm show --profile other 1` can
refer to two different generations. `hm list` and `hm status` without any
context still show every profile; with a context they show only that one.

A generation path must lie inside the profile root. `hm add` rejects an
outside path, `hm gen` refuses to capture one, and `hm apply` reports an
outside entry as `CONFLICT` instead of writing it.

`hm profile create NAME ROOT` is the normal creation command and requires
an existing root directory. `hm profile add NAME` and `hm add --profile
NAME` remain as legacy creation paths; their root is `/`. `HM_PROFILE` and
the active context never create a profile by accident: a typo cannot
silently start writing into a new namespace. `hm profile use` never creates
either.

---

## Shell completion

Optional completion files for Bash, Zsh and Fish live in `completions/`.
They are self contained, they never run `hm` and they never change the
project state: the profile-local generation numbers are read with a single
read-only `sqlite3` query, and a missing or unreadable database simply
means "no dynamic suggestion".

```sh
# Bash
source ~/.local/share/hm-lite/completions/hm.bash

# Zsh, after compinit
source ~/.local/share/hm-lite/completions/hm.zsh

# Fish
source ~/.local/share/hm-lite/completions/hm.fish
```

The commands, the options of every command, the profile names, the
profile-local generation numbers, the tracked paths and the backup archives
are completed. See [docs/completion.md](docs/completion.md) for the
permanent installation of each shell, the exact scope and the verification
notes.

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

`HM_PROFILE` is special: it is an environment-only profile context, not a
configuration key. It never appears in the configuration file and it
overrides the active profile for one process (an explicit `--profile` still
wins). Use it in scripts and cron jobs:

```sh
HM_PROFILE=dotfiles hm gen --name nightly
```

### Colours

Colours are enabled automatically when the stream is a terminal. `HM_COLOR`
overrides the detection: `never` always disables the colours, `always`
enables them even in a pipe and `auto` keeps the detection.

A non-empty `NO_COLOR` environment variable always disables the colours,
even when `HM_COLOR=always` is set, and an empty `NO_COLOR` counts as unset.
The diagnostics follow standard error while the human readable output
follows standard output, so a redirected stream never receives an escape
sequence. Every command colours its own output with the bright palette:
bold bright cyan headings, dim labels and secondary text, bright green
success and additions, bright red removals and conflicts, bright yellow
changes and warnings, bright cyan identifiers and paths, bright magenta
pending paths.

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
| [docs/completion.md](docs/completion.md) | The Bash, Zsh and Fish completion: activation, scope, dynamic suggestions, limits. |
| [docs/safety.md](docs/safety.md) | The safety model, the backups, the rollback and the known limits. |
| [docs/testing.md](docs/testing.md) | The test harness and the test inventory. |

---

## Known limits

* Only regular files and directories are tracked. Symbolic links and
  special files are skipped with a warning and are never followed.
* The recorded metadata is type, mode, uid, gid, mtime and size. ACLs,
  extended attributes, file capabilities and hard links are **not** tracked.
* The size that `hm status` reports for a generation is the size of its
  distinct content objects, not the sum of the entry sizes: content that
  several paths share is counted once.
* The generation history is linear **per profile**: the parent of a new
  generation is always the newest existing generation of the same profile.
  Generation numbers are local to the profile and monotonic; deleting a
  generation leaves a gap and its number is never reused. Deleting a
  generation leaves the parent of its children empty, the remaining
  history stays readable.
* The tracked paths, the pending set, the generations and the selection
  belong to a profile; the content store and `current/`/`testing/` are
  shared by every profile. `hm init` creates the profile `default`.
  `hm profile create NAME ROOT` creates a rooted profile, while
  `hm profile add NAME` and `hm add --profile NAME` create a legacy profile
  with root `/`; the environment context and the active context never
  create a profile.
* A profile root bounds the paths that can be registered, captured and
  applied. `hm add` and `hm gen` reject an outside path; `hm apply` reports
  an outside generation entry as `CONFLICT`.
* The active context is project-global (stored in the `state` table), so it
  is shared by every terminal. Use `HM_PROFILE` in a script when the
  persisted context would be unsafe. The presence of a context can never
  redirect an operation into a different profile silently: `--profile`
  wins, and generation numbers always resolve only inside the effective
  profile.
* The `default` profile cannot be renamed or deleted. The effective
  context and the persisted active profile cannot be deleted either, even
  when `HM_PROFILE` currently points at another profile. A profile with
  generations requires `--force`. The content objects of a deleted profile
  stay in the store until `hm clean`; a path shared with another profile is
  retained, and an orphan path row is removed only when no generation entry
  still references it.
* `hm apply` refuses a destination that is a symbolic link, whose type
  does not match the generation, that is not absolute or that is the root
  of the filesystem. It never writes through a link.
* `hm apply` refuses every destination outside of the profile root as a
  `CONFLICT`, and every destination outside of `$HOME` unless
  `HM_ALLOW_OUTSIDE_HOME=1` is set.
* HM-Lite never escalates privileges. There is no `sudo`, no setuid helper
  and no daemon.
