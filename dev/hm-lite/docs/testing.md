# Testing

The test suite is a self contained Bash program. It has no dependency
beyond the tools HM-Lite itself needs, and it never touches the real home
directory.

```sh
./tests/run.sh              # the whole suite
./tests/run.sh 06_apply     # only the suites whose file name matches
```

---

## 1. The isolation

Every test case runs in its own project directory:

```
$TMPDIR/hm-lite-tests.XXXXXXXX/     the root of one run
└── work/<case name>/
    ├── project/                    the runtime directory (HM_DIR)
    ├── source/                     the "live" files of the test
    └── destination/                a second target area
```

The runner creates one unique temporary root for the whole run and removes
it again at the end. `$HOME` is never written to, and the real content
store is never touched.

The environment of a test:

| Variable | Meaning |
|---|---|
| `HM_BIN` | The path of the `hm` executable under test. |
| `TEST_ROOT` | The root of the temporary area. |
| `HM_DIR` | The runtime directory of the current case. |
| `HM_ALLOW_OUTSIDE_HOME` | `1`, because the test workspace is outside of `$HOME`. |

---

## 2. The harness

`tests/lib/harness.sh` provides the isolation and the assertions.

### Running the command

| Helper | Behaviour |
|---|---|
| `run_hm <args…>` | Runs `hm` with a **closed** standard input. A command that asks for a confirmation must not block the test run. Stores the output in `HM_OUTPUT` and the exit status in `HM_STATUS`. |
| `run_hm_input <input> <args…>` | Runs `hm` with the given text on standard input, for the confirmation prompts. The escape `\n` may be used instead of a real line break. |

### Assertions

| Assertion | Checks |
|---|---|
| `assert_eq <expected> <actual> <message>` | Two values are equal. |
| `assert_rc <expected> <actual> <message>` | The exit status is the expected one. |
| `assert_contains <haystack> <needle> <message>` | The output contains a string. |
| `assert_not_contains <haystack> <needle> <message>` | The output does not contain a string. |
| `assert_file_exists <path> <message>` | The path exists. |
| `assert_file_absent <path> <message>` | The path does not exist. |
| `assert_dir_empty <path> <message>` | The directory has no entries. |
| `assert_file_content <path> <expected> <message>` | The content of a file is exactly the expected text. |
| `assert_sql <expected> <sql> <message>` | A query against the project database returns the expected value. The query runs directly in `sqlite3`, independent of the code under test. |
| `assert_count <expected> <actual> <message>` | A count matches. |

`assert_sql` is the important one for the database: the tests never trust
the code under test to check its own work.

---

## 3. The test files

| File | Content | Tests |
|---|---|---|
| `tests/cases/01_init.sh` | The bootstrap: directories, configuration, schema, idempotence, the version. | 11 |
| `tests/cases/02_add.sh` | The registration: discovery, symlink skipping, deduplication, the preview, the confirmation, hostile file names. | 15 |
| `tests/cases/03_gen.sh` | The capture: hashing, the store, the transaction, the missing path, the carry forward. | 15 |
| `tests/cases/04_list.sh` | The read only views and their error cases. | 12 |
| `tests/cases/05_switch.sh` | `switch` and `discard`: the materialisation, the atomic rename, the recorded mode. | 13 |
| `tests/cases/06_apply.sh` | The live write path: the classification, the backup, the manifest, the conflicts, the rollback. | 16 |
| `tests/cases/07_backup.sh` | `backup` and `restore`: the archive, the manifest, the validation, the activation. | 11 |
| `tests/cases/08_clean.sh` | The garbage collection: the reference analysis, the removal, the missing objects. | 10 |
| `tests/cases/09_completion.sh` | The three completion files: the commands, the options per command, the argument ranges, the generation ids, the paths with spaces, the fail-safe behaviour without a database, the absence of side effects. | 18 |
| `tests/cases/10_show.sh` | `show`: the metadata block, the entry table, the selected marker, the missing objects, the usage and state errors, the read-only guarantee. | 12 |
| `tests/cases/11_delete.sh` | `delete`: the preview, the confirmation, `--yes`/`-y`, the selected generation, the parent of the children, the orphan hand-off to `clean`, the rollback of a failing transaction. | 15 |
| `tests/cases/12_color.sh` | The colours: the automatic detection on a terminal and on a pipe, `HM_COLOR`, `NO_COLOR`, the stream each palette follows, the unchanged plain output. | 8 |
| `tests/cases/13_status.sh` | `status`: the project overview, the store space and its classification (referenced, unreferenced, missing), the size of every generation with the shared content counted once, the selected marker, the empty project, the read-only guarantee, the usage and state errors, the colours of the dashboard. | 15 |

