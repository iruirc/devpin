bats_require_minimum_version 1.5.0
load helpers/common
setup() {
  common_setup
  make_repo "$WORK/repo"
  mkdir "$WORK/repo/.devpin"
  cd "$WORK/repo"
}

# expect_written <value>: use succeeded and .devpin/local holds exactly the value.
expect_written() {
  [ "$status" -eq 0 ]
  [ "$(cat .devpin/local)" = "$1" ]
}

# expect_refused: exit 1, nothing written, a reason on stderr, the working tree clean.
expect_refused() {
  [ "$status" -eq 1 ]
  [ ! -e .devpin/local ]
  [ -n "$stderr" ]
  [ -z "$(git status --porcelain)" ]
}

@test "a simulator name writes its UDID" {
  run --separate-stderr devpin use 'Test Phone (dup)'
  expect_written "$SIM,id=$SIM_ID"
  run --separate-stderr devpin get
  [ "$output" = "$SIM,id=$SIM_ID" ]
}

@test "an ambiguous name is refused with candidates" {
  run --separate-stderr devpin use 'Twin Phone'
  expect_refused
  assert_contains "$stderr" "'Twin Phone' names 2 devices"
  assert_contains "$stderr" "$SIM,id=$TWIN_ID_1"
  assert_contains "$stderr" "$SIM,id=$TWIN_ID_2"
}

@test "an unknown name is refused" {
  run --separate-stderr devpin use 'No Such Phone'
  expect_refused
  assert_contains "$stderr" "no available simulator or paired phone 'No Such Phone' — see devpin list"
}

@test "an unavailable simulator is refused" {
  run --separate-stderr devpin use 'Old Phone'
  expect_refused
  run --separate-stderr devpin use "$OLD_ID"
  expect_refused
}

@test "a simulator UDID" {
  run --separate-stderr devpin use "$TWIN_ID_2"
  expect_written "$SIM,id=$TWIN_ID_2"
}

@test "a phone identifier" {
  run --separate-stderr devpin use "$DEV_ID"
  expect_written "$DEV,id=$DEV_ID"
}

@test "a phone name" {
  run --separate-stderr devpin use 'Dev Phone'
  expect_written "$DEV,id=$DEV_ID"
}

@test "an unknown phone identifier is refused" {
  run --separate-stderr devpin use "${DEV_ID}9"
  expect_refused
}

@test "a destination string is written as is" {
  run --separate-stderr devpin use "$DEV,id=$DEV_ID,arch=arm64"
  expect_written "$DEV,id=$DEV_ID,arch=arm64"
}

@test "without devicectl a simulator still resolves" {
  export STUB_DEVICECTL=
  run --separate-stderr devpin use 'Test Phone (dup)'
  expect_written "$SIM,id=$SIM_ID"
}

@test "without devicectl a phone is refused naming devicectl" {
  export STUB_DEVICECTL=
  run --separate-stderr devpin use "$DEV_ID"
  expect_refused
  assert_contains "$stderr" "devicectl unavailable"
}

@test "a non-iOS device is refused" {
  local arg
  for arg in 'My Watch' "$WATCH_ID" 'Test Watch' "$WATCH_SIM_ID"; do
    run --separate-stderr devpin use "$arg"
    expect_refused
  done
}

@test "not a device is a wrong invocation" {
  local arg
  for arg in "" xplatform=iOS platform= $'Test Phone\nx'; do
    run --separate-stderr devpin use "$arg"
    [ "$status" -eq 2 ]
    assert_contains "$stderr" "Usage:"
    [ ! -e .devpin/local ]
  done
}

@test "use without an argument is a wrong invocation" {
  run --separate-stderr devpin use
  [ "$status" -eq 2 ]
  assert_contains "$stderr" "Usage:"
}

@test "works in a root whose path holds a space" {
  make_repo "$WORK/My Projects/MyApp"
  mkdir "$WORK/My Projects/MyApp/.devpin"
  cd "$WORK/My Projects/MyApp"
  run --separate-stderr devpin use 'Dev Phone'
  [ "$status" -eq 0 ]
  [ "$(cat .devpin/local)" = "$DEV,id=$DEV_ID" ]
  run --separate-stderr devpin get
  [ "$output" = "$DEV,id=$DEV_ID" ]
}

@test "use replaces an existing local" {
  put . local "$SIM,name=Test Phone"
  run --separate-stderr devpin use 'Dev Phone'
  expect_written "$DEV,id=$DEV_ID"
}

