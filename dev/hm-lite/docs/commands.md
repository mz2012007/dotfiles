# Command reference

Every command is `hm <command> [options]`.

* Commands that change something ask for a confirmation. `--yes` (`-y`)
  skips the prompt, `--dry-run` shows the preview without changing
  anything. `hm backup` never changes the project state and therefore
  never asks.
* A declined confirmation ends the command with exit code `7`. A script
  can therefore tell "the user said no" apart from "the command did its
  work".
* Colours are enabled automatically on a terminal and disabled on a pipe.
  `HM_COLOR` and `NO_COLOR` override the detection, see
  [Configuration](../README.md#colours). The human readable output of every
  command uses the standard output palette; the diagnostics use the
  standard error palette.
* A difference is not an error: `hm diff` always ends with exit code `0`,
  also when the compared generations differ. Exit code `1` stays reserved
  for a generic runtime failure.
* The exit codes are documented in the [README](../README.md#exit-codes).
* All commands require an initialised project (`hm init`) except `init`
  itself.
* A **profile** is an independent namespace: the tracked paths, the pending
  set, the generations and the selection belong to a profile, the content
  store is shared. `hm init` creates the profile `default`.
  `hm profile add NAME` and `hm add --profile NAME` create a missing
  profile; every other profile operation requires an existing one.
* The **profile context** is resolved in this order: an explicit
  `--profile NAME`, then `HM_PROFILE`, then the persisted active profile
  set by `hm profile use NAME`, then the default profile for `add`/`gen`.
  `list` and `status` show every profile when no context is present, and
  only the context profile when one is. `show`, `diff`, `edit`, `switch`,
  `delete` and an argument-less `apply` use the context as an ownership
  check; without a context they keep the legacy unscoped behaviour.
* `HM_PROFILE` is a process environment variable, not a configuration key.
  It must name an existing profile. An invalid name is a usage error (`2`)
  and an unknown name is a validation error (`3`); an explicit `--profile`
  still wins over an invalid environment value.
* A profile name starts with a letter or a digit and continues with
  letters, digits, dots, underscores or hyphens
  (`[A-Za-z0-9][A-Za-z0-9._-]*`). An invalid name is a usage error (`2`),
  an unknown profile is a validation error (`3`).

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

## `hm profile <subcommand>`

Manage the profiles and the active context. The command is a namespace for
the management subcommands; the operations on generations keep their own
commands and accept `--profile`.

```
Usage: hm profile <subcommand> [arguments...]

Subcommands:
  profile add <name> [path...]  Create a profile and optionally register paths
  profile list                  List the profiles and their counts
  profile show [name]           Show the paths and generations of a profile
  profile use [name]            Select the active profile, or print it
  profile rename <old> <new>    Rename a profile and its context
  profile delete <name>         Delete a profile after a confirmation
```

`profile add` validates the name, takes the exclusive lock and creates the
row. With paths it reuses the `hm add` registration pipeline, registers
them in the usual single transaction and prints the same preview. A failed
or declined registration removes the still empty profile again. `profile
add` without paths asks for a confirmation; `hm add --profile NAME` is the
shortcut that creates and registers in one command.

`profile list` is read only. It prints every profile with its path, pending
and generation counts and the marker of the effective context. `profile
show` is read only too: without a name it shows the effective context
(`HM_PROFILE`, then the persisted active profile, then `default`), with a
name it shows that profile regardless of the environment. Neither command
prompts.

`profile use NAME` stores the active profile in the `state` table under
`active_profile` and takes the exclusive lock. It does not create a
missing profile, and it does not prompt: switching the context is
reversible. Without a name it prints the persisted active profile and, when
`HM_PROFILE` is set, the effective environment context. The context is
project-global, so every terminal sees the same persisted value; use
`HM_PROFILE` for a script that needs a private context.

`profile rename OLD NEW` updates the profile row, the
`selected_generation:OLD` state key and the persisted `active_profile` in
one transaction. The profile id, the paths, the generations and the
selection therefore follow the new name. The default profile cannot be
renamed. `--yes`/`-y` skips the confirmation.

`profile delete NAME` has a deliberately conservative policy:

* the `default` profile cannot be deleted;
* the effective context and the persisted active profile are protected,
  even when `HM_PROFILE` currently points at another profile; select
  another profile first;
* a profile with generations requires `--force`; without it the command
  stops with exit code `3`;
* the deletion removes the profile's selections (including a global
  selection that points into it), pending rows, generation rows and path
  memberships in one transaction;
* a path that another profile still tracks is retained, and an orphan path
  row is removed only when no generation entry still references it;
* content objects stay in the shared store until `hm clean` reclaims them.

`--yes`/`-y` skips the confirmation and a declined prompt exits `7`.
Unknown or invalid names follow the common profile errors (`3`/`2`).
`profile list`, `profile show` and `profile use` without a name never
prompt; they are read-only or a reversible context switch.

---

## `hm add [--profile NAME] <file|directory…>`

Register paths for the next generation.

```
Usage: hm add [--profile NAME] <file|directory...>
```

`add` is a **registration only** command. It does not hash a file, does not
write to the content store, does not create a generation and never changes
the file that was registered. The target profile is the effective context
(`--profile`, `HM_PROFILE` or the persisted active profile) and falls back
to `default`. An explicit `--profile` creates a missing profile on the
spot; an environment or active context must already exist, so a typo cannot
create a namespace by accident. A missing context therefore never writes
into another profile.

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
Paths selected for registration (profile: default):

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

Capture the pending paths of a profile into a new generation.

```
Usage: hm gen [options]

Options:
  --profile NAME     Profile of the generation (default: the context)
  --name NAME        Give the generation a name
  --comment TEXT     Attach a comment to the generation
  --yes, -y          Do not ask for a confirmation
```

What it does:

1. Take the **exclusive** project lock.
2. Read the pending set of the effective profile (`--profile`, then
   `HM_PROFILE`, then the active profile, then `default`). The generation is
   attached to that profile; the other profiles are not touched. The
   profile must already exist: only `add`/`profile add` create one.
3. For every pending path that no longer exists the command **fails hard**
   with exit code `4`. The remedy is to run `hm add` again, which prunes
   the paths that vanished.
4. Stage a copy of every pending file in `tmp/`, hash it with SHA-256 and
   store the unique contents in the content store. A stored object is read
   back and verified.
5. Carry the other tracked paths of the profile forward from its parent
   generation and drop the ones that vanished.
6. Insert the `files`, `generations` and `generation_entries` rows in one
   transaction and clear the pending set of the profile in the same
   transaction.

```
Generation preview (profile: default):

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
  --profile NAME    Show a single profile (default: the context, else every profile)
  --generation ID   Show the entries of a single generation
  --pending         Show the paths that are queued for the next generation
  --paths           Show the tracked paths
  --store           Show the statistics of the content store
```

Without an option and without a profile context the overview of all
generations is shown, with the profile of every generation. With
`HM_PROFILE` or a persisted active profile, `list` narrows itself to that
profile, exactly as if `--profile` had been given; an explicit `--profile`
always wins.

```
ID     PROFILE          CREATED                ENTRIES  OBJECTS  NAME
1      default          2026-10-22T14:01:44Z         1        1  (unnamed)
```

With `--profile NAME` only the generations, the pending paths and the
tracked paths of that profile are shown, and the `PROFILE` column and the
`Profile:` line are still printed for clarity. The generation ids stay
global across the profiles: a generation belongs to exactly one profile.

The generations are ordered by `created_at DESC, id DESC`.

`hm list --store` is the raw view of the content store. The richer
dashboard is [`hm status`](#hm-status).

---

## `hm status`

Show a read-only dashboard of the project: the project itself, the content
store and the generations with their profiles, sizes and comments. The
command only takes the shared lock and changes nothing.

```
Usage: hm status [options]

Options:
  --profile NAME  Show a single profile (default: the context, else every profile)
  -h, --help      Show this help
```

Without `--profile`, an `HM_PROFILE` or persisted active context narrows
the dashboard to that profile. With no context at all, every profile is
shown and the project-wide selection is used for the `SEL` marker.

```
HM-Lite status

  Project:         /home/user/.config/hm-lite
  Profile:         all
  Generations:     3
  Selected:        2
  Tracked paths:   3
  Pending paths:   0

Store

  Location:        /home/user/.config/hm-lite/store/objects
  Objects:         2
  Size:            6 B (6 bytes)
  Referenced:      2 object(s), 6 B (6 bytes)
  Unreferenced:    0 object(s), 0 B (0 bytes)
  Missing:         0 object(s), 0 B (0 bytes)

Generations

ID     SEL PROFILE          CREATED                ENTRIES  OBJECTS       SIZE  NAME                  COMMENT
3           default          2026-10-22T16:13:02Z         3        2        6 B  third
2      *    default          2026-10-22T16:13:02Z         2        1        2 B  second                the working configuration
1           default          2026-10-22T16:13:02Z         1        1        2 B  first
```

* `PROFILE` names the profile that owns the generation and `COMMENT` prints
  the comment set with `hm gen --comment` or `hm edit --comment` (empty
  when the generation has none).
* `SEL` marks the selection of the shown scope: the global selection (the
  last `hm switch`) when every profile is shown, and the selection of the
  context profile (`--profile`, `HM_PROFILE` or the active profile).
* `Selected:` follows the same scope: the global selection, or the
  selection of the named profile.
* With a profile context (`--profile NAME`, `HM_PROFILE` or the active
  profile) the dashboard is restricted to that profile: only its
  generations, tracked paths and pending paths are counted and listed, and
  `Profile:` names the profile instead of `all`.
* The size of a generation is the summed size of the **distinct** content
  objects it references. Content that several paths or several generations
  share is counted once, therefore the generation sizes never add up to
  more than the store holds.
* The store is classified in one pass:
  * `Referenced` — the object is present and used by at least one
    generation,
  * `Unreferenced` — the object is present but no generation uses it; this
    is the garbage that `hm clean` removes,
  * `Missing` — a generation needs the object but the store does not have
    it.
* A damaged store does not fail the command: it is reported in the
  `Missing:` line and with a warning, and nothing is repaired.
* The sizes are human readable (`B`, `KiB`, `MiB`, …) with one decimal
  place. The exact byte count of the store is printed next to the formatted
  value.
* Colours follow the same rules as every other command: they are enabled on
  a terminal and disabled on a pipe, `HM_COLOR` and `NO_COLOR` override the
  detection. The headings are bold bright cyan, the labels are dim, the
  selected generation is bright cyan, unreferenced objects are bright
  yellow and missing objects are bright red.

---

## `hm show [--profile NAME] <generation>`

Show the metadata and the complete entry list of one generation. The
command is read only and only takes the shared lock.

```
Usage: hm show [--profile NAME] <generation>

Options:
  --profile NAME Profile owning the generation
  -h, --help     Show this help
```

The metadata block names the generation, its profile, whether that profile
selected it, how many entries and content objects it holds and how many
bytes the files occupy:

```
Generation 2

  Name:       dotfiles-2026-10
  Comment:    the working configuration
  Profile:    default
  Created:    2026-10-22T14:01:44Z
  Parent:     1
  Selected:   no
  Entries:    4
  Objects:    2
  Size:       8 bytes

PATH                                     TYPE  MODE  OWNER           SIZE  MODIFIED            HASH
/home/user/.bashrc                       file  644   1000:1000         12  2026-10-22T14:00:00Z 4e07408562be
```

* The entry table is the detailed variant of `hm list --generation`: it
  adds the owner, the group and the modification time, and it always
  shows the full path.
* A content object that is missing from the store is reported on a
  `Missing:` line and as a warning. The command still succeeds: it never
  hides a damaged store behind a repair, and it never modifies anything.
* An unknown generation is a state error (`4`), a missing or extra
  argument is a usage error (`2`).
* With `--profile`, `HM_PROFILE` or an active profile, the generation must
  belong to that profile; a generation owned by another profile is refused
  with exit code `3` before anything is printed. Without any context the
  command keeps the legacy unscoped behaviour.

---

## `hm diff [--profile NAME] <generation> <generation> [<generation>…]`

Compare the entries of two or more generations. The generations are
compared in the order in which they are given, every consecutive pair is
one comparison. The command is read only and only takes the shared lock.

```
Usage: hm diff [--profile NAME] <generation> <generation> [<generation>...]

Options:
  --profile NAME Profile owning the generations
  --all          Show the entries that did not change
  -h, --help     Show this help
```

```
HM-Lite diff

Generation 1 -> 2

  ~ /home/user/.bashrc (content, mode 600 -> 644)
  + /home/user/.config/nvim/init.lua
  - /home/user/.config/old.conf

  1 added, 1 removed, 1 changed, 2 unchanged
```

* The marker and the colour name the kind of change: `+` green added,
  `-` red removed, `~` yellow changed, `=` unchanged. The unchanged
  entries are hidden unless `--all` is given.
* An entry is compared by its type, its content hash, its mode, its owner
  and its group. The modification time is recorded metadata but it is not
  a difference: `hm apply` ignores it as well, and copying a file updates
  it without changing the content. A size difference is only reported
  when the content hash did not change.
* The comparison uses the recorded hashes and never opens the content
  store. A missing content object therefore does not change the result of
  a comparison; `hm show`, `hm status` and `hm clean` report it.
* The summary counts every path of the pair, including the paths that did
  not change. When a pair has no difference at all the line
  `No differences.` is printed.
* The generations must be distinct. A duplicate, an unknown generation
  and a generation that is not a positive integer are rejected before
  anything is printed.
* With `--profile`, `HM_PROFILE` or an active profile, every generation
  must belong to that profile; otherwise the command exits `3`. Without a
  context it keeps the legacy unscoped behaviour.
* A difference is a normal result: the command always ends with exit code
  `0`. A database failure stops it with exit code `5`, an unknown
  generation is a state error (`4`), and a usage error is `2`.

---

## `hm edit [--profile NAME] <generation> [options]`

Change the name and the comment of an existing generation.

```
Usage: hm edit [--profile NAME] <generation> [options]

Options:
  --profile NAME     Profile owning the generation
  --name NAME        Set the name of the generation
  --comment TEXT     Set the comment of the generation
  --clear-name       Remove the name of the generation
  --clear-comment    Remove the comment of the generation
  --yes, -y          Do not ask for a confirmation
  -h, --help         Show this help
```

```
Edit preview for generation 2

  Generation: 2
  Name:       old label -> new label
  Comment:    - -> the working configuration

Apply the change? [y/N]
```

* At least one of `--name`, `--comment`, `--clear-name` and
  `--clear-comment` is required. `--name` and `--clear-name` cannot be
  combined, neither can `--comment` and `--clear-comment`.
* An empty value is rejected with exit code `2`; removing a value has an
  explicit flag. This keeps `--name ""` from wiping a label by accident.
* Only the metadata of the generation changes. The entries, the content
  objects, the parent and the selection are untouched: a generation is
  immutable as a snapshot, the name and the comment are labels for the
  human reader.
* The command takes the **exclusive** lock and performs a single `UPDATE`
  in one transaction. The selected generation may be edited; `hm delete`
  is the command that refuses it.
* An unknown generation is a state error (`4`), a declined confirmation
  ends the command with exit code `7`, and a database failure stops it
  with exit code `5` without changing anything.
* With `--profile`, `HM_PROFILE` or an active profile, the generation must
  belong to that profile; otherwise the command exits `3`. Without a
  context it keeps the legacy unscoped behaviour.

---

## `hm switch [--profile NAME] <generation>`

Select a generation and materialise it into `<runtime>/current`.

```
Usage: hm switch [--profile NAME] <generation>

Options:
  --profile NAME Profile owning the generation
  -h, --help     Show this help
```

* The generation and every content object it needs are validated first.
* The tree is built in a staging directory and then renamed into place,
  so `current/` is never half written.
* The live filesystem is **not** touched. `current/` is a copy, never a
  hard link and never a symbolic link.
* The selected generation is recorded in the `state` table twice: under
  `selected_generation:<profile>` for the profile that owns the generation
  and under the global `selected_generation` (the last selection of any
  profile). `hm apply` uses the active context, the global selection or,
  with `--profile`, the selection of that profile. Two profiles can
  therefore keep two different selections.
* With `--profile`, `HM_PROFILE` or an active profile, the generation must
  belong to that profile (`3` on a mismatch). Without a context the
  command keeps the legacy unscoped behaviour.

---

## `hm delete [--profile NAME] <generation>`

Delete a generation and its entries.

```
Usage: hm delete [--profile NAME] <generation> [options]

Options:
  --profile NAME Profile owning the generation
  --yes, -y      Do not ask for a confirmation
  -h, --help     Show this help
```

The command prints a preview first: the metadata of the generation, the
number of entries and objects, and how many content objects only this
generation uses. Only then it asks.

```
Delete preview:

  Generation: 3
  Name:       (unnamed)
  Created:    2026-10-22T14:05:12Z
  Entries:    4
  Objects:    2

  1 content object(s) are used by no other generation.
  They stay in the store until "hm clean" runs.

Delete the generation? [y/N]
```

* **A selected generation is never deleted.** The command refuses it
  with exit code `3` when **any** profile (or the global selection) points
  to the generation, because `current/` and a later `hm apply` without an
  argument would otherwise point to a generation that no longer exists.
  `hm switch` must select another generation in that profile first.
* The removal runs in **one transaction**: the entries are deleted first,
  then the generation row. A failure rolls everything back and the project
  is unchanged. An unknown generation ends the command with exit code `4`
  before anything is written.
* The parent of the child generations becomes empty: the schema uses
  `ON DELETE SET NULL`, so the remaining history stays readable. The
  remaining generation is otherwise untouched.
* The content objects and the `files` rows that no generation uses any
  more are **not** deleted here. `hm clean` reclaims them, and both the
  preview and the success message name how many objects are affected.
* A declined confirmation ends the command with exit code `7` and a
  message on standard error.
* With `--profile`, `HM_PROFILE` or an active profile, the generation must
  belong to that profile (`3` on a mismatch). Without a context the
  command keeps the legacy unscoped behaviour. The selected-generation
  guard is independent of the context and always checks every profile.

---

## `hm apply [generation] [--profile NAME]`

Write a generation to the live filesystem.

```
Usage: hm apply [generation] [options]

Options:
  --profile NAME Profile whose selection is applied
  --dry-run      Show the preview only, change nothing
  --yes, -y      Do not ask for a confirmation
```

Without an argument the selected generation of the effective context is
applied (`--profile`, then `HM_PROFILE`, then the active profile, then the
global selection when no context is set). With `--profile NAME` and
without an argument the selection of that profile is applied; a named
generation must belong to the profile, otherwise the command refuses it
with exit code `3`. A `--profile` name must already exist.

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
  -h, --help     Show this help
```

The backup never changes the project state, therefore it does not ask for a
confirmation and it can be run from a cron job.

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

Every query of the analysis is checked. A database that cannot be read
stops the command with exit code `5` and an unreadable store stops it
with exit code `9`, **before** a single object is removed. An empty
result and a failed query are never confused with each other.

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
and the code directory. `HM_PROFILE` selects the profile context for the
current process (after an explicit `--profile`, before the persisted
active profile); it must name an existing profile and is never read from
the configuration file.
