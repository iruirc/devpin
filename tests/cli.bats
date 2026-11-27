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

@test "get, init and list take no --packages" {
  local app
  app=$(sibling_tree "$WORK")
  cd "$app"
  local c
  for c in get init list; do
    run --separate-stderr devpin "$c" --packages "$WORK/packages/*"
    [ "$status" -eq 2 ]
    assert_contains "$stderr" "Usage:"
  done
  [ ! -e "$WORK/packages/pkgA/.devpin" ]
}

@test "--packages needs an argument" {
  local app
  app=$(sibling_tree "$WORK")
  cd "$app"
  local c
  for c in show check use; do
    run --separate-stderr devpin "$c" --packages
    [ "$status" -eq 2 ]
    assert_contains "$stderr" "Usage:"
    run --separate-stderr devpin "$c" --packages ""
    [ "$status" -eq 2 ]
  done
  run --separate-stderr devpin use --packages 'Dev Phone'
  [ "$status" -eq 2 ]
  [ ! -e "$app/.devpin/local" ]
}

@test "init keeps the packages of config, whatever DEVPIN_PACKAGES says" {
  local app
  app=$(sibling_tree "$WORK")
  make_package "$WORK/other/Core"
  cd "$app"
  DEVPIN_PACKAGES="$WORK/other/*" run --separate-stderr devpin init
  [ "$status" -eq 0 ]
  [ -d "$WORK/packages/pkgA/.devpin" ]
  [ ! -e "$WORK/other/Core/.devpin" ]
  refute_contains "$stderr" "packages:"
}
