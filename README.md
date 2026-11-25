# devpin

One place per repository for the device every build, test and run of an Apple project goes to.

devpin keeps the choice in a `.devpin/` directory at the repository root and prints it as the value of
`xcodebuild -destination`:

```sh
xcodebuild test -scheme MyApp -destination "$(devpin get)"
```

- **one clone, its own device** — a machine's choice lives in a git-ignored file, the project's default
  in a committed one;
- **packages follow the app** — `devpin use "iPhone 17 Pro"` writes the choice into the app and every
  package listed in its `config`, beside it (`../packages/*`) or inside it (`packages/*`);
- **named slots** — a second device, for an on-device test runner for example, falling back to the main
  one when not set;
- **a hardcode check** — `devpin check` fails on a device written into a command anywhere else.

One zsh script, macOS only, installed with Homebrew.

**Status:** 1.0 in development.

## Install

```sh
brew install iruirc/tap/devpin
```

It needs macOS, its built-in zsh and git. The device lists come from Xcode's `xcrun simctl` and
`xcrun devicectl`.

## Quick start

```sh
cd MyApp
devpin init --default "iPhone 17 Pro"   # creates .devpin/ and the .gitignore line
devpin use "iPhone 17"                  # this machine's choice, git-ignored
xcodebuild test -scheme MyApp -destination "$(devpin get)"
```

## The files

Every repository, the app and each package, keeps its choice in `.devpin/` at its root:

| File | What it holds | In git |
|---|---|---|
| `default` | the main slot, the project's value | yes |
| `local` | the main slot, this machine's choice | no |
| `<slot>.default` | optional, the same for a named slot | yes |
| `<slot>.local` | the same, this machine's choice | no |
| `config` | the format below; required only where `use` and `check` run | yes |

The repository's `.gitignore` holds `.devpin/*local`; `devpin init` adds the line, and `devpin use`
warns when git does not ignore the file it wrote.

A value is the first non-blank line of its file, stripped of surrounding whitespace (a `\r` from a
Windows editor included). A file of whitespace alone reads as absent. A value is an
`xcodebuild -destination` string: `platform=iOS Simulator,id=<UDID>`, or `platform=iOS,id=<UDID>` for a
phone. You may write `name=…` by hand; `devpin use` always writes `id=`.

## config

One entry per line; `#` starts a comment; blank lines are skipped.

```
requires 1.0            the lowest devpin this project accepts; an older one refuses to run
slot runner             declares a slot; one line per slot
packages ../packages/*  package directories, relative to the root; globs; several lines allowed
check-ignore Docs/**    paths check does not read, relative to the root
```

- An unknown first word is an error naming the line, never a skip.
- `requires` takes `major.minor` or `major.minor.patch`, compared part by part as numbers (a project
  requiring `1.10` refuses devpin 1.9.0); a missing part counts as 0. A project that needs a newer
  devpin is reported as that, whatever else its `config` holds.
- A slot name is `a-z`, `0-9` and `-`.
- `packages` matches that hold no `Package.swift` are skipped, and `devpin show` names them. A pattern
  that matches nothing warns. No `packages` line means the root alone.
- `check-ignore` paths are relative to the root of the app, even when they reach into a package:
  `../packages/Core/Docs/**` beside the app, `packages/Core/Docs/**` inside it.
- A missing `.devpin/config` is an empty config: `get`, `show` and `list` work without one. A package
  has no `config` of its own; it follows the app's.

## Which repository is read

The nearest directory holding `.devpin/`, walking up from the working directory and never above the top
of the enclosing git repository. `--root <dir>` names it instead. A package is its own repository, so
from inside it devpin finds the package's `.devpin/` and never the app's. When none is found, devpin
exits 1 and says where it looked.

## Resolution

For slot `S`, the first non-empty source wins:

| | main slot | slot `S` |
|---|---|---|
| 1 | `DEVPIN_DESTINATION` | `DEVPIN_DESTINATION_<S>` (upper case, `-` as `_`) |
| 2 | `.devpin/local` | `.devpin/S.local` |
| 3 | `.devpin/default` | `.devpin/S.default` |
| 4 | none | the main slot, by rows 1 to 3 |

An environment variable set to the empty string counts as unset. A slot with no device of its own is the
main device, so a project with no second device never sees slots. A slot is valid when the app's
`config` declares it, or when the repository read holds a file for it (a package has no `config`, but it
got `runner.local` from `devpin use --slot runner`). Any other name, a typo such as `runer`, is an error
listing the known slots, never a silent fallback.