@test "a written file gets the mode the umask allows" {
  local mask mode
  for mask in 022 077 002; do
    rm -f .devpin/local
    (umask "$mask"; devpin use 'Dev Phone')
    case $mask in 022) mode=644 ;; 077) mode=600 ;; 002) mode=664 ;; esac
    [ "$(stat -f %Lp .devpin/local)" = "$mode" ]
  done
}

@test "a wrong invocation is exit 2 outside any .devpin" {
  mkdir "$WORK/bare"
  cd "$WORK/bare"
  run --separate-stderr devpin use
  [ "$status" -eq 2 ]
  assert_contains "$stderr" "Usage:"
  run --separate-stderr devpin use --bogus Dev
  [ "$status" -eq 2 ]
  run --separate-stderr devpin use --slot
  [ "$status" -eq 2 ]
  run --separate-stderr devpin use --reset Dev
  [ "$status" -eq 2 ]
}

# every_repo <tree-app> <file> <expected>: the file holds the value in app, pkgA, pkgB.
expect_everywhere() {
  local app=$1 file=$2 want=$3 d
  for d in "$app" "$app/../packages/pkgA" "$app/../packages/pkgB"; do
    [ "$(cat "$d/.devpin/$file")" = "$want" ]
  done
}

expect_clean_trees() {
  local d
  for d in "$@"; do
    [ -z "$(git -C "$d" status --porcelain)" ]
  done
}

# tree <root> [nested]: a tree whose app has its .devpin/config committed, so a clean status
# proves devpin wrote only ignored files.
tree() {
  local app
  if [ "${2:-}" = nested ]; then app=$(nested_tree "$1"); else app=$(sibling_tree "$1"); fi
  git -C "$app" add -A
  git -C "$app" commit -q -m config
  printf '%s\n' "$app"
}

R_DEV() { printf '%s,id=%s' "$DEV" "$DEV_ID"; }

@test "writes the root and every package" {
  local app; app=$(tree "$WORK/t")
  cd "$app"
  run --separate-stderr devpin use 'Dev Phone'
  [ "$status" -eq 0 ]
  expect_everywhere "$app" local "$(R_DEV)"
  [ ! -e "$WORK/t/packages/notAPackage/.devpin" ]
  expect_clean_trees "$app" "$WORK/t/packages/pkgA" "$WORK/t/packages/pkgB" "$WORK/t/packages/notAPackage"
  assert_contains "$output" ".devpin/local <- $(R_DEV) (Dev Phone):"
  assert_matches "$output" '^  MyApp +written$'
  assert_matches "$output" '^  \.\./packages/pkgA +written$'
}

@test "nested layout writes every package" {
  local app; app=$(tree "$WORK/t" nested)
  cd "$app"
  run --separate-stderr devpin use 'Dev Phone'
  [ "$status" -eq 0 ]
  [ "$(cat .devpin/local)" = "$(R_DEV)" ]
  [ "$(cat packages/pkgA/.devpin/local)" = "$(R_DEV)" ]
  [ "$(cat packages/pkgB/.devpin/local)" = "$(R_DEV)" ]
  expect_clean_trees "$app" "$app/packages/pkgA" "$app/packages/pkgB"
}

@test "writes the packages when run from a subdirectory" {
  local app; app=$(tree "$WORK/t")
  mkdir -p "$app/Sources"
  cd "$app/Sources"
  run --separate-stderr devpin use 'Dev Phone'
  [ "$status" -eq 0 ]
  expect_everywhere "$app" local "$(R_DEV)"
  [ ! -e "$WORK/t/packages/notAPackage/.devpin" ]
  expect_clean_trees "$app" "$WORK/t/packages/pkgA" "$WORK/t/packages/pkgB"
}

@test "--only-root writes the root alone" {
  local app; app=$(tree "$WORK/t")
  cd "$app"
  run --separate-stderr devpin use --only-root 'Dev Phone'
  [ "$status" -eq 0 ]
  [ "$(cat .devpin/local)" = "$(R_DEV)" ]
  [ ! -e "$WORK/t/packages/pkgA/.devpin/local" ]
  [ ! -e "$WORK/t/packages/pkgB/.devpin/local" ]
}

@test "a package without .devpin gets one" {
  local app; app=$(tree "$WORK/t")
  rm -rf "$WORK/t/packages/pkgB/.devpin"
  cd "$app"
  run --separate-stderr devpin use 'Dev Phone'
  [ "$status" -eq 0 ]
  [ "$(cat "$WORK/t/packages/pkgB/.devpin/local")" = "$(R_DEV)" ]
}

