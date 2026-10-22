# Shell completion

HM-Lite ships an optional completion file for Bash, Zsh and Fish. The
completion is a convenience layer: it is not loaded by the `hm` script, it
is not needed by any command and it can be removed at any time.

```
completions/hm.bash     # Bash
completions/hm.zsh      # Zsh
completions/hm.fish     # Fish
```

The three files are self contained. They share the same tables and the
same rules, there is no shared library and no generated code between them.

---

## Activation

### Bash

```sh
source ~/.local/share/hm-lite/completions/hm.bash
```

To load it in every interactive shell, copy it to a directory that Bash
already sources:

```sh
install -Dm644 completions/hm.bash \
  ~/.local/share/bash-completion/completions/hm
```

That directory is loaded by the `bash-completion` package. The file itself
does **not** depend on that package: it only uses Bash builtins
(`compgen`, `mapfile`, `compopt`), so the `source` route above works on a
plain Bash too.

### Zsh

The Zsh completion system must be initialized first. Either source the file
after `compinit`:

```zsh
autoload -Uz compinit && compinit
source ~/.local/share/hm-lite/completions/hm.zsh
```

or install it under the name `_hm` in a directory of `$fpath` and let
`compinit` autoload it:

```zsh
install -Dm644 completions/hm.zsh ~/.zsh/completions/_hm
```

```zsh
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

The file name matters for the second route: `compinit` only autoloads
files whose name starts with an underscore. The header line `#compdef hm`
registers the file for the `hm` command.

### Fish

```sh
source ~/.local/share/hm-lite/completions/hm.fish
```

or copy it into the Fish completion directory, where it is loaded
automatically:

```sh
install -Dm644 completions/hm.fish ~/.config/fish/completions/hm.fish
```

---

## What is completed

The completion mirrors the real command line. It never offers a command
that `hm` does not have, and it never offers an option outside the command
that supports it.

| Command | Options | Argument |
|---|---|---|
| `hm init` | `-h`, `--help` | — |
| `hm add` | `-h`, `--help` | one or more paths |
| `hm gen` | `--name`, `--comment`, `--yes`, `-y`, `-h`, `--help` | — |
| `hm list` | `--generation`, `--pending`, `--paths`, `--store`, `-h`, `--help` | — |
| `hm status` | `-h`, `--help` | — |
| `hm show` | `-h`, `--help` | exactly one generation id |
| `hm switch` | `-h`, `--help` | exactly one generation id |
| `hm delete` | `--yes`, `-y`, `-h`, `--help` | exactly one generation id |
| `hm apply` | `--dry-run`, `--yes`, `-y`, `-h`, `--help` | one optional generation id |
| `hm discard` | `-h`, `--help` | — |
| `hm backup` | `-h`, `--help` | — |
| `hm restore` | `--yes`, `-y`, `-h`, `--help` | exactly one backup archive |
| `hm clean` | `--dry-run`, `--yes`, `-y`, `-h`, `--help` | — |

At the command position the completion offers the thirteen commands, `help`,
`-h`, `--help` and `--version`.

The argument is only completed while it is still valid:

* `hm switch <TAB>` offers the generation ids, `hm switch 1 <TAB>` offers
  nothing.
* `hm show <TAB>` and `hm delete <TAB>` offer the generation ids,
  `hm show 1 <TAB>` and `hm delete 1 <TAB>` offer nothing.
* `hm apply <TAB>` offers the generation ids, `hm apply 1 <TAB>` offers
  nothing.
* `hm init <TAB>`, `hm gen <TAB>`, `hm status <TAB>`, `hm backup <TAB>` and
  the other commands without an argument offer nothing.
* `hm gen --name <TAB>` offers nothing: `--name` and `--comment` are free
  text.

`hm add <TAB>` offers the paths of the filesystem **and** the paths that
the project already tracks. `hm restore <TAB>` offers the archives of
`<runtime>/backup/` **and** the files of the filesystem.

