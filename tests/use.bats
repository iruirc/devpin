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
  for arg in "" booted xplatform=iOS platform= $'Test Phone\nx'; do
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

@test "an interrupted write leaves no temporary file" {
  mkdir "$WORK/slowbin"
  printf '#!/bin/sh\nsleep 2\nexec /bin/mv "$@"\n' > "$WORK/slowbin/mv"
  chmod +x "$WORK/slowbin/mv"
  PATH="$WORK/slowbin:$PATH" devpin use 'Dev Phone' 2>/dev/null &
  local pid=$! n=0
  while [ -z "$(ls -A .devpin | grep '^\.local\.')" ] && [ $n -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
  [ -n "$(ls -A .devpin | grep '^\.local\.')" ]
  kill -TERM "$pid"
  local rc=0
  wait "$pid" || rc=$?
  [ "$rc" -eq 143 ]
  [ -z "$(ls -A .devpin | grep '^\.local')" ]
}
