# voidsetup

An async, resumable setup tool for Void Linux, with a Textual TUI and a
non-interactive CLI. It is a Python replacement for the old `install.sh` in
`mz2012007/dotfiles`, but it deliberately does **not** copy the old script's
SUID tricks, recursive `chown`s or destructive defaults.

## Why this exists

The original bash script is convenient but risky:

- it sets SUID on `sleep`, `poweroff`, `reboot` and `hostname`;
- it adds the user to privileged groups such as `root` and `sys`;
- it overwrites `/etc/sysctl.conf` and pins `/etc/resolv.conf`;
- it runs `chown -R "$USER:$USER" "$HOME"` and `/var/log`;
- it is not idempotent and has no dry-run, state or resume support;
- `error()` only prints a message, so failures do not stop the plan.

`voidsetup` turns every step into a small async task with a name, a
description, dependencies, a severity and an optional `check()` for
idempotency. See [REVIEW.md](REVIEW.md) for the detailed evaluation and the
mapping from the old functions to the new tasks.

## Requirements

- Void Linux (the tool refuses to run on other distributions by default; the
  check is in `voidsetup doctor`/preflight).
- Python 3.11 or newer.
- `sudo`, `xbps-install`, `xbps-query` and `rsync` for the corresponding
  tasks. Other commands (`stow`, `git`, `make`, `ufw`, `grub-mkconfig`,
  `plymouth-set-default-theme`, ...) are checked only when their tasks are
  selected.
- `textual` is the only runtime dependency.

## Install

```sh
cd ~/dotfiles/dev/installer
python3 -m venv .venv
. .venv/bin/activate
pip install -e '.[dev]'
```

The package installs the `voidsetup` command. The code lives in
`src/voidsetup/`.

## Quick start

```sh
# 1. Read-only environment/safety audit, including old-installer damage.
voidsetup doctor

# 2. See exactly what a profile would do.
voidsetup plan --profile during_work

# 3. Run it without changing anything.
voidsetup run --profile during_work --skip packages --dry-run --yes

# 4. Repair known damage left by the old installer (review with --dry-run first).
voidsetup run --profile repair --dry-run --yes
voidsetup run --profile repair --yes

# 5. Start the TUI (or just run `voidsetup` on a terminal).
voidsetup tui
```

For a real run that touches the system, start a sudo session first (the TUI
does this for you before root tasks):

```sh
sudo -v
voidsetup run --profile old_lab --groups base,gui_base,dwm --yes
```

`--yes` is required for non-interactive execution. `--json` additionally
requires `--yes` and writes a machine-readable result to stdout while all
human output goes to stderr.

## Profiles

| Profile | Purpose | Destructive |
| --- | --- | --- |
| `old_lab` | The old-lab workflow without wiping the home directory. | no |
| `during_work` | Safe repeatable maintenance: clock, updates, packages, fonts. | no |
| `dotfiles` | Stow dotfiles, copy configs, refresh TPM/mpv/fonts. | no |
| `fresh` | Back up and clear the home directory, then run the full setup. | yes (`backup_home`) |
| `repair` | Remove legacy SUID bits, repair resolv.conf, remove the stray tmux dir. | no |
| `custom` | Pick tasks yourself with `--tasks a,b,c` or in the TUI. | depends |

Profiles are ordered task lists; dependencies are inserted automatically.
`--skip update` also removes every selected task that depends on `update`
(for example `packages`). The TUI shows all tasks and lets you change the
selection before starting.

## Safety model

- **Dry-run first**: `--dry-run` never runs a mutating command. Read-only
  probes (for example `xbps-query -l` and `stow --simulate`) still run so
  checks are meaningful.
- **No SUID hacks**: the optional `power_polkit` task writes a narrow polkit
  rule instead of changing the mode of `sleep`/`poweroff`/`reboot`. The
  optional `harden_suid` task removes legacy SUID bits from `sleep`,
  `poweroff`, `reboot`, `hostname` and `zzz`; it is included in `old_lab`
  and `fresh`.
- **Curated groups**: `root`, `sys`, `kmem`, `tty`, `xbuilder` and similar
  system groups are refused even if configured.
- **Safe DNS**: `/etc/resolv.conf` is written root-owned; the immutable flag
  is removed unless `resolv_immutable = true` is explicitly configured.
- **Drop-in sysctl**: values go to `/etc/sysctl.d/99-voidsetup.conf`, not
  `/etc/sysctl.conf`.
- **Explicit destructive work**: tasks marked dangerous require
  `--allow-destructive` (CLI) or the confirmation checkbox (TUI). This
  includes `backup_home` in the `fresh` profile.
- **Stow conflicts**: if an existing target file is not a symlink, `stow`
  stops with a list. With `--allow-destructive`, the conflicting files are
  moved to
  `~/.local/state/voidsetup/stow-backups/<timestamp>/` and then stowed.
- **Resumable state**: completed tasks are recorded atomically in
  `~/.local/state/voidsetup/state.json`; use `--resume` after a failure and
  `--fresh` to discard previous state. Resume is accepted only for the exact
  same task plan, so a changed plan cannot silently skip work. A dry-run never
  writes state.
