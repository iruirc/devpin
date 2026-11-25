bats_require_minimum_version 1.5.0
load helpers/common
setup() { common_setup; }

@test "finds .devpin in the working directory" {
  make_repo "$WORK/repo"
  put "$WORK/repo" default "$DEFAULT_DEST"
  cd "$WORK/repo"
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_DEST" ]
  [ -z "$stderr" ]
}

@test "finds the root from a subdirectory" {
  make_repo "$WORK/repo"
  put "$WORK/repo" default "$DEFAULT_DEST"
  mkdir -p "$WORK/repo/Sources/Feature"
  cd "$WORK/repo/Sources/Feature"
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_DEST" ]
  [ -z "$stderr" ]
}

@test "stops at the top of the git repository" {
  mkdir -p "$WORK/outer"
  put "$WORK/outer" default "$DEFAULT_DEST"
  make_repo "$WORK/outer/app"
  cd "$WORK/outer/app"
  run --separate-stderr devpin get
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  assert_contains "$stderr" "$WORK/outer/app"
  assert_contains "$stderr" "devpin init"
}

@test "a package never reads the app's .devpin" {
  local app
  app="$(nested_tree "$WORK")"
  put "$app" default "$DEFAULT_DEST"
  [ ! -e "$app/packages/pkgA/.devpin" ]
  cd "$app/packages/pkgA"
  run --separate-stderr devpin get
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  assert_contains "$stderr" "devpin init"
}

@test "--root names the root" {
  make_repo "$WORK/repo"
  put "$WORK/repo" default "$DEFAULT_DEST"
  cd "$WORK"
  run --separate-stderr devpin --root "$WORK/repo" get
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_DEST" ]
  [ -z "$stderr" ]
}

@test "--root without .devpin is refused" {
  make_repo "$WORK/repo"
  cd "$WORK"
  run --separate-stderr devpin --root "$WORK/repo" get
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  assert_contains "$stderr" "$WORK/repo"
  assert_contains "$stderr" ".devpin"
}

@test "works through a symlinked path" {
  make_repo "$WORK/repo"
  put "$WORK/repo" default "$DEFAULT_DEST"
  ln -s "$WORK/repo" "$WORK/link"
  cd "$WORK/link"
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]
  [ "$output" = "$DEFAULT_DEST" ]
  [ -z "$stderr" ]
}
