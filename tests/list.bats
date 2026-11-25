bats_require_minimum_version 1.5.0
load helpers/common
setup() {
  common_setup
  make_repo "$WORK/repo"
  mkdir "$WORK/repo/.devpin"
  cd "$WORK/repo"
}

row() { printf '  %-36s %s\n' "$1" "$2"; }

@test "lists iOS simulators and phones" {
  run --separate-stderr devpin list
  [ "$status" -eq 0 ]
  expected="$(printf '%s\n' \
    'Simulators:' \
    "$(row 'Test Phone (dup)' "$SIM_ID")" \
    "$(row 'Twin Phone' "$TWIN_ID_1")" \
    "$(row 'Twin Phone' "$TWIN_ID_2")" \
    'Devices:' \
    "$(row 'Other Phone' "$OTHER_DEV_ID")" \
    "$(row 'Dev Phone' "$DEV_ID")")"
  [ "$output" = "$expected" ]
  [ -z "$stderr" ]
  refute_contains "$output" "My Watch"
  refute_contains "$output" "Test Watch"
  refute_contains "$output" "Old Phone"
  refute_contains "$output" "$GONE_ID"
}

@test "without devicectl lists simulators and warns" {
  export STUB_DEVICECTL=
  run --separate-stderr devpin list
  [ "$status" -eq 0 ]
  expected="$(printf '%s\n' \
    'Simulators:' \
    "$(row 'Test Phone (dup)' "$SIM_ID")" \
    "$(row 'Twin Phone' "$TWIN_ID_1")" \
    "$(row 'Twin Phone' "$TWIN_ID_2")")"
  [ "$output" = "$expected" ]
  assert_contains "$stderr" "devicectl unavailable"
  refute_contains "$output" "Devices:"
}

@test "list takes no argument" {
  run --separate-stderr devpin list extra
  [ "$status" -eq 2 ]
  assert_contains "$stderr" "Usage:"
}

@test "list fails when simctl cannot be read" {
  export STUB_SIMCTL=/nonexistent
  run --separate-stderr devpin list
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "devpin: "
}