- **Sudo keepalive**: the CLI/TUI refreshes the sudo timestamp every 45
  seconds while a run is active, instead of an unmanaged background loop.
- **Logs**: every run writes a human-readable log under
  `~/.local/state/voidsetup/logs/`; old logs are pruned (`log_keep`, default
  20).

## Package groups

Package groups are parsed from `~/dotfiles/packages.sh` without executing the
file. The parser supports the simple `name=(package package)` arrays used by
the repository and ignores comments. The historical typo group `blutouth` is
recognized: select `bluetooth` and it resolves to the `blutouth` array.

You can also pick **individual packages** — either from the full list built out
of every group, or by typing names that are not in any group. Selecting
anything in the TUI automatically adds the `packages` task to the plan.

```sh
voidsetup packages                 # list groups
voidsetup packages --json          # machine-readable map
voidsetup run --profile old_lab --groups base,dwm,sound_pipewire --yes
voidsetup run --profile old_lab --all-groups --yes
voidsetup run --profile during_work --packages neovim,git --yes
```

`sound_pulseaudio` and `sound_pipewire` are both selectable, but the CLI warns
that normally only one should be installed. Manual package names are validated
before they reach `xbps-install`; duplicates across groups are installed once.

## Commands

```
voidsetup tui [--profile P] [--dry-run]
voidsetup run (--profile P | --tasks a,b) [--skip c,d]
             [--groups g1,g2 | --all-groups] [--packages p1,p2]
             [--dry-run] [--yes] [--json]
             [--resume | --fresh] [--force]
             [--allow-destructive] [--reboot]
             [--plymouth-theme THEME]
voidsetup plan  (--profile P | --tasks a,b) [--skip c,d] [--json]
voidsetup list [--json]
voidsetup profiles [--json]
voidsetup packages [--json]
voidsetup doctor [--json]
voidsetup themes [--json]          # Plymouth themes
voidsetup schemes [--json]         # TUI colour schemes
voidsetup init-config [--force]
```

Global options: `--config PATH`, `--dotfiles PATH`, `--state-dir PATH`,
`--verbose`, `--version`.

Useful task examples:

```sh
voidsetup run --tasks dns --dry-run --yes
voidsetup run --tasks dns --yes
voidsetup run --tasks timezone --yes
voidsetup run --tasks stow --allow-destructive --yes
voidsetup run --tasks packages --groups base --yes
```

## Configuration

Run `voidsetup init-config` to write a commented sample to
`~/.config/voidsetup/config.toml`. The defaults intentionally mirror the
dotfiles repository:

```toml
dotfiles = "~/dotfiles"
state_dir = "~/.local/state/voidsetup"
timezone = "Africa/Cairo"
resolv_immutable = false
power_polkit = true
admin_group = "wheel"
plymouth_theme = ""
tui_theme = "textual-dark"
log_keep = 20

[[repos]]
name = "my-repo"
url = "https://raw.githubusercontent.com/mz2012007/void-xbps/refs/heads/main/x86_64"
```

Environment overrides: `VOIDSETUP_CONFIG`, `VOIDSETUP_DOTFILES`,
`VOIDSETUP_STATE_DIR`.

Missing rsync sources (for example the polkit rule or `.ssh/agent` when they
are not present in a checkout) produce a warning and are skipped; they do not
abort the run.

## TUI flow

1. Welcome: run `doctor`, start, or quit.
2. Profile: choose one of the profiles.
3. Plan: toggle tasks, pick package groups and/or individual packages, enable
   dry-run/resume, optionally allow destructive tasks, and pick a Plymouth
   theme. Selecting packages adds the `packages` task automatically.
4. Execution: live task table, progress bar, streaming log and an abort
   button (stops after the current command).
5. Summary: status counts, log path, resume failed tasks, new run, reboot
   when safe. Resume reuses the same plan and skips tasks already completed.

The **Package selection** dialog has two tabs: *Groups* (whole arrays from
`packages.sh`) and *Individual packages* (filterable list plus a field for
arbitrary names). Press Enter to apply. **Ctrl+T** opens the colour-scheme
picker; it previews schemes live and saves the choice to
`~/.config/voidsetup/config.toml` as `tui_theme`.

Sudo is requested while the TUI is suspended, so the password prompt appears
in the normal terminal. Run the TUI in a real terminal; `voidsetup tui` refuses
to start without a TTY.

## Development

```sh
.venv/bin/python -m pytest
.venv/bin/python -m compileall -q src
```

The tests are hermetic: they use temporary directories, never run root tasks,
and use dry-run for the end-to-end CLI/TUI paths. Destructive tasks are not
exercised by the test suite.

## Known limitations

- There is no automatic rollback. A failed run leaves state so you can resume,
  and the log explains which command failed.
- Tasks run sequentially. The dependency model is ready for parallel groups,
  but ordering is intentionally conservative for system changes.
- stow conflict handling is per-target-file; unusual directory conflicts may
  still require manual intervention.
- Package group definitions are read from `packages.sh`; they are not
  duplicated in the TOML config.
