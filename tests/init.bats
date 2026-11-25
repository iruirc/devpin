bats_require_minimum_version 1.5.0
load helpers/common
setup() {
  common_setup
  make_repo "$WORK/repo"
  : > "$WORK/repo/.gitignore"
  git -C "$WORK/repo" commit -q -am empty-ignore
  cd "$WORK/repo"
}

# version_xy: the major.minor of the script's version.
version_xy() { devpin --version | cut -d. -f1,2; }

@test "creates .devpin, config and the gitignore line" {
  run --separate-stderr devpin init
  [ "$status" -eq 0 ]
  assert_contains "$output" "created .devpin/config"
  assert_contains "$output" "added .devpin/*local to .gitignore"
  [ "$(head -n1 .devpin/config)" = "# devpin — https://github.com/iruirc/devpin#config" ]
  grep -qx "requires $(version_xy)" .devpin/config
  grep -qx '# slot runner' .devpin/config
  grep -qx '# packages ../packages/\*' .devpin/config
  grep -qx '# check-ignore Docs/\*\*' .devpin/config
  [ "$(grep -cxF '.devpin/*local' .gitignore)" -eq 1 ]
  [ ! -e .devpin/default ]
  run --separate-stderr devpin get
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "devpin use"
}

@test "appends the gitignore line on its own line" {
  printf 'build/' > .gitignore
  run --separate-stderr devpin init
  [ "$status" -eq 0 ]
  [ "$(cat .gitignore)" = "$(printf 'build/\n.devpin/*local')" ]
}

@test "--default writes a resolved default" {
  run --separate-stderr devpin init --default "Dev Phone"
  [ "$status" -eq 0 ]
  assert_contains "$output" "created .devpin/config, created .devpin/default"
  [ "$(cat .devpin/default)" = "$DEV,id=$DEV_ID" ]
  run --separate-stderr devpin get
  [ "$status" -eq 0 ]
  [ "$output" = "$DEV,id=$DEV_ID" ]
}

@test "--default refuses an ambiguous device before creating anything" {
  run --separate-stderr devpin init --default "Twin Phone"
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "'Twin Phone' names 2 devices"
  [ ! -e .devpin ]
  [ ! -s .gitignore ]
}

@test "never overwrites" {
  mkdir .devpin
  printf '# custom text\nslot runner\n' > .devpin/config
  printf '%s,id=OLDVALUE\n' "$DEV" > .devpin/default
  run --separate-stderr devpin init --default "Dev Phone"
  [ "$status" -eq 0 ]
  assert_contains "$output" "kept .devpin/default"
  refute_contains "$output" "created"
  [ "$(cat .devpin/config)" = "$(printf '# custom text\nslot runner')" ]
  [ "$(cat .devpin/default)" = "$DEV,id=OLDVALUE" ]
}

@test "does not duplicate the gitignore line" {
  run --separate-stderr devpin init
  [ "$status" -eq 0 ]
  run --separate-stderr devpin init
  [ "$status" -eq 0 ]
  assert_contains "$output" "nothing to do"
  [ "$(grep -cxF '.devpin/*local' .gitignore)" -eq 1 ]
}

@test "with packages in config initialises every package without config" {
  local app
  app=$(sibling_tree "$WORK/tree")
  rm -rf "$WORK/tree/packages/pkgA/.devpin" "$WORK/tree/packages/pkgB/.devpin"
  for p in pkgA pkgB; do
    : > "$WORK/tree/packages/$p/.gitignore"
  done
  cd "$app"
  run --separate-stderr devpin init --default "Dev Phone"
  [ "$status" -eq 0 ]
  assert_contains "$output" "pkgA"
  assert_contains "$output" "../packages/pkgB"
  for p in pkgA pkgB; do
    d="$WORK/tree/packages/$p"
    [ -d "$d/.devpin" ]
    [ "$(cat "$d/.devpin/default")" = "$DEV,id=$DEV_ID" ]
    [ "$(grep -cxF '.devpin/*local' "$d/.gitignore")" -eq 1 ]
    [ ! -e "$d/.devpin/config" ]
  done
  [ ! -e "$WORK/tree/packages/notAPackage/.devpin" ]
  # the app's existing config is kept
  [ "$(cat .devpin/config)" = "packages ../packages/*" ]
}

@test "from a subdirectory initialises the git top" {
  mkdir Sources
  cd Sources
  run --separate-stderr devpin init
  [ "$status" -eq 0 ]
  [ -f "$WORK/repo/.devpin/config" ]
  [ ! -e "$WORK/repo/Sources/.devpin" ]
}

@test "--root names the directory to initialise" {
  cd "$WORK"
  run --separate-stderr devpin --root repo init
  [ "$status" -eq 0 ]
  [ -f "$WORK/repo/.devpin/config" ]
}

@test "outside git the working directory is the root" {
  mkdir "$WORK/plain"
  cd "$WORK/plain"
  run --separate-stderr devpin init
  [ "$status" -eq 0 ]
  [ -f "$WORK/plain/.devpin/config" ]
  [ "$(cat .gitignore)" = ".devpin/*local" ]
}

@test "wrong invocation" {
  run --separate-stderr devpin init extra
  [ "$status" -eq 2 ]
  run --separate-stderr devpin init --default
  [ "$status" -eq 2 ]
  run --separate-stderr devpin init --default ""
  [ "$status" -eq 2 ]
  run --separate-stderr devpin init --bogus
  [ "$status" -eq 2 ]
  [ ! -e .devpin ]
}