## Commands

Every command exits 0 on success, 1 when refused or failed, and 2 for a wrong invocation (usage on
stderr). Every message goes to stderr, starts with `devpin:`, and names the reason, where the value came
from and the command that fixes it. `--root <dir>` goes before the command.

### `devpin get [--slot S]`

Prints one line on stdout: the resolved destination.

```
$ devpin get
platform=iOS Simulator,id=<UDID>
```

It exits 1, with nothing on stdout, when no source holds a value; when an `id=` is known to neither
`xcrun simctl` nor `xcrun devicectl` (a paired phone that is not connected passes); or when `simctl`
marks the simulator unavailable, its runtime removed for example. A value without `id=` is not checked.
When a list cannot be read, devpin warns, prints the value and exits 0.

Ids are matched case-sensitively, as `simctl` lists them (upper case). `devpin use` accepts a UDID in
any case and writes it as listed, so a hand-written id in another case is the one to look at when `get`
says an id is unknown.

### `devpin show`

One row per repository and slot of the app and every package of its `config`: the source (`env`,
`local`, `default`, `main` for a slot that falls back, `missing`) and the value with the device it names.
UDIDs are shortened to `<UDID>` here.

```
$ devpin show
MyApp                    main       local    platform=iOS Simulator,id=<UDID> (iPhone 17)
MyApp                    runner     local    platform=iOS,id=<UDID> (Dev Phone)
../packages/pkgA         main       local    platform=iOS Simulator,id=<UDID> (iPhone 17)
../packages/pkgA         runner     local    platform=iOS,id=<UDID> (Dev Phone)
```

A stale id reads `(unknown id)`, an unavailable simulator carries the reason `simctl` gives. A match
without `Package.swift` and a package without `.devpin/` get a line of their own. Exit 0 whenever the
configuration could be read.

### `devpin list`

The available simulators and the paired phones, with their UDIDs.

```
$ devpin list
Simulators:
  iPhone 17 Pro                        1A2B3C4D-0000-0000-0000-000000000001
  iPhone 17                            1A2B3C4D-0000-0000-0000-000000000002
Devices:
  Dev Phone                            00008120-000AAAABBBBCCCC1
```

Without `devicectl`: the simulators alone and a warning. Exit 1 when `simctl` itself fails.

### `devpin use [--slot S] [--only-root] <device>`

`<device>` is a device name, a UDID, or a string holding `platform=`. A name or UDID is written as
`platform=…,id=<UDID>`; a `platform=` string is written as given.

```
$ devpin use "iPhone 17"
.devpin/local <- platform=iOS Simulator,id=<UDID> (iPhone 17):
  MyApp                        written
  ../packages/pkgA             written
  ../packages/pkgB             written
```

It writes `.devpin/local` (or `S.local`) in the app and in every package of `config`; `--only-root`
writes the app alone. Each write is atomic: a temporary file beside the target, then `mv`.

- A name two devices share, or one nobody has, is refused before anything is written, with the
  candidates listed. `booted` is always refused: with two simulators booted it would pick either.
- Exit 1 when any repository was not written; the others still are.
- A `local` file that `git check-ignore` does not ignore gets a warning naming the line to add; the
  write still happens.

### `devpin use [--slot S] [--only-root] --reset`

Removes `local` (or `S.local`) in the same repositories, so `default`, or the main slot, applies again.

### `devpin init [--default <device>]`

Creates `.devpin/` with a `config` skeleton, a `default` when `--default` is given (the device resolved
as `use` resolves it), and appends `.devpin/*local` to `.gitignore`. When the `config` already lists
`packages`, it does the same in every package, without `config`. It never overwrites a file and says
what it kept. The root is the `--root` directory, else the top of the enclosing git repository, else the
working directory.

### `devpin check`

Fails on a device written into a command. See the next section. Exit 0 clean, 1 findings.

### `devpin --version`

Prints the version.

## The hardcode check

A device written into a command bypasses the choice: `devpin use` moves every build to a new device, and
that one command keeps building on the old one, or fails on a machine without it. `devpin check` finds
such commands so that a project can fail on them.

**What is read.** In the app and in every package of `config`, every text file git counts as part of the
repository, at any depth: tracked files and new files not yet added (`git ls-files -co
--exclude-standard`), and nothing `.gitignore` excludes (`.build`, `DerivedData` and the like). Outside a
git repository, a walk of the tree that skips `.git`, `.build`, `DerivedData`, `*.xcodeproj`. Always
skipped: `.devpin/`, binary files and the paths of `check-ignore`. Extensions do not matter: a device is
written into scripts, Makefiles, CI files, Markdown with commands in it, Swift.

