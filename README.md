# devpin

One place per repository for the device every build, test and run of an Apple project goes to.

devpin keeps the choice in a `.devpin/` directory at the repository root and prints it as the value of
`xcodebuild -destination`:

```sh
xcodebuild test -scheme MyApp -destination "$(devpin get)"
```

- **one clone, its own device** — a machine's choice lives in a git-ignored file, the project's default
  in a committed one;
- **packages follow the app** — `devpin use "iPhone 17 Pro"` writes the choice into the app and every
  package listed in its `config`, beside it (`../packages/*`) or inside it (`packages/*`);
- **named slots** — a second device, for an on-device test runner for example, falling back to the main
  one when not set;
- **a hardcode check** — `devpin check` fails on a device written into a command anywhere else.

One zsh script, macOS only, installed with Homebrew.

**Status:** design. There is no code yet.

## License

MIT — see [LICENSE](LICENSE).
