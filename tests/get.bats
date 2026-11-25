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

@test "an empty slot name is a wrong invocation" {
  put "$WORK/repo" default "$DEFAULT_DEST"
  run --separate-stderr devpin get --slot ''
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  assert_contains "$stderr" "Usage:"
}

# ---- device lists: an id nothing answers to is refused

# expect_refused <args...>: get is refused (exit 1, nothing on stdout); stderr is left in $stderr.
expect_refused() {
  run --separate-stderr devpin get "$@"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "refuses an unknown id from local" {
  put "$WORK/repo" local "$SIM,id=$GONE_ID"
  expect_refused
  assert_contains "$stderr" "devpin: no simulator or paired device with id $GONE_ID on this machine — "
  assert_contains "$stderr" "$SIM,id=$GONE_ID comes from $WORK/repo/.devpin/local"
  assert_contains "$stderr" "devpin use <device>"
  assert_contains "$stderr" "(devpin list shows the devices)"
}

@test "refuses an unknown id from default" {
  put "$WORK/repo" default "$SIM,id=$GONE_ID"
  expect_refused
  assert_contains "$stderr" "id $GONE_ID "
  assert_contains "$stderr" "comes from $WORK/repo/.devpin/default"
  assert_contains "$stderr" "devpin use <device>"
}

@test "refuses an unknown id from env" {
  export DEVPIN_DESTINATION="$SIM,id=$GONE_ID"
  put "$WORK/repo" local "$A"
  expect_refused
  assert_contains "$stderr" "id $GONE_ID "
  assert_contains "$stderr" "comes from DEVPIN_DESTINATION"
  assert_contains "$stderr" "change or unset DEVPIN_DESTINATION"
}

@test "slot refuses an unknown id from its local" {
  put "$WORK/repo" config 'slot runner'
  put "$WORK/repo" runner.local "$SIM,id=$GONE_ID"
  expect_refused --slot runner
  assert_contains "$stderr" "id $GONE_ID "
  assert_contains "$stderr" "comes from $WORK/repo/.devpin/runner.local"
  assert_contains "$stderr" "devpin use --slot runner <device>"
}

@test "slot refuses an unknown id from its env" {
  put "$WORK/repo" config 'slot runner'
  export DEVPIN_DESTINATION_RUNNER="$SIM,id=$GONE_ID"
  expect_refused --slot runner
  assert_contains "$stderr" "comes from DEVPIN_DESTINATION_RUNNER"
  assert_contains "$stderr" "change or unset DEVPIN_DESTINATION_RUNNER"
}

@test "slot falling back to main names both fixes" {
  put "$WORK/repo" config 'slot runner'
  put "$WORK/repo" local "$SIM,id=$GONE_ID"
  expect_refused --slot runner
  assert_contains "$stderr" "id $GONE_ID "
  assert_contains "$stderr" "comes from $WORK/repo/.devpin/local (no runner device of its own)"
  assert_contains "$stderr" "devpin use <device> fixes both, devpin use --slot runner <device> runner alone"
}

@test "slot falling back to an env main" {
  put "$WORK/repo" config 'slot runner'
  export DEVPIN_DESTINATION="$SIM,id=$GONE_ID"
  expect_refused --slot runner
  assert_contains "$stderr" "comes from DEVPIN_DESTINATION (no runner device of its own)"
  assert_contains "$stderr" "change or unset DEVPIN_DESTINATION, or devpin use --slot runner <device> for runner alone"
}

# expect_unavailable <place> <fix> <args...>: the simulator is listed but unavailable.
expect_unavailable() {
  local place=$1 fix=$2
  shift 2
  expect_refused "$@"
  assert_contains "$stderr" "devpin: simulator Old Phone with id $OLD_ID is unavailable (runtime profile not found) — "
  assert_contains "$stderr" "$SIM,id=$OLD_ID comes from $place"
  assert_contains "$stderr" "$fix"
  assert_contains "$stderr" "(devpin list shows the devices)"
}

@test "refuses an unavailable simulator from local" {
  put "$WORK/repo" local "$SIM,id=$OLD_ID"
  expect_unavailable "$WORK/repo/.devpin/local" "devpin use <device>"
}

@test "refuses an unavailable simulator from default" {
  put "$WORK/repo" default "$SIM,id=$OLD_ID"
  expect_unavailable "$WORK/repo/.devpin/default" "devpin use <device>"
}

@test "refuses an unavailable simulator from env" {
  mkdir -p "$WORK/repo/.devpin"
  export DEVPIN_DESTINATION="$SIM,id=$OLD_ID"
  expect_unavailable DEVPIN_DESTINATION "change or unset DEVPIN_DESTINATION"
}

@test "slot refuses an unavailable simulator from its local" {
  put "$WORK/repo" config 'slot runner'
  put "$WORK/repo" runner.local "$SIM,id=$OLD_ID"
  expect_unavailable "$WORK/repo/.devpin/runner.local" "devpin use --slot runner <device>" --slot runner
}

@test "slot refuses an unavailable simulator from its env" {
  put "$WORK/repo" config 'slot runner'
  export DEVPIN_DESTINATION_RUNNER="$SIM,id=$OLD_ID"
  expect_unavailable DEVPIN_DESTINATION_RUNNER "change or unset DEVPIN_DESTINATION_RUNNER" --slot runner
}

@test "slot refuses an unavailable simulator reached via main" {
  put "$WORK/repo" config 'slot runner'
  put "$WORK/repo" local "$SIM,id=$OLD_ID"
  expect_unavailable "$WORK/repo/.devpin/local (no runner device of its own)" \
    "devpin use <device> fixes both, devpin use --slot runner <device> runner alone" --slot runner
}

@test "accepts a known simulator quietly" {
  put "$WORK/repo" local "$A"
  expect_value "$A"
}

@test "accepts a phone only devicectl knows" {
  local R="$DEV,id=$DEV_ID"
  put "$WORK/repo" local "$R"
  expect_value "$R"
}

@test "an id is found wherever it stands in the value" {
  put "$WORK/repo" local "$SIM,id=$TWIN_ID_1,OS=27.0"
  expect_value "$SIM,id=$TWIN_ID_1,OS=27.0"
}

@test "without devicectl warns and prints the value" {
  export STUB_DEVICECTL=
  put "$WORK/repo" local "$SIM,id=$GONE_ID"
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]
  [ "$output" = "$SIM,id=$GONE_ID" ]
  assert_contains "$stderr" "devpin: warning: id $GONE_ID was not found, but xcrun devicectl could not be read — the id was not checked"
}

