# Changelog

All notable changes to devpin are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[semantic versioning](https://semver.org/).

## Unreleased

### Added

- `devpin check` finds a slot the project root does not declare: `--slot X` on a line that names
  `devpin`, and `DEVPIN_DESTINATION_X`, in the files of the app and of its packages.
- `--packages <glob>` on `show`, `use` and `check`, and `DEVPIN_PACKAGES`, replace the list of packages
  of `config`; a relative glob is taken from the working directory.

### Changed

- A slot in a repository without `.devpin/config`, a package for one, falls back to the main device,
  with a warning from `get`, instead of being refused as unknown.
- `devpin check` prints `✓ No hardcoded destination or undeclared slot in N repositories.` when clean,
  and a second total line when slots are found.
- `devpin check` reads a slot as declared only from a `slot` line or an `S.default` in the app's
  `.devpin/`; a slot known only from `S.local` there is now reported.

## 1.0.0 — 2026-11-26

### Added

- `devpin get [--slot S]` prints the destination for `xcodebuild -destination`, refusing an `id=` that
  no simulator or paired phone answers to and a simulator that `simctl` marks unavailable.
- `devpin show` lists, for the app and every package of its `config`, each slot with its value, where
  the value came from and the device it names.
- `devpin list` lists the available simulators and the paired phones with their UDIDs.
- `devpin use [--slot S] [--only-root] <device>` and `--reset` write or remove this machine's choice,
  atomically, in the app and in every package of its `config`.
- `devpin init [--default <device>]` creates `.devpin/` in the app and in its packages, with a `config`
  skeleton and the `.gitignore` line, and never overwrites a file.
- `devpin check` fails on a device written into a command, in every file git counts as part of the
  repository.
- Named slots, declared with `slot` in `.devpin/config`, falling back to the main device.
- `.devpin/config` entries `requires`, `slot`, `packages` and `check-ignore`.
- `--root <dir>` and `--version`.
- `scripts/release.sh`, which cuts a version and feeds the Homebrew tap.
