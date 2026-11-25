bats_require_minimum_version 1.5.0
load helpers/common
# Every test releases from a clone of this repository: the working tree's bin/, scripts/,
# CHANGELOG.md and README.md are copied into it and committed on main, so uncommitted code is what
# runs. Its origin is a bare repository in the test's directory. The tap is a repository with its own
# bare remote, reached only through the brew stub, by name. Nothing here touches a real remote.

setup() {
  common_setup
  export DEVPIN_RELEASE_SKIP_TESTS=1
  export STUB_BREW_LOG="$WORK/brew.log" STUB_TAP="$WORK/tap"
  : > "$STUB_BREW_LOG"

  mkdir -p "$WORK/stubs"
  cat > "$WORK/stubs/brew" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_BREW_LOG"
case "$1" in
  tap)
    echo other/tap
    [ "${STUB_NO_TAP:-}" = 1 ] || echo iruirc/tap
    ;;
  --repository)
    [ "$2" = iruirc/tap ] && echo "$STUB_TAP"
    ;;
  bump-formula-pr)
    git -C "$STUB_TAP" commit -q --allow-empty -m "devpin: bump"
    ;;
esac
exit 0
EOF
  cat > "$WORK/stubs/curl" <<'EOF'
#!/bin/sh
printf archive
EOF
  chmod +x "$WORK/stubs/brew" "$WORK/stubs/curl"
  PATH="$WORK/stubs:$PATH"
  export PATH

  make_repo "$WORK/tap"
  mkdir "$WORK/tap/Formula"
  echo 'class Devpin < Formula; end' > "$WORK/tap/Formula/devpin.rb"
  git -C "$WORK/tap" add Formula
  git -C "$WORK/tap" commit -q -m formula
  git init -q --bare -b main "$WORK/tap-origin.git"
  git -C "$WORK/tap" remote add origin "$WORK/tap-origin.git"
  git -C "$WORK/tap" push -q -u origin main

  git init -q --bare -b main "$WORK/origin.git"
  git clone -q "$REPO" "$WORK/devpin"
  git -C "$WORK/devpin" remote set-url origin "$WORK/origin.git"
  rm -rf "$WORK/devpin/bin" "$WORK/devpin/scripts"
  cp -R "$REPO/bin" "$REPO/scripts" "$WORK/devpin/"
  cp "$REPO/CHANGELOG.md" "$REPO/README.md" "$WORK/devpin/"
  # independent of the real history: no inherited tags, and a version below every release under test
  git -C "$WORK/devpin" tag -l | while read -r t; do git -C "$WORK/devpin" tag -d "$t" >/dev/null; done
  sed -i '' 's/^DEVPIN_VERSION=.*/DEVPIN_VERSION="0.0.0"/' "$WORK/devpin/bin/devpin"
  git -C "$WORK/devpin" add -A
  git -C "$WORK/devpin" commit -q --allow-empty -m "working tree"
  git -C "$WORK/devpin" switch -q -C main
  git -C "$WORK/devpin" push -q -u origin main
}

# release <stdin text> <arguments...>: runs release.sh in the clone, answering its prompts.
release() {
  local answers=$1
  shift
  cd "$WORK/devpin" || return 1
  printf "$answers" | scripts/release.sh "$@"
}

origin_tags() { git -C "$WORK/origin.git" tag; }
clone_tags() { git -C "$WORK/devpin" tag; }
brew_log() { cat "$STUB_BREW_LOG"; }

@test "formula renders version and sha" {
  run --separate-stderr release '' formula 1.2.3 abc
  [ "$status" -eq 0 ]
  assert_contains "$output" 'url "https://github.com/iruirc/devpin/archive/refs/tags/v1.2.3.tar.gz"'
  assert_contains "$output" 'sha256 "abc"'
  assert_contains "$output" 'assert_equal "1.2.3"'
  assert_contains "$output" 'class Devpin < Formula'
  assert_contains "$output" 'depends_on :macos'
  assert_contains "$output" 'bin.install "bin/devpin"'
}