@test "without devicectl a known simulator passes quietly" {
  export STUB_DEVICECTL=
  put "$WORK/repo" local "$A"
  expect_value "$A"
}

@test "without simctl warns and prints the value" {
  export STUB_SIMCTL="$WORK/none"
  put "$WORK/repo" local "$C"
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]
  [ "$output" = "$C" ]
  assert_contains "$stderr" "warning"
  assert_contains "$stderr" "$TWIN_ID_2"
  assert_contains "$stderr" "xcrun simctl could not be read"
  refute_contains "$stderr" "devicectl"
}

@test "without simctl a simulator devicectl lists passes" {
  export STUB_SIMCTL="$WORK/none"
  put "$WORK/repo" local "$A"
  expect_value "$A"
}

@test "with neither list both are named" {
  export STUB_SIMCTL="$WORK/none" STUB_DEVICECTL=
  put "$WORK/repo" local "$SIM,id=$GONE_ID"
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]
  [ "$output" = "$SIM,id=$GONE_ID" ]
  assert_contains "$stderr" "xcrun simctl and xcrun devicectl could not be read"
}

@test "does not match an id by prefix" {
  put "$WORK/repo" local "$SIM,id=$GONE_ID"
  expect_refused
  assert_contains "$stderr" "no simulator or paired device with id $GONE_ID"
  refute_contains "$stderr" "Test Phone"
}

@test "a value without id= calls no xcrun" {
  export XCRUN_RECORD="$WORK/rec"
  put "$WORK/repo" config 'slot runner'
  put "$WORK/repo" default "$DEFAULT_DEST"
  expect_value "$DEFAULT_DEST"
  expect_slot_value "$DEFAULT_DEST"
  [ "$(xcrun_calls simctl)" -eq 0 ]
  [ "$(xcrun_calls devicectl)" -eq 0 ]
}

@test "asks devicectl only when simctl does not know the id" {
  export XCRUN_RECORD="$WORK/rec"
  put "$WORK/repo" local "$A"
  expect_value "$A"
  [ "$(xcrun_calls simctl)" -eq 1 ]
  [ "$(xcrun_calls devicectl)" -eq 0 ]
  : > "$WORK/rec"
  put "$WORK/repo" local "$DEV,id=$DEV_ID"
  expect_value "$DEV,id=$DEV_ID"
  [ "$(xcrun_calls simctl)" -eq 1 ]
  [ "$(xcrun_calls devicectl)" -eq 1 ]
}

@test "a refused id reads each list once" {
  export XCRUN_RECORD="$WORK/rec"
  put "$WORK/repo" local "$SIM,id=$GONE_ID"
  expect_refused
  [ "$(xcrun_calls simctl)" -eq 1 ]
  [ "$(xcrun_calls devicectl)" -eq 1 ]
}
