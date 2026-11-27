bats_require_minimum_version 1.5.0
load helpers/common
setup() {
  common_setup
  D="$DEFAULT_DEST"
  GONE="$SIM,id=$GONE_ID"
  A="$SIM,id=$SIM_ID"
  R="$DEV,id=$DEV_ID"
}

# row <label> <slot> <source> <described>: one data row, as show prints it.
row() { printf '%-24s %-10s %-8s %s\n' "$1" "$2" "$3" "$4"; }
# note <label> <text>: one special line (no data).
note() { printf '%-24s %s\n' "$1" "$2"; }
# lines <line>...: joins its arguments with newlines, as bats holds $output.
lines() { local IFS=$'\n'; printf '%s' "$*"; }

# show_tree: the sibling layout with every kind of repository; prints the app path.
show_tree() {
  local app
  app=$(sibling_tree "$WORK")
  put "$app" config $'packages ../packages/*\nslot runner'
  put "$app" local "$GONE"
  put "$app" default "$D"
  put "$WORK/packages/pkgA" local "$A"
  put "$WORK/packages/pkgA" default "$D"
  put "$WORK/packages/pkgB" default "$D"
  put "$WORK/packages/pkgB" runner.local "$R"
  make_package "$WORK/packages/pkgC"
  printf '%s\n' "$app"
}

@test "show from the root and get in a package agree on an undeclared slot" {
  app=$(show_tree)
  cd "$app"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  assert_contains "$output" "$(row ../packages/pkgA runner main "$A (Test Phone (dup))")"
  cd "$WORK/packages/pkgA"
  run --separate-stderr devpin get --slot runner
  [ "$status" -eq 0 ]
  [ "$output" = "$A" ]
}

@test "reports every repository and slot" {
  app=$(show_tree)
  cd "$app"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  expected=$(lines \
    "$(row MyApp main local "$GONE (unknown id)")" \
    "$(row MyApp runner main "$GONE (unknown id)")" \
    "$(row ../packages/pkgA main local "$A (Test Phone (dup))")" \
    "$(row ../packages/pkgA runner main "$A (Test Phone (dup))")" \
    "$(row ../packages/pkgB main default "$D")" \
    "$(row ../packages/pkgB runner local "$R (Dev Phone)")" \
    "$(note ../packages/pkgC '(no .devpin/)')" \
    "$(note ../packages/notAPackage '(no Package.swift — skipped)')")
  [ "$output" = "$expected" ]
}

@test "env applies to every repository" {
  app=$(show_tree)
  cd "$app"
  export DEVPIN_DESTINATION="$R" DEVPIN_DESTINATION_RUNNER="$A"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  expected=$(lines \
    "$(row MyApp main env "$R (Dev Phone)")" \
    "$(row MyApp runner env "$A (Test Phone (dup))")" \
    "$(row ../packages/pkgA main env "$R (Dev Phone)")" \
    "$(row ../packages/pkgA runner env "$A (Test Phone (dup))")" \
    "$(row ../packages/pkgB main env "$R (Dev Phone)")" \
    "$(row ../packages/pkgB runner env "$A (Test Phone (dup))")" \
    "$(note ../packages/pkgC '(no .devpin/)')" \
    "$(note ../packages/notAPackage '(no Package.swift — skipped)')")
  [ "$output" = "$expected" ]
}

@test "without devicectl says so" {
  app=$(show_tree)
  cd "$app"
  export STUB_DEVICECTL=
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  assert_contains "$output" "$(row MyApp main local "$GONE (unknown to simctl, devicectl unavailable)")"
  assert_contains "$output" "$(row MyApp runner main "$GONE (unknown to simctl, devicectl unavailable)")"
  assert_contains "$output" "$(row ../packages/pkgA main local "$A (Test Phone (dup))")"
  assert_contains "$output" "$(row ../packages/pkgB runner local "$R (unknown to simctl, devicectl unavailable)")"
}