The inline form of the value options is completed as well:
`hm list --generation=<TAB>` offers `--generation=1`, `--generation=2`, …

---

## The dynamic part

The generation ids come from the project database. The runtime directory is
resolved exactly like the `hm` script does it:

```
${HM_DB_FILE:-${HM_DIR:-$HOME/.config/hm-lite}}/db.sqlite
```

The completion opens the database **read only** and runs a single query:

```sql
SELECT id FROM generations ORDER BY created_at DESC, id DESC;
```

The same order as `hm list`: newest generation first. The tracked paths are
read with `SELECT path FROM paths ORDER BY path;`.

This has four consequences, and they are the design:

1. **The completion never changes the state of a project.** `sqlite3
   -readonly` cannot create, update or delete a row, and it cannot create
   the file when it does not exist. Completion must be free of side
   effects: a `<TAB>` is not a command.
2. **The completion never takes the project lock.** It does not run `hm`,
   so it never waits for `flock`. A `hm gen` that holds the lock cannot
   freeze an interactive shell.
3. **The completion is cheap.** One read-only process per `<TAB>` at the
   positions that need an id. `hm list` is deliberately *not* used: it runs
   three queries, one of them `PRAGMA integrity_check`, and it takes the
   shared lock.
4. **A failure is not an error.** A missing, unreadable or damaged database
   produces no suggestion and no message. The shell keeps working. Nothing
   is created as a side effect of a failed read.

The completion does not read the configuration file. It uses the
environment and the same defaults as the dispatcher, which is enough for
the two values it needs (`HM_DIR`, `HM_DB_FILE`).

---

## Requirements

| Shell | Requirement |
|---|---|
| Bash | Bash 4.4 or newer, `sqlite3` for the dynamic part |
| Zsh | Zsh 5.x with `compinit`, `sqlite3` for the dynamic part |
| Fish | Fish 3.0 or newer, `sqlite3` for the dynamic part |

Without `sqlite3` the completion still works: it simply offers fewer
suggestions (the commands, the options and the filesystem paths).

---

## Verification status

| Shell | How it was verified |
|---|---|
| Bash | `bash -n`, ShellCheck, the behavioural tests of `tests/cases/09_completion.sh`, and a real interactive pseudo terminal: completing `dir` inserts `dir\ with\ space`, completing `b` inside an escaped path inserts `b\'q.txt`, a quoted prefix is closed and reopened correctly. |
| Fish | `fish -n` and `complete -C`, both in `tests/cases/09_completion.sh`. |
| Zsh | `zsh -n`, registration under `compinit` (`_comps[hm]=_hm`), a behavioural harness with stubbed completion primitives, and a real interactive pseudo terminal. The manual test was run in a Debian container with Zsh 5.9 because Zsh is not installed on the development host. |

The test suite runs the Bash tests directly and the Fish tests through
`complete -C`. When `fish` or `zsh` is not on the `PATH`, the tests of that
shell print an explicit `SKIP` line on stderr and pass without executing
the completion; they are the only part of the suite that depends on an
optional interpreter.

The suite never installs anything and never downloads an image: the
container verification of the Zsh file is documented here, it is not part
of `./tests/run.sh`.

---

## Limits

* The dynamic suggestions are a snapshot taken at the moment of the
  `<TAB>`. A generation that is created in another terminal afterwards is
  not in the list of an already open menu.
* The completion reads the database schema directly (`generations.id`,
  `paths.path`). A future schema migration has to update the three files.
  The queries are one line each and they are the only schema knowledge
  outside `db/schema.sql` and `lib/`.
* `hm add` suggests absolute tracked paths. That is how `hm add` stores
  them; a relative suggestion would be a different path for the same entry.
* Directory candidates get the separator of the shell (a trailing `/`); the
  quoting of a space, a quote or a `$` is left to the completion system of
  the shell, which is the only component that knows the quoting rules of
  its own command line.
