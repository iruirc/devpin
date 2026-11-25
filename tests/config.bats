bats_require_minimum_version 1.5.0
load helpers/common
setup() {
  common_setup
  make_repo "$WORK/repo"
  put "$WORK/repo" default "$DEFAULT_DEST"
  cd "$WORK/repo"
}

# write_config <text>: replaces .devpin/config with the text as given.
write_config() {
  mkdir -p "$WORK/repo/.devpin"
  printf '%s\n' "$1" > "$WORK/repo/.devpin/config"
}

# expect_config_error <reason>: get refuses, names the config line and the reason.
expect_config_error() {
  run --separate-stderr devpin get
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  assert_contains "$stderr" "devpin: $WORK/repo/.devpin/config:$1"
}

@test "comments and blank lines are skipped" {
  write_config $'# a comment\n\n   \nslot runner  # trailing\n'
  run --separate-stderr devpin get --slot runner
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_DEST" ]
  [ -z "$stderr" ]
}

@test "a config with CRLF line endings is read" {
  printf 'slot runner\r\nrequires 0.0\r\n' > "$WORK/repo/.devpin/config"
  run --separate-stderr devpin get --slot runner
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_DEST" ]
  [ -z "$stderr" ]
}

@test "duplicate slot lines are fine" {
  write_config $'slot runner\nslot runner'
  run --separate-stderr devpin get --slot runner
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_DEST" ]
}

@test "an unknown entry is an error naming the line" {
  write_config $'# first\nslot runner\npakages x'
  expect_config_error "3: unknown entry 'pakages'"
}

@test "slot rejects a bad name" {
  write_config $'\nslot Runner'
  expect_config_error "2: "
  assert_contains "$stderr" "Runner"
}

@test "slot rejects a missing or doubled name" {
  write_config $'slot'
  expect_config_error "1: "
  write_config $'slot a b'
  expect_config_error "1: "
}

@test "requires rejects 1" {
  write_config $'slot runner\nrequires 1'
  expect_config_error "2: "
}

@test "requires rejects 1.x" {
  write_config $'requires 1.x'
  expect_config_error "1: "
}

@test "packages needs an argument" {
  write_config $'slot runner\n\npackages   # nothing'
  expect_config_error "3: "
}

@test "check-ignore needs an argument" {
  write_config $'check-ignore'
  expect_config_error "1: "
}

@test "two requires lines" {
  write_config $'requires 0.0\nslot runner\nrequires 0.1'
  expect_config_error "3: "
}

@test "requires older than devpin passes" {
  write_config 'requires 0.0'
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_DEST" ]
  [ -z "$stderr" ]
}

@test "requires equal to devpin passes" {
  write_config 'requires 0.0.0'
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]
}

@test "requires newer than devpin refuses" {
  write_config $'slot runner\nrequires 999.0'
  run --separate-stderr devpin get
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  assert_contains "$stderr" "$WORK/repo/.devpin/config:2:"
  assert_contains "$stderr" "requires devpin 999.0"
  assert_contains "$stderr" "brew upgrade devpin"
}

@test "requires newer wins over an unknown entry in a later line" {
  write_config $'requires 999.0\nsome-future-entry x'
  run --separate-stderr devpin get
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "requires devpin 999.0"
}

@test "requires compares numerically, not as text" {
  mkdir -p "$WORK/v"
  sed 's/^DEVPIN_VERSION=.*/DEVPIN_VERSION="1.9.0"/' "$REPO/bin/devpin" > "$WORK/v/devpin"
  chmod +x "$WORK/v/devpin"
  PATH="$WORK/v:$PATH"
  run devpin --version
  [ "$output" = "1.9.0" ]

  write_config 'requires 1.10'
  run --separate-stderr devpin get
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "requires devpin 1.10"

  write_config 'requires 1.9'
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]

  write_config 'requires 1.9.1'
  run --separate-stderr devpin get
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "requires devpin 1.9.1"
}

@test "a missing config is an empty config" {
  [ ! -e "$WORK/repo/.devpin/config" ]
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_DEST" ]
  [ -z "$stderr" ]
}

@test "a config error also stops get --slot" {
  write_config 'bogus'
  run --separate-stderr devpin get --slot runner
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "config:1: unknown entry 'bogus'"
}