@test "without simctl says so" {
  app=$(show_tree)
  cd "$app"
  export STUB_SIMCTL="$WORK/missing.txt"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  assert_contains "$output" "$(row MyApp main local "$GONE (unknown to devicectl, simctl unavailable)")"
  assert_contains "$output" "$(row ../packages/pkgB runner local "$R (Dev Phone)")"
}

@test "without simctl and devicectl says so" {
  app=$(show_tree)
  cd "$app"
  export STUB_SIMCTL="$WORK/missing.txt" STUB_DEVICECTL=
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  assert_contains "$output" "$(row MyApp main local "$GONE (simctl and devicectl unavailable)")"
  assert_contains "$output" "$(row ../packages/pkgA main local "$A (simctl and devicectl unavailable)")"
  assert_contains "$output" "$(row ../packages/pkgB main default "$D")"
}

@test "marks an unavailable simulator" {
  app=$(show_tree)
  put "$app" local "$SIM,id=$OLD_ID"
  put "$app" runner.local "$SIM,id=$OLD_ID"
  cd "$app"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  assert_contains "$output" "$(row MyApp main local "$SIM,id=$OLD_ID (Old Phone) (unavailable, runtime profile not found)")"
  assert_contains "$output" "$(row MyApp runner local "$SIM,id=$OLD_ID (Old Phone) (unavailable, runtime profile not found)")"
}

@test "shows a missing value as a dash" {
  make_repo "$WORK/repo"
  put "$WORK/repo" config 'slot runner'
  put "$WORK/repo" runner.default "$D"
  cd "$WORK/repo"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  expected=$(lines \
    "$(row repo main missing -)" \
    "$(row repo runner default "$D")")
  [ "$output" = "$expected" ]
}

@test "without packages shows the root" {
  make_repo "$WORK/repo"
  put "$WORK/repo" default "$D"
  cd "$WORK/repo"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$output" = "$(row repo main default "$D")" ]
}

@test "a packages glob matching nothing warns" {
  make_repo "$WORK/repo"
  put "$WORK/repo" config 'packages ../nowhere/*'
  put "$WORK/repo" default "$D"
  cd "$WORK/repo"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ "$output" = "$(row repo main default "$D")" ]
  [ "$stderr" = "devpin: warning: packages ../nowhere/* matches nothing" ]
}

@test "nested layout" {
  app=$(nested_tree "$WORK")
  put "$app" default "$D"
  put "$app/packages/pkgA" default "$D"
  put "$app/packages/pkgB" default "$D"
  cd "$app"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  expected=$(lines \
    "$(row MyApp main default "$D")" \
    "$(row packages/pkgA main default "$D")" \
    "$(row packages/pkgB main default "$D")")
  [ "$output" = "$expected" ]
}

@test "works from a subdirectory of the app" {
  app=$(show_tree)
  mkdir -p "$app/sub"
  cd "$app/sub"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  assert_contains "$output" "$(row ../packages/pkgA main local "$A (Test Phone (dup))")"
}

@test "loads each device list once and only for ids" {
  app=$(show_tree)
  cd "$app"
  export XCRUN_RECORD="$WORK/xcrun.log"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ "$(xcrun_calls simctl)" -eq 1 ]
  [ "$(xcrun_calls devicectl)" -eq 1 ]

  rm -f "$XCRUN_RECORD"
  make_repo "$WORK/plain"
  put "$WORK/plain" default "$D"
  cd "$WORK/plain"
  run --separate-stderr devpin show
  [ "$status" -eq 0 ]
  [ "$(xcrun_calls simctl)" -eq 0 ]
  [ "$(xcrun_calls devicectl)" -eq 0 ]
}

@test "show takes no argument" {
  make_repo "$WORK/repo"
  put "$WORK/repo" default "$D"
  cd "$WORK/repo"
  run --separate-stderr devpin show x
  [ "$status" -eq 2 ]
  assert_contains "$stderr" "Usage:"
}
