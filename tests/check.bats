bats_require_minimum_version 1.5.0
load helpers/common
setup() {
  common_setup
  OPT="-destination"   # built from parts: this suite must not trip a check run on devpin itself
  PLAT="platform="
  SIMVAR="SIMULA""TOR"
  # checkout: the sibling layout, every repository holding a default; files are planted and
  # left untracked.
  APP=$(sibling_tree "$WORK")
  put "$APP" default "$SIM,name=iPhone 17"
  put "$WORK/packages/pkgA" default "$SIM,name=iPhone 17"
  put "$WORK/packages/pkgB" default "$SIM,name=iPhone 17"
  cd "$APP"
}

# plant <file> <line>: appends two filler lines and <line> (the finding is on line 3).
plant() {
  mkdir -p "$(dirname "$1")"
  printf 'first\nsecond\n%s\n' "$2" >> "$1"
}

@test "a clean tree passes" {
  run --separate-stderr devpin check
  [ "$status" -eq 0 ]
  assert_contains "$output" "in 3 repositories"
  [ -z "$stderr" ]
}

@test "finds a destination in Markdown" {
  line="xcodebuild test $OPT '$SIM,name=iPhone 17'"
  plant "$APP/Docs/Guide.md" "$line"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  assert_contains "$output" "✗ MyApp"
  assert_contains "$output" "Docs/Guide.md:3:$line"
  assert_contains "$stderr" "devpin: 1 hardcoded destinations"
  assert_contains "$stderr" "devpin get"
}

@test "finds one in a Makefile" {
  line=$(printf '\txcodebuild test %s "%s,name=iPhone 17"' "$OPT" "$SIM")
  plant "$APP/Makefile" "$line"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  assert_contains "$output" "Makefile:3:$line"
}

@test "finds one in a script" {
  line="  $OPT $SIM,id=ABC-123 \\"
  plant "$APP/run.sh" "$line"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  assert_contains "$output" "run.sh:3:$line"
}

@test "finds one in a package, under the package" {
  line="xcodebuild test $OPT '$DEV,id=00008120-XYZ'"
  plant "$WORK/packages/pkgA/CLAUDE.md" "$line"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  assert_contains "$output" "✗ ../packages/pkgA"
  assert_contains "$output" "../packages/pkgA/CLAUDE.md:3:"
  refute_contains "$output" "✗ MyApp"
}

@test "finds a device inside platform=" {
  line="MY_DESTINATION='$SIM,name=iPhone 17' make test"
  plant "$APP/ci.sh" "$line"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  assert_contains "$output" "ci.sh:3:$line"
}

@test "finds literal assignments" {
  plant "$APP/a.sh" "DESTINATION=\"$SIM,name=iPhone 17\""
  plant "$WORK/packages/pkgA/Makefile" "DEST ?= $SIM,name=iPhone 17"
  plant "$WORK/packages/pkgA/Other.mk" "${SIMVAR} := iPhone 17"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  assert_contains "$output" "a.sh:3:"
  assert_contains "$output" "../packages/pkgA/Makefile:3:"
  assert_contains "$output" "../packages/pkgA/Other.mk:3:"
  assert_contains "$stderr" "3 hardcoded destinations"
}

@test "passes a destination without a device" {
  f="$APP/Docs/Notes.md"
  plant "$f" "xcodebuild $OPT 'generic/${PLAT}iOS'"
  {
    printf '%s\n' "xcodebuild $OPT '${PLAT}macOS,arch=arm64'"
    printf '%s\n' "Measured on iPhone 17 Pro Max: 12 ms per frame."
    printf '%s\n' "xcodebuild $OPT \"\$(devpin get)\""
    printf '%s\n' "  $OPT \"\$DEST\" \\"
    printf '%s\n' "use writes a name as $SIM,id=<UDID>"
    printf '%s\n' "DEST := \$(RUNNER_DEST)"
    printf '%s\n' "DEST=… on the command line overrides it"
  } >> "$f"
  plant "$APP/App/Router.swift" "case .carried(destination: let destination):"
  run --separate-stderr devpin check
  [ "$status" -eq 0 ]
  assert_contains "$output" "No hardcoded destination"
}

@test "skips git-ignored, .git and .devpin files" {
  printf '.build/\nDerivedData/\n' >> "$APP/.gitignore"
  printf '.build/\n' >> "$WORK/packages/pkgA/.gitignore"
  line="xcodebuild $OPT '$SIM,name=iPhone 17'"
  plant "$APP/.build/x.md" "$line"
  plant "$APP/DerivedData/x.md" "$line"
  plant "$APP/.git/notes.md" "$line"
  plant "$WORK/packages/pkgA/.build/checkouts/x.md" "$line"
  put "$APP" local "$DEV,id=$DEV_ID"
  put "$WORK/packages/pkgA" runner.local "$DEV,id=$DEV_ID"
  run --separate-stderr devpin check
  [ "$status" -eq 0 ]
}

