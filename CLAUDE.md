# CLAUDE.md

devpin is a zsh command-line tool that keeps the device every build, test and run of an Apple project
goes to in one place per repository, `.devpin/`, and prints it as the value of `xcodebuild
-destination`. The app's packages, each its own git repository, follow the app's choice; `devpin check`
fails on a device written into a command anywhere else. See [README.md](README.md).

## Maintainer notes

@../devpin-notes/CLAUDE.private.md

The line above imports the maintainer's private notes: where the work stands and where its documents
live. In a clone without the sibling repositories it resolves to nothing, and nothing here depends on it.
