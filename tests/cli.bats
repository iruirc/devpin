bats_require_minimum_version 1.5.0
load helpers/common
setup() { common_setup; }

@test "--version prints the version" {
  run --separate-stderr devpin --version
  [ "$status" -eq 0 ]
  assert_matches "$output" '^[0-9]+\.[0-9]+\.[0-9]+$'
  [ "$output" = "$(sed -n 's/^DEVPIN_VERSION="\(.*\)"$/\1/p' "$REPO/bin/devpin")" ]
}

@test "no command is a wrong invocation" {
  run --separate-stderr devpin
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  assert_contains "$stderr" "Usage:"
}

@test "unknown command is a wrong invocation" {
  run --separate-stderr devpin bogus
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  assert_contains "$stderr" "Usage:"
}

@test "--root without a value is a wrong invocation" {
  run --separate-stderr devpin --root
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  assert_contains "$stderr" "Usage:"
}

@test "--help prints usage on stdout" {
  run --separate-stderr devpin --help
  [ "$status" -eq 0 ]
  assert_contains "$output" "Usage:"
  local c
  for c in get show list use init check; do
    assert_contains "$output" "$c"
  done
}

@test "the stub answers only simctl and devicectl" {
  run --separate-stderr xcrun foo
  [ "$status" -eq 64 ]
}

@test "the stub lists simulators and honours the available filter" {
  run --separate-stderr xcrun simctl list devices
  [ "$status" -eq 0 ]
  assert_contains "$output" "$OLD_ID"
  run --separate-stderr xcrun simctl list devices available
  [ "$status" -eq 0 ]
  refute_contains "$output" "$OLD_ID"
  assert_contains "$output" "$SIM_ID"
}

@test "the helpers build repositories and record xcrun calls" {
  local app
  app="$(sibling_tree "$WORK/s")"
  [ -f "$app/.devpin/config" ]
  [ -f "$WORK/s/packages/pkgA/Package.swift" ]
  [ ! -f "$WORK/s/packages/notAPackage/Package.swift" ]
  app="$(nested_tree "$WORK/n")"
  [ -d "$app/packages/pkgB/.git" ]
  put "$app" slot-x "$DEFAULT_DEST"
  [ -f "$app/.devpin/slot-x" ]
  put "$app" slot-x ABSENT
  [ ! -e "$app/.devpin/slot-x" ]
  export XCRUN_RECORD="$WORK/record"
  xcrun simctl list devices >/dev/null
  [ "$(xcrun_calls simctl)" -eq 1 ]
  [ "$(xcrun_calls devicectl)" -eq 0 ]
}
