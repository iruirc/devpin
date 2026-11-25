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

# ---- slots

# slot_setup: lays out the slot table; arguments are the env main, env runner, local, default,
# runner.local and runner.default (ABSENT or empty = not set).
slot_setup() {
  put "$WORK/repo" config 'slot runner'
  [ "$1" = ABSENT ] || export DEVPIN_DESTINATION="$1"
  [ "$2" = ABSENT ] || export DEVPIN_DESTINATION_RUNNER="$2"
  put "$WORK/repo" local "$3"
  put "$WORK/repo" default "$4"
  put "$WORK/repo" runner.local "$5"
  put "$WORK/repo" runner.default "$6"
}

expect_slot_value() {
  run --separate-stderr devpin get --slot "${2:-runner}"
  [ "$status" -eq 0 ]
  [ "$output" = "$1" ]
  [ -z "$stderr" ]
}

@test "slot env wins" {
  local R="$DEV,id=$DEV_ID" F="$DEV,id=$OTHER_DEV_ID"
  slot_setup ABSENT "$R" "$B" "$DEFAULT_DEST" "$F" ABSENT
  expect_slot_value "$R"
  expect_value "$B"
}

@test "slot local wins over main" {
  local F="$DEV,id=$OTHER_DEV_ID"
  slot_setup "$A" ABSENT "$B" "$DEFAULT_DEST" "$F" ABSENT
  expect_slot_value "$F"
}

@test "slot default wins over main" {
  local F="$DEV,id=$OTHER_DEV_ID"
  slot_setup ABSENT ABSENT "$B" "$DEFAULT_DEST" ABSENT "$F"
  expect_slot_value "$F"
}

@test "slot local wins over slot default" {
  local R="$DEV,id=$DEV_ID" F="$DEV,id=$OTHER_DEV_ID"
  slot_setup ABSENT ABSENT "$B" "$DEFAULT_DEST" "$R" "$F"
  expect_slot_value "$R"
}

@test "slot falls back to main" {
  slot_setup ABSENT ABSENT "$B" "$DEFAULT_DEST" ABSENT ABSENT
  expect_slot_value "$B"
}

@test "slot falls back to main through the main env var" {
  slot_setup "$A" ABSENT "$B" "$DEFAULT_DEST" ABSENT ABSENT
  expect_slot_value "$A"
}

@test "a blank slot file falls back to main" {
  slot_setup "$A" ABSENT ABSENT "$DEFAULT_DEST" $' \n\t' ABSENT
  expect_slot_value "$A"
}

@test "an empty slot env var reads as absent" {
  slot_setup ABSENT "" "$B" "$DEFAULT_DEST" ABSENT ABSENT
  expect_slot_value "$B"
}

@test "slot without main is exit 1" {
  slot_setup ABSENT ABSENT ABSENT ABSENT ABSENT ABSENT
  run --separate-stderr devpin get --slot runner
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  assert_contains "$stderr" "runner"
  assert_contains "$stderr" "devpin use"
}

@test "env name upper-cases and maps - to _" {
  local R="$DEV,id=$DEV_ID"
  put "$WORK/repo" config 'slot ui-runner'
  put "$WORK/repo" default "$DEFAULT_DEST"
  export DEVPIN_DESTINATION_UI_RUNNER="$R"
  expect_slot_value "$R" ui-runner
}

@test "a slot name may hold digits" {
  put "$WORK/repo" config 'slot ui2'
  put "$WORK/repo" ui2.default "$B"
  expect_slot_value "$B" ui2
}

@test "a slot known only by its file is valid" {
  local F="$DEV,id=$OTHER_DEV_ID"
  put "$WORK/repo" runner.local "$F"
  expect_slot_value "$F"
  put "$WORK/repo" runner.local ABSENT
  put "$WORK/repo" runner.default "$F"
  expect_slot_value "$F"
}

@test "an undeclared slot is refused listing the known ones" {
  put "$WORK/repo" config $'slot runner\nslot ui'
  put "$WORK/repo" default "$DEFAULT_DEST"
  put "$WORK/repo" other.local "$B"
  run --separate-stderr devpin get --slot runer
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  assert_contains "$stderr" "unknown slot 'runer'"
  assert_contains "$stderr" "known: other, runner, ui;"
  assert_contains "$stderr" "slot runer"
}

@test "an undeclared slot with none known says so" {
  put "$WORK/repo" default "$DEFAULT_DEST"
  run --separate-stderr devpin get --slot runner
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "known: none;"
}

@test "a malformed slot name is a wrong invocation" {
  put "$WORK/repo" default "$DEFAULT_DEST"
  run --separate-stderr devpin get --slot Runner
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  assert_contains "$stderr" "Usage:"
  run --separate-stderr devpin get --slot
  [ "$status" -eq 2 ]
  assert_contains "$stderr" "Usage:"
  run --separate-stderr devpin get --slot 'a b'
  [ "$status" -eq 2 ]
}