@test "reads tracked and untracked files alike" {
  line="xcodebuild $OPT '$SIM,name=iPhone 17'"
  plant "$APP/tracked.md" "$line"
  git -C "$APP" add tracked.md
  git -C "$APP" commit -q -m tracked
  plant "$APP/untracked.md" "$line"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  assert_contains "$output" "tracked.md:3:"
  assert_contains "$output" "untracked.md:3:"
  assert_contains "$stderr" "2 hardcoded destinations"
}

@test "skips binary files" {
  printf 'first\0second\nxcodebuild test %s "%s,name=iPhone 17"\n' "$OPT" "$SIM" > "$APP/blob.bin"
  run --separate-stderr devpin check
  [ "$status" -eq 0 ]
}

@test "honours check-ignore, relative to the root even into a package" {
  put "$APP" config $'packages ../packages/*\ncheck-ignore Docs/**\ncheck-ignore ../packages/pkgA/Docs/**'
  line="xcodebuild $OPT '$SIM,name=iPhone 17'"
  plant "$APP/Docs/x.md" "$line"
  plant "$APP/Docs/sub/y.md" "$line"
  plant "$WORK/packages/pkgA/Docs/x.md" "$line"
  run --separate-stderr devpin check
  [ "$status" -eq 0 ]
  plant "$WORK/packages/pkgB/Docs/x.md" "$line"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  assert_contains "$output" "../packages/pkgB/Docs/x.md:3:"
  assert_contains "$stderr" "1 hardcoded destinations"
}

@test "a directory without Package.swift is not read" {
  plant "$WORK/packages/notAPackage/README.md" "xcodebuild $OPT '$SIM,name=iPhone 17'"
  run --separate-stderr devpin check
  [ "$status" -eq 0 ]
}

@test "outside git walks the tree, skipping build directories" {
  plain="$WORK/plain"
  mkdir -p "$plain/.devpin"
  cd "$plain"
  line="xcodebuild $OPT '$SIM,name=iPhone 17'"
  plant "$plain/.build/x.md" "$line"
  plant "$plain/DerivedData/x.md" "$line"
  plant "$plain/App.xcodeproj/x.md" "$line"
  plant "$plain/.git/x.md" "$line"
  plant "$plain/.devpin/x.md" "$line"
  run --separate-stderr devpin --root "$plain" check
  [ "$status" -eq 0 ]
  assert_contains "$output" "in 1 repositories"
  plant "$plain/Docs/x.md" "$line"
  run --separate-stderr devpin --root "$plain" check
  [ "$status" -eq 1 ]
  assert_contains "$output" "Docs/x.md:3:"
}

@test "nested layout reports a package finding once, under the package" {
  app=$(nested_tree "$WORK/n")
  cd "$app"
  plant "$app/packages/pkgA/x.md" "xcodebuild $OPT '$SIM,name=iPhone 17'"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'x.md:3:')" -eq 1 ]
  assert_contains "$output" "✗ packages/pkgA"
  assert_contains "$output" "packages/pkgA/x.md:3:"
  refute_contains "$output" "✗ MyApp"
  # without the ignore line, git lists packages/pkgA/ as an embedded-repository entry
  grep -vx '/packages/' .gitignore > .gitignore.new
  mv .gitignore.new .gitignore
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'x.md:3:')" -eq 1 ]
  assert_contains "$output" "✗ packages/pkgA"
  refute_contains "$output" "✗ MyApp"
  [ "$(printf '%s\n' "$stderr" | grep -c '1 hardcoded destinations')" -eq 1 ]
}

@test "finds a destination in a file whose path holds a space" {
  line="xcodebuild $OPT '$SIM,name=iPhone 17'"
  plant "$APP/Docs/My Guide.md" "$line"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  assert_contains "$output" "Docs/My Guide.md:3:$line"
}

@test "works in a root whose path holds a space" {
  sp="$WORK/My Projects"
  app=$(sibling_tree "$sp")
  put "$app" default "$SIM,name=iPhone 17"
  cd "$app"
  line="xcodebuild $OPT '$SIM,name=iPhone 17'"
  plant "$sp/packages/pkgB/My Notes.md" "$line"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  assert_contains "$output" "../packages/pkgB/My Notes.md:3:"
}

@test "no colour when stdout is not a terminal" {
  plant "$APP/Docs/Guide.md" "xcodebuild $OPT '$SIM,name=iPhone 17'"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  case $output$stderr in *$'\033['*) false ;; esac
  rm "$APP/Docs/Guide.md"
  run --separate-stderr devpin check
  case $output in *$'\033['*) false ;; esac
}

@test "a glob matching nothing checks the root and warns" {
  put "$APP" config 'packages ../nowhere/*'
  plant "$APP/Docs/Guide.md" "xcodebuild $OPT '$SIM,name=iPhone 17'"
  run --separate-stderr devpin check
  [ "$status" -eq 1 ]
  assert_contains "$stderr" "matches nothing"
  assert_contains "$output" "Docs/Guide.md:3:"
}

@test "check takes no arguments" {
  run --separate-stderr devpin check extra
  [ "$status" -eq 2 ]
  assert_contains "$stderr" "Usage"
}