**171 test cases**, plus the static analysis. The runner reports 172 checks
when ShellCheck is missing and 173 when it is installed.

---

## 4. The static analysis

After the test cases the runner analyses the code:

1. **The syntax check** runs always: `bash -n` on every shell file of the
   project. A file that does not parse fails the run.
2. **ShellCheck** runs when the binary is available. It is checked with
   `-x -S style -e SC1090,SC1091`, because the dynamic `source` of the
   command modules cannot be followed statically.

On the development machine ShellCheck **is** installed, so the step runs and
the project is free of findings. The runner skips it automatically when the
binary is not on the `PATH`.

---

## 5. What the suite deliberately checks

These are the behaviours that would be dangerous to get wrong, so they
have an explicit test:

* A file name with a space, an apostrophe or a newline survives the whole
  cycle: discovery, registration, capture, listing and the write back.
* A symbolic link is never followed and never written through.
* A pending path that vanishes makes `hm gen` fail with exit code `4` and
  leaves the previous state intact.
* A failed write rolls back the files that were already written.
* A conflict stops `hm apply` before anything is changed.
* An archive with a damaged file is refused by `hm restore`.
* A content object that a generation needs but that is missing from the
  store is reported by `hm clean` and never removed.
* `hm status` counts the size of a generation from its distinct content
  objects: shared content is counted once, and the store totals always
  match the objects on disk.
* Every command that changes something asks for a confirmation, and a
  closed standard input answers "no".
* A declined confirmation ends the command with exit code `7`, so a script
  can tell "the user said no" apart from "the command did its work".
* A failing query stops the command instead of producing an empty result:
  `hm list` and `hm clean` report the database failure, and `hm clean`
  removes nothing when the store cannot be read.
* The completion never changes the project: a fingerprint of the project
  directory, the database and the files of the store is identical before
  and after the completion calls, and no journal, WAL or shared memory file
  appears.
* The completion fails safe: without a database, and with a database that
  is not a database, it exits 0, offers no generation id, prints no shell
  error and does not create the database as a side effect.
* The completion never offers an option outside its command (`backup` has
  no `--yes`) and never offers an argument after a positional one that is
  already complete (`switch 1 <TAB>` offers nothing).
* `hm delete` refuses the selected generation (exit `3`, nothing deleted),
  clears the parent of its children and rolls both statements back when
  the transaction fails (exit `5`, the generation and its entries are
  still there).
* The colours are decided per stream: a pipe gets no escape sequence, a
  terminal does, `HM_COLOR=always` and `HM_COLOR=never` win over the
  detection, and a non-empty `NO_COLOR` wins over everything. Stripping
  the escape sequences from a coloured run gives exactly the plain output.
* `hm show` records no change: the generation and entry counts are
  identical before and after the calls.

The Fish and Zsh tests need an optional interpreter, the pseudo terminal
tests need `script` from util-linux. When `fish`, `zsh` or `script` is not
on the `PATH` the affected tests print an explicit `SKIP` line on stderr
and pass without executing that check; the Bash tests always run.

---

## 6. Writing a new test

Add a file to `tests/cases/`, name it `NN_topic.sh` and list the tests in
the `TESTS` array at the top:

```bash
TESTS=(
  test_something_works
)

test_something_works() {
  _test_setup my_case
  printf 'hello\n' > "$SRC_DIR/a.txt"

  run_hm_input 'y\n' add "$SRC_DIR/a.txt"
  run_hm_input 'y\n' gen

  assert_rc 0 "$HM_STATUS" "the generation was created"
  assert_sql "1" "SELECT COUNT(*) FROM generations;" "one generation exists"
}
```

`_test_setup <name>` creates the isolated project and initialises it. Use
`_test_setup <name> raw` when the test needs an uninitialised project.

The runner picks the file up automatically, there is no registry to
update.