@test "reports a repository it cannot write" {
  local app; app=$(tree "$WORK/t")
  mkdir "$WORK/t/packages/pkgA/.devpin"
  cd "$app"
  chmod a-w "$WORK/t/packages/pkgA/.devpin"
  run --separate-stderr devpin use 'Dev Phone'
  chmod u+w "$WORK/t/packages/pkgA/.devpin"
  [ "$status" -eq 1 ]
  [ "$(cat .devpin/local)" = "$(R_DEV)" ]
  [ "$(cat "$WORK/t/packages/pkgB/.devpin/local")" = "$(R_DEV)" ]
  [ ! -e "$WORK/t/packages/pkgA/.devpin/local" ]
  assert_matches "$output" '^  \.\./packages/pkgA +FAILED to write$'
  assert_contains "$stderr" "devpin: 1 repositories not updated"
  expect_clean_trees "$WORK/t/packages/pkgA"
}

@test "warns where git does not ignore the file" {
  local app; app=$(tree "$WORK/t")
  make_package "$WORK/t/packages/pkgLoose"
  : > "$WORK/t/packages/pkgLoose/.gitignore"
  git -C "$WORK/t/packages/pkgLoose" commit -qam loose
  cd "$app"
  run --separate-stderr devpin use 'Dev Phone'
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c WARNING)" -eq 1 ]
  assert_matches "$output" '^  \.\./packages/pkgLoose +written, WARNING: git does not ignore \.devpin/local here — add \.devpin/\*local to \.gitignore$'
}

@test "use again keeps every tree clean" {
  local app; app=$(tree "$WORK/t")
  cd "$app"
  run --separate-stderr devpin use 'Dev Phone'
  [ "$status" -eq 0 ]
  run --separate-stderr devpin use 'Dev Phone'
  [ "$status" -eq 0 ]
  expect_everywhere "$app" local "$(R_DEV)"
  expect_clean_trees "$app" "$WORK/t/packages/pkgA" "$WORK/t/packages/pkgB"
  [ -z "$(find "$WORK/t" -name '.local.*' -o -name '.*.local.*')" ]
}

@test "an interrupted write leaves no temporary file" {
  local app; app=$(tree "$WORK/t")
  mkdir "$WORK/killbin"
  printf '#!/bin/bash\nkill -TERM "$PPID"\nexit 1\n' > "$WORK/killbin/mv"
  chmod +x "$WORK/killbin/mv"
  cd "$app"
  PATH="$WORK/killbin:$PATH" run --separate-stderr devpin use 'Dev Phone'
  [ "$status" -ne 0 ]
  [ -z "$(find "$WORK/t" -path '*/.devpin/*' -name '*.local.*' -o -path '*/.devpin/*' -name '.local.*')" ]
  [ ! -e .devpin/local ]
  [ ! -e "$WORK/t/packages/pkgA/.devpin/local" ]
  expect_clean_trees "$app" "$WORK/t/packages/pkgA" "$WORK/t/packages/pkgB"
}

@test "slot and reset" {
  local app; app=$(tree "$WORK/t")
  put "$app" config $'packages ../packages/*\nslot runner'
  git -C "$app" commit -qam slot
  cd "$app"
  local A="$SIM,id=$SIM_ID"
  run --separate-stderr devpin use 'Test Phone (dup)'
  [ "$status" -eq 0 ]
  run --separate-stderr devpin use --slot runner 'Dev Phone'
  [ "$status" -eq 0 ]
  assert_contains "$output" ".devpin/runner.local <- $(R_DEV) (Dev Phone):"
  expect_everywhere "$app" runner.local "$(R_DEV)"
  expect_everywhere "$app" local "$A"
  run --separate-stderr devpin get --slot runner
  [ "$output" = "$(R_DEV)" ]

  run --separate-stderr devpin use --slot runner 'Twin Phone'
  [ "$status" -eq 1 ]
  expect_everywhere "$app" runner.local "$(R_DEV)"

  run --separate-stderr devpin use --slot runner --reset
  [ "$status" -eq 0 ]
  assert_contains "$output" ".devpin/runner.local removed:"
  assert_matches "$output" '^  MyApp +removed$'
  [ ! -e .devpin/runner.local ]
  [ ! -e "$WORK/t/packages/pkgA/.devpin/runner.local" ]
  [ ! -e "$WORK/t/packages/pkgB/.devpin/runner.local" ]
  expect_everywhere "$app" local "$A"
  run --separate-stderr devpin get --slot runner
  [ "$output" = "$A" ]

  run --separate-stderr devpin use --slot runner --reset
  [ "$status" -eq 0 ]
  assert_matches "$output" '^  MyApp +absent$'
  assert_matches "$output" '^  \.\./packages/pkgB +absent$'
}