@test "formula without a version and a sha is a wrong invocation" {
  run --separate-stderr release '' formula 1.2.3
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "refuses a malformed version" {
  run --separate-stderr release '' 1.0
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "release:"
  [ -z "$(clone_tags)" ]
}

@test "refuses a version not above the current one" {
  run --separate-stderr release '' 0.0.0
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "release:"
  [ -z "$(clone_tags)" ]
}

@test "compares versions numerically" {
  sed -i '' 's/^DEVPIN_VERSION=.*/DEVPIN_VERSION="1.9.0"/' "$WORK/devpin/bin/devpin"
  git -C "$WORK/devpin" commit -q -am "version 1.9.0"
  run --separate-stderr release 'n\n' 1.10.0
  [ "$status" -eq 0 ]
  [ "$("$WORK/devpin/bin/devpin" --version)" = 1.10.0 ]
  run --separate-stderr release 'n\n' 1.9.5
  [ "$status" -eq 1 ]
}

@test "refuses a dirty tree" {
  touch "$WORK/devpin/stray"
  run --separate-stderr release '' 1.0.0
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "release:"
  [ -z "$(clone_tags)" ]
}

@test "refuses when not on main" {
  git -C "$WORK/devpin" switch -q -c topic
  run --separate-stderr release '' 1.0.0
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "main"
  [ -z "$(clone_tags)" ]
}

@test "refuses a tag that exists" {
  git -C "$WORK/devpin" tag v1.0.0
  run --separate-stderr release '' 1.0.0
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "v1.0.0"
}

@test "refuses an empty Unreleased section" {
  printf '# Changelog\n\n## Unreleased\n\n## 0.0.1 — 2026-01-01\n\n- old\n' > "$WORK/devpin/CHANGELOG.md"
  git -C "$WORK/devpin" commit -q -am "empty changelog"
  run --separate-stderr release '' 1.0.0
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "Unreleased"
  [ -z "$(clone_tags)" ]
}

@test "refuses a changelog without an Unreleased section" {
  printf '# Changelog\n\n## 0.0.1 — 2026-01-01\n\n- old\n' > "$WORK/devpin/CHANGELOG.md"
  git -C "$WORK/devpin" commit -q -am "no unreleased"
  run --separate-stderr release '' 1.0.0
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "Unreleased"
}

@test "refuses when the tap is not tapped" {
  export STUB_NO_TAP=1
  run --separate-stderr release '' 1.0.0
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "brew tap iruirc/tap"
  [ -z "$(clone_tags)" ]
}

@test "refuses when the suite fails" {
  unset DEVPIN_RELEASE_SKIP_TESTS
  printf '#!/bin/sh\nexit 1\n' > "$WORK/devpin/scripts/test.sh"
  git -C "$WORK/devpin" commit -q -am "failing suite"
  run --separate-stderr release '' 1.0.0
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "release:"
  [ -z "$(clone_tags)" ]
}

@test "bumps, commits and tags, then stops when push is declined" {
  run --separate-stderr release 'n\n' 1.0.0
  [ "$status" -eq 0 ]
  assert_contains "$output" "Push main and v1.0.0 to origin? [y/N]"
  assert_contains "$output" "git push origin main v1.0.0"
  assert_contains "$output" "scripts/release.sh tap 1.0.0"
  [ "$("$WORK/devpin/bin/devpin" --version)" = 1.0.0 ]
  [ "$(clone_tags)" = v1.0.0 ]
  [ "$(git -C "$WORK/devpin" cat-file -t v1.0.0)" = tag ]
  [ "$(git -C "$WORK/devpin" log -1 --format=%s)" = "release: 1.0.0" ]
  [ -z "$(git -C "$WORK/devpin" status --porcelain)" ]
  assert_contains "$(cat "$WORK/devpin/CHANGELOG.md")" "## 1.0.0 — "
  assert_matches "$(cat "$WORK/devpin/CHANGELOG.md")" '^## 1\.0\.0 — [0-9]{4}-[0-9]{2}-[0-9]{2}$'
  assert_contains "$(cat "$WORK/devpin/CHANGELOG.md")" "## Unreleased"
  [ -z "$(origin_tags)" ]
  refute_contains "$(brew_log)" "bump-formula-pr"
}

@test "the new Unreleased section sits above the release and is empty" {
  run --separate-stderr release 'n\n' 1.0.0
  [ "$status" -eq 0 ]
  local heads
  heads="$(grep '^## ' "$WORK/devpin/CHANGELOG.md")"
  [ "$(printf '%s\n' "$heads" | sed -n 1p)" = "## Unreleased" ]
  assert_matches "$(printf '%s\n' "$heads" | sed -n 2p)" '^## 1\.0\.0 — '
  # the entries moved under the release; Unreleased holds none
  [ -z "$(awk '/^## Unreleased/{f=1;next} /^## /{f=0} f && NF' "$WORK/devpin/CHANGELOG.md")" ]
  assert_contains "$(awk '/^## 1\.0\.0/{f=1;next} /^## /{f=0} f' "$WORK/devpin/CHANGELOG.md")" "devpin get"
}

@test "pushes, then leaves the tap when declined" {
  run --separate-stderr release 'y\nn\n' 1.0.0
  [ "$status" -eq 0 ]
  [ "$(origin_tags)" = v1.0.0 ]
  [ "$(git -C "$WORK/origin.git" log -1 --format=%s main)" = "release: 1.0.0" ]
  refute_contains "$(brew_log)" "bump-formula-pr"
  assert_contains "$output" "Update iruirc/tap/devpin to 1.0.0 and push the tap? [y/N]"
}

@test "bumps the formula through brew by name" {
  run --separate-stderr release 'y\ny\n' 1.0.0
  [ "$status" -eq 0 ]
  grep -Fxq 'bump-formula-pr --write-only --commit --url=https://github.com/iruirc/devpin/archive/refs/tags/v1.0.0.tar.gz iruirc/tap/devpin' "$STUB_BREW_LOG"
  [ "$(grep -c bump-formula-pr "$STUB_BREW_LOG")" -eq 1 ]
  [ "$(git -C "$WORK/tap-origin.git" log -1 --format=%s main)" = "devpin: bump" ]
}

@test "the tap step runs alone" {
  run --separate-stderr release 'y\n' tap 1.0.0
  [ "$status" -eq 0 ]
  grep -Fq -- '--url=https://github.com/iruirc/devpin/archive/refs/tags/v1.0.0.tar.gz iruirc/tap/devpin' "$STUB_BREW_LOG"
  [ "$(git -C "$WORK/tap-origin.git" log -1 --format=%s main)" = "devpin: bump" ]
}

@test "the tap step declined leaves the tap alone" {
  run --separate-stderr release 'n\n' tap 1.0.0
  [ "$status" -eq 0 ]
  refute_contains "$(brew_log)" "bump-formula-pr"
  [ "$(git -C "$WORK/tap-origin.git" log -1 --format=%s main)" = formula ]
}

@test "the first release prints the formula to add by hand" {
  rm -r "$WORK/tap/Formula"
  git -C "$WORK/tap" commit -q -am "no formula"
  local sha
  sha="$(printf archive | shasum -a 256 | cut -d' ' -f1)"
  run --separate-stderr release 'y\n' 1.0.0
  [ "$status" -eq 0 ]
  assert_contains "$output" "sha256 \"$sha\""
  assert_contains "$output" "Formula/devpin.rb"
  refute_contains "$(brew_log)" "bump-formula-pr"
  [ "$(origin_tags)" = v1.0.0 ]
}

@test "the tap step wrong invocation" {
  run --separate-stderr release '' tap
  [ "$status" -eq 2 ]
  run --separate-stderr release '' tap 1.0
  [ "$status" -eq 2 ]
}

@test "a rejected push says how to finish" {
  printf '#!/bin/sh\nexit 1\n' > "$WORK/origin.git/hooks/pre-receive"
  chmod +x "$WORK/origin.git/hooks/pre-receive"
  run --separate-stderr release 'y\n' 1.0.0
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "release: push failed"
  assert_contains "$stderr" "git push origin main v1.0.0"
  assert_contains "$stderr" "scripts/release.sh tap 1.0.0"
  [ "$(clone_tags)" = v1.0.0 ]
  [ -z "$(origin_tags)" ]
  refute_contains "$(brew_log)" "bump-formula-pr"
}
