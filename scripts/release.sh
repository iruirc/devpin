#!/bin/zsh
# Cuts a devpin version and feeds the Homebrew tap.
#
#   scripts/release.sh <version>                  bump, commit, tag, push on confirmation, then the tap step
#   scripts/release.sh tap <version>              the tap step alone
#   scripts/release.sh formula <version> <sha256> print the formula
#
# DEVPIN_RELEASE_SKIP_TESTS=1 skips the test suite (the test hook: the suite tests this script).
setopt no_unset pipe_fail
cd "${0:A:h}/.." || exit 1

TAP_NAME=iruirc/tap
REPO_URL=https://github.com/iruirc/devpin

refuse() { print -u2 -r -- "release: $*"; exit 1 }

usage() {
  print -u2 -r -- "Usage: scripts/release.sh <version> | tap <version> | formula <version> <sha256>"
  exit 2
}

archive_url() { print -r -- "$REPO_URL/archive/refs/tags/v$1.tar.gz" }

# formula <version> <sha256>: prints Formula/devpin.rb.
formula() {
  local version=$1 sha=$2
  cat <<EOF
class Devpin < Formula
  desc "One place per repository for the device every Apple build goes to"
  homepage "$REPO_URL"
  url "$(archive_url "$version")"
  sha256 "$sha"
  license "MIT"

  depends_on :macos

  def install
    bin.install "bin/devpin"
  end

  test do
    assert_equal "$version", shell_output("#{bin}/devpin --version").strip
  end
end
EOF
}

valid_version() { [[ $1 =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] }

# version_gt <a> <b>: succeeds when a > b, part by part as numbers.
version_gt() {
  local -a a b
  a=( ${(s:.:)1} ); b=( ${(s:.:)2} )
  local i
  for (( i = 1; i <= 3; i++ )); do
    (( 10#${a[i]:-0} > 10#${b[i]:-0} )) && return 0
    (( 10#${a[i]:-0} < 10#${b[i]:-0} )) && return 1
  done
  return 1
}

current_version() { sed -n 's/^DEVPIN_VERSION="\(.*\)"$/\1/p' bin/devpin }

# unreleased_entries: prints the non-blank lines of the "## Unreleased" section of CHANGELOG.md.
unreleased_entries() {
  awk '/^## Unreleased[[:space:]]*$/ { f = 1; next } /^## / { f = 0 } f && NF' CHANGELOG.md
}

need_brew() {
  command -v brew >/dev/null 2>&1 || refuse "brew is not on PATH — the tap step needs Homebrew"
  brew tap | grep -qx "$TAP_NAME" || refuse "$TAP_NAME is not tapped — run: brew tap $TAP_NAME"
}

confirm() {
  local answer=""
  print -n -r -- "$1 [y/N] "
  read -r answer || true
  [[ $answer == y ]]
}

tap_step() {
  local version=$1 url tap sha
  url=$(archive_url "$version")
  need_brew
  tap=$(brew --repository "$TAP_NAME")

  if [[ ! -f $tap/Formula/devpin.rb ]]; then
    sha=$(curl -fsSL "$url" | shasum -a 256) || refuse "cannot download $url"
    sha=${sha%% *}
    print -r -- "The tap has no Formula/devpin.rb yet (the first release). Formula for $version:"
    print
    formula "$version" "$sha"
    print
    print -r -- "Add it to the tap by hand: save the text above as Formula/devpin.rb in a clone of"
    print -r -- "$TAP_NAME, commit it and push."
    return 0
  fi

  if confirm "Update $TAP_NAME/devpin to $version and push the tap?"; then
    brew bump-formula-pr --write-only --commit --url="$url" "$TAP_NAME/devpin" || refuse "brew bump-formula-pr failed"
    git -C "$tap" push || refuse "pushing the tap failed"
  else
    print -r -- "Tap not updated. To do it later: scripts/release.sh tap $version"
  fi
}

release() {
  local version=$1 current today tmp

  valid_version "$version" || refuse "'$version' is not a version — use major.minor.patch, e.g. 1.0.0"
  current=$(current_version)
  version_gt "$version" "$current" || refuse "$version is not above the current version $current"
  [[ -z $(git status --porcelain) ]] || refuse "the working tree is not clean — commit or stash first"
  [[ $(git rev-parse --abbrev-ref HEAD) == main ]] || refuse "not on main — switch with: git switch main"
  git rev-parse -q --verify "refs/tags/v$version" >/dev/null && refuse "tag v$version already exists"
  [[ -n $(unreleased_entries) ]] || refuse "CHANGELOG.md has no '## Unreleased' section with entries"
  need_brew
  if [[ ${DEVPIN_RELEASE_SKIP_TESTS:-} != 1 ]]; then
    scripts/test.sh || refuse "the test suite failed"
  fi

  today=$(date +%Y-%m-%d)
  tmp=$(mktemp) || refuse "cannot create a temporary file"
  sed "s/^DEVPIN_VERSION=.*/DEVPIN_VERSION=\"$version\"/" bin/devpin > "$tmp" && cat "$tmp" > bin/devpin
  awk -v v="$version" -v d="$today" '
    /^## Unreleased[[:space:]]*$/ && !done { print "## Unreleased"; print ""; print "## " v " — " d; done = 1; next }
    { print }' CHANGELOG.md > "$tmp" && cat "$tmp" > CHANGELOG.md
  rm -f "$tmp"

  git add bin/devpin CHANGELOG.md
  git commit -q -m "release: $version" || refuse "commit failed"
  git tag -a "v$version" -m "devpin $version" || refuse "tag failed"
  print -r -- "Committed release: $version and tagged v$version."

  if ! confirm "Push main and v$version to origin?"; then
    print -r -- "Not pushed. To publish by hand:"
    print -r -- "  git push origin main v$version"
    print -r -- "  scripts/release.sh tap $version"
    return 0
  fi
  git push origin main "v$version" || refuse "push failed"
  tap_step "$version"
}

case ${1:-} in
  formula)
    (( $# == 3 )) || usage
    formula "$2" "$3"
    ;;
  tap)
    (( $# == 2 )) && valid_version "$2" || usage
    tap_step "$2"
    ;;
  '')
    usage
    ;;
  *)
    (( $# == 1 )) || usage
    release "$1"
    ;;
esac