@test "reset of the main slot" {
  local app; app=$(tree "$WORK/t")
  put "$app" default "$DEFAULT_DEST"
  cd "$app"
  run --separate-stderr devpin use 'Dev Phone'
  [ "$status" -eq 0 ]
  run --separate-stderr devpin use --reset
  [ "$status" -eq 0 ]
  [ ! -e .devpin/local ]
  [ ! -e "$WORK/t/packages/pkgA/.devpin/local" ]
  run --separate-stderr devpin get
  [ "$output" = "$DEFAULT_DEST" ]
}

@test "an undeclared slot is refused" {
  local app; app=$(tree "$WORK/t")
  put "$app" config $'packages ../packages/*\nslot runner'
  git -C "$app" commit -qam slot
  cd "$app"
  run --separate-stderr devpin use --slot runer 'Dev Phone'
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "devpin: unknown slot 'runer' — known: runner; check the spelling, or declare it with 'slot runer' in .devpin/config"
  [ -z "$(find "$WORK/t" -name '*local' -path '*/.devpin/*')" ]
}

@test "wrong invocation writes nothing" {
  local app; app=$(tree "$WORK/t")
  put "$app" config $'packages ../packages/*\nslot runner'
  git -C "$app" commit -qam slot
  cd "$app"
  local -a inv=( "" "--reset Dev" "--slot runner --reset Dev" "Dev Phone" "--bogus Dev" "--slot" "--slot Bad_Slot Dev" "--slot --only-root Dev" "--slot -x Dev" )
  local a
  for a in "${inv[@]}"; do
    # shellcheck disable=SC2086
    run --separate-stderr devpin use $a
    [ "$status" -eq 2 ]
    assert_contains "$stderr" "Usage:"
  done
  [ -z "$(find "$WORK/t" -name '*local' -path '*/.devpin/*')" ]
}

@test "booted is refused with its own message" {
  local msg="devpin: 'booted' is refused — with two simulators booted it would pick either; pass a name or UDID (see devpin list)"
  run --separate-stderr devpin use booted
  expect_refused
  assert_contains "$stderr" "$msg"
  local app; app=$(tree "$WORK/t")
  put "$app" config $'packages ../packages/*\nslot runner'
  git -C "$app" commit -qam slot
  cd "$app"
  run --separate-stderr devpin use --slot runner booted
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "$msg"
  [ -z "$(find "$WORK/t" -name '*local' -path '*/.devpin/*')" ]
}

@test "a slot name starting with a hyphen is a wrong invocation" {
  run --separate-stderr devpin use --slot --only-root 'Dev Phone'
  [ "$status" -eq 2 ]
  assert_contains "$stderr" "Usage:"
  [ ! -e .devpin/local ]
}

@test "warns when an environment variable overrides what was written" {
  DEVPIN_DESTINATION="$SIM,name=Other" run --separate-stderr devpin use 'Dev Phone'
  [ "$status" -eq 0 ]
  [ "$(cat .devpin/local)" = "$DEV,id=$DEV_ID" ]
  assert_contains "$stderr" "devpin: warning: DEVPIN_DESTINATION is set and overrides .devpin/local — unset it for the written value to apply"
  # the slot variable of the slot written, not another
  put . config 'slot runner'
  DEVPIN_DESTINATION_RUNNER="$SIM,name=Other" run --separate-stderr devpin use --slot runner 'Dev Phone'
  [ "$status" -eq 0 ]
  [ "$(cat .devpin/runner.local)" = "$DEV,id=$DEV_ID" ]
  assert_contains "$stderr" "devpin: warning: DEVPIN_DESTINATION_RUNNER is set and overrides .devpin/runner.local — unset it for the written value to apply"
  DEVPIN_DESTINATION="$SIM,name=Other" run --separate-stderr devpin use --slot runner 'Dev Phone'
  refute_contains "$stderr" "warning"
  # an empty variable reads as absent; --reset removes, so it has nothing to warn about
  DEVPIN_DESTINATION="" run --separate-stderr devpin use 'Dev Phone'
  refute_contains "$stderr" "warning"
  DEVPIN_DESTINATION="$SIM,name=Other" run --separate-stderr devpin use --reset
  refute_contains "$stderr" "warning"
}
