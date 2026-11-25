# Shared helpers for every .bats file. Load with: load helpers/common

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

SIM='platform=iOS Simulator'
DEV='platform=iOS'
DEFAULT_DEST="$SIM,name=Test Phone"

SIM_ID=11111111-2222-3333-4444-555555555555
TWIN_ID_1=AAAAAAAA-0000-0000-0000-000000000001
TWIN_ID_2=AAAAAAAA-0000-0000-0000-000000000002
OLD_ID=BBBBBBBB-0000-0000-0000-000000000000
GONE_ID=99999999-0000-0000-0000-000000000000
DEV_ID=00008120-000AAAABBBBCCCC1
OTHER_DEV_ID="${DEV_ID}0"
WATCH_ID=00008310-000DDDDEEEEFFFF1
WATCH_SIM_ID=CCCCCCCC-0000-0000-0000-000000000000

common_setup() {
  local v
  for v in $(compgen -e | grep '^DEVPIN_' || true); do unset "$v"; done
  PATH="$REPO/tests/helpers/bin:$REPO/bin:$PATH"
  export PATH
  unset XCRUN_RECORD
  export STUB_SIMCTL="$REPO/tests/helpers/fixtures/simctl.txt"
  export STUB_DEVICECTL="$REPO/tests/helpers/fixtures/devicectl.txt"
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
  export GIT_CONFIG_GLOBAL=/dev/null
  WORK="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
}

# make_repo <dir>: a git repository ignoring .devpin/*local, with one commit.
make_repo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main
  printf '.devpin/*local\n' > "$1/.gitignore"
  git -C "$1" add .gitignore
  git -C "$1" commit -q -m init
}

# make_package <dir>: a repository holding a Package.swift.
make_package() {
  make_repo "$1"
  printf '// swift-tools-version:5.9\n' > "$1/Package.swift"
  git -C "$1" add Package.swift
  git -C "$1" commit -q -m package
}

# put <repo> <file> <value>: write <repo>/.devpin/<file>; ABSENT removes it.
put() {
  if [ "$3" = ABSENT ]; then
    rm -f "$1/.devpin/$2"
  else
    mkdir -p "$1/.devpin"
    printf '%s\n' "$3" > "$1/.devpin/$2"
  fi
}

# sibling_tree <root>: app next to its packages; prints the app path.
sibling_tree() {
  make_repo "$1/MyApp"
  put "$1/MyApp" config 'packages ../packages/*'
  make_package "$1/packages/pkgA"
  make_package "$1/packages/pkgB"
  make_repo "$1/packages/notAPackage"
  printf '%s\n' "$1/MyApp"
}

# nested_tree <root>: packages inside the app, each its own repository; prints the app path.
nested_tree() {
  make_repo "$1/MyApp"
  printf '/packages/\n' >> "$1/MyApp/.gitignore"
  put "$1/MyApp" config 'packages packages/*'
  make_package "$1/MyApp/packages/pkgA"
  make_package "$1/MyApp/packages/pkgB"
  printf '%s\n' "$1/MyApp"
}

# xcrun_calls <simctl|devicectl>: how many times the stub was called for that tool.
xcrun_calls() {
  [ -f "${XCRUN_RECORD:-/nonexistent}" ] || { echo 0; return; }
  grep -c "^$1 " "$XCRUN_RECORD" || true
}

# Assertions. Under bash 3.2 (macOS) a failing `[[ ]]` that is not the last command of a
# test does not fail it, so never use a bare `[[ ]]` as an assertion: use these or `[ ]`.
# assert_contains <haystack> <needle> / refute_contains <haystack> <needle> (literal match)
assert_contains() {
  case $1 in *"$2"*) return 0 ;; esac
  printf 'expected to contain: %s\n--- in:\n%s\n' "$2" "$1" >&2
  return 1
}
refute_contains() {
  case $1 in *"$2"*) ;; *) return 0 ;; esac
  printf 'expected NOT to contain: %s\n--- in:\n%s\n' "$2" "$1" >&2
  return 1
}
# assert_matches <string> <extended regex>
assert_matches() {
  printf '%s\n' "$1" | grep -Eq -- "$2" && return 0
  printf 'expected to match: %s\n--- in:\n%s\n' "$2" "$1" >&2
  return 1
}
