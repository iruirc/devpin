bats_require_minimum_version 1.5.0
load helpers/common
setup() {
  common_setup
  A="$SIM,id=$SIM_ID"
  B="$SIM,id=$TWIN_ID_1"
  C="$SIM,id=$TWIN_ID_2"
  make_repo "$WORK/repo"
  cd "$WORK/repo"
}

# expect_value <value>: get succeeds, prints exactly the value, says nothing on stderr.
expect_value() {
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]
  [ "$output" = "$1" ]
  [ -z "$stderr" ]
}

@test "env wins over both files" {
  export DEVPIN_DESTINATION="$A"
  put "$WORK/repo" local "$B"
  put "$WORK/repo" default "$DEFAULT_DEST"
  expect_value "$A"
}

@test "an empty env var reads as absent" {
  export DEVPIN_DESTINATION=""
  put "$WORK/repo" local "$B"
  put "$WORK/repo" default "$DEFAULT_DEST"
  expect_value "$B"
}

@test "local wins over default" {
  put "$WORK/repo" local "$B"
  put "$WORK/repo" default "$DEFAULT_DEST"
  expect_value "$B"
}

@test "default when no local" {
  put "$WORK/repo" local ABSENT
  put "$WORK/repo" default "$DEFAULT_DEST"
  expect_value "$DEFAULT_DEST"
}

@test "a blank local reads as absent" {
  put "$WORK/repo" local $'\n   \n\t'
  put "$WORK/repo" default "$DEFAULT_DEST"
  expect_value "$DEFAULT_DEST"
}

@test "the first non-blank line is read" {
  put "$WORK/repo" local $'\n  \n'"$B"$'\n'"$C"
  put "$WORK/repo" default "$DEFAULT_DEST"
  expect_value "$B"
}

@test "strips CR and surrounding whitespace from a value" {
  put "$WORK/repo" local "  $B"$' \r'
  expect_value "$B"
}

@test "a value file without a trailing newline is read" {
  mkdir -p "$WORK/repo/.devpin"
  printf '%s' "$B" > "$WORK/repo/.devpin/local"
  expect_value "$B"
}

@test "no value is exit 1" {
  put "$WORK/repo" local ABSENT
  put "$WORK/repo" default ABSENT
  mkdir -p "$WORK/repo/.devpin"
  run --separate-stderr devpin get
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  assert_contains "$stderr" ".devpin/default"
  assert_contains "$stderr" "devpin use"
}

@test "get takes no positional argument" {
  put "$WORK/repo" default "$DEFAULT_DEST"
  run --separate-stderr devpin get extra
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  assert_contains "$stderr" "Usage:"
}