**What counts as a finding**, a device in the role of a destination:

- a literal `key=value` after `-destination`;
- `name=` or `id=` inside a `platform=…` string, unless the value is `$…` or `<…>`;
- a literal value assigned to `DESTINATION`, `DEST` or `SIMULATOR` with `=`, `:=`, `?=` or `+=`.

**What passes:** a destination that names only the host platform (macOS), `generic/…`, a variable or a
command substitution (`-destination "$(devpin get)"`), a placeholder, and a device in prose ("measured on
iPhone 17 Pro").

**Output.** `path:line:text` per finding, grouped by repository and relative to the app's root, then a
total and the fix. Colour only when stdout is a terminal.

```
$ devpin check
✗ MyApp
build.sh:1:xcodebuild test -scheme MyApp -destination "platform=iOS Simulator,name=iPhone 17 Pro"
devpin: 1 hardcoded destinations — take the device from devpin get, or write it into .devpin/default
```

Where to run it is the project's choice: in CI, in a pre-commit hook, on the first line of a build
script. devpin wires it into nothing. Run it from the app; `check-ignore` keeps out what should not be
read, such as documentation that quotes a command.

## Use from scripts and from spine

A script takes the device from devpin and passes it on:

```sh
xcodebuild test -scheme MyApp -destination "$(devpin get)"
xcodebuild test -scheme MyAppRunnerTests -destination "$(devpin get --slot runner)"
```

`devpin get` exits 1 with nothing on stdout when there is no device to give, so a script run with
`set -e` stops there rather than building on whatever `xcodebuild` falls back to.

A spine project hands devpin to its stages in one line of its configuration:

```
[DEVICE_SOURCE] = [devpin get]
```

## Development

Requirements: macOS, zsh (built in), bats-core.

```sh
brew install bats-core
scripts/test.sh            # syntax check of bin/devpin, then every test
bats tests/get.bats        # one file
```

The tests drive the script only through its command line, in temporary git repositories, with an `xcrun`
stub first on `PATH`; no test depends on the devices of the machine it runs on.

- `tests/helpers/bin/xcrun` is the stub. It answers `xcrun simctl list devices [available]` and `xcrun
  devicectl list devices …` from fixtures, and anything else with exit 64. `STUB_SIMCTL` and
  `STUB_DEVICECTL` name the files it prints (an empty `STUB_DEVICECTL` makes `devicectl` fail);
  `XCRUN_RECORD` names a file it appends each call to.
- `tests/helpers/fixtures/simctl.txt` and `devicectl.txt` hold the fixed device lists: available and
  unavailable simulators, two devices sharing a name, phones, a watch.
- `tests/helpers/common.bash` holds the shared setup and helpers: `make_repo`, `make_package`, `put`,
  `sibling_tree`, `nested_tree`, `xcrun_calls` and the assertions.

To add a test, put it in the `.bats` file of its command (`tests/<command>.bats`; `tests/config.bats`
for `config`), or start a new file with:

```sh
bats_require_minimum_version 1.5.0
load helpers/common
setup() { common_setup; }
```

build the repositories under `$WORK` with the helpers, call `devpin` through `run --separate-stderr`, and
assert on `$status`, `$output` and `$stderr`. Never use a bare `[[ … ]]` as an assertion: macOS runs
bats under bash 3.2, where a failing `[[ … ]]` that is not the last command of a test does not fail it.
Use `[ … ]`, `assert_contains`, `refute_contains` or `assert_matches`.

### Releasing

`scripts/release.sh <version>`, from the repository root on `main`, with a clean tree and a
`## Unreleased` section of `CHANGELOG.md` that holds entries. It runs the suite, sets the version line of
`bin/devpin`, dates the changelog section, commits `release: <version>`, tags `v<version>`, and asks
before pushing `main` and the tag. A second question updates the formula in the Homebrew tap through
`brew bump-formula-pr`, addressing the tap by name; it needs `brew` and `brew tap iruirc/tap`.

The first release has no formula to update: the script prints the formula, and it is added to the tap by
hand once. `scripts/release.sh tap <version>` runs the tap step alone, `scripts/release.sh formula
<version> <sha256>` prints the formula.

## License

MIT — see [LICENSE](LICENSE).
