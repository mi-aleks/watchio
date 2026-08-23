# Building Watchio

## Requirements

- Apple Silicon Mac
- macOS 14.5 or newer for development
- Xcode 16.2 or newer; Xcode 26 is also continuously built
- Swift 6 language mode

Open `Watchio.xcodeproj`, choose a local development team for both targets, select the Watchio scheme, and run on My Mac. The deployment target is macOS 14.0.

## Why both targets need a team

The app and widget share a team-prefixed App Group. Xcode expands:

```text
$(DEVELOPMENT_TEAM).io.github.mi-aleks.watchio.shared
```

Using the same team on both targets makes their entitlements match without depending on the maintainer's registered group. The collector remains nonsandboxed and the widget remains sandboxed.

## Command-line checks

```bash
make format-check
make test
make ui-test
make build
make check
```

`make build` disables signing and writes Derived Data under `.build/Xcode`. `make ui-test` uses local ad-hoc signing and needs an interactive macOS session. Override `DERIVED_DATA` or `DESTINATION` when needed.

## Demo mode

Add `--demo-data` to the Watchio scheme arguments to avoid showing workstation data. Add `--screenshot-mode` to open the deterministic native menu UI in a centered window for repository screenshots.

## Integration test

```bash
WATCHIO_RUN_INTEGRATION_TESTS=1 swift test --package-path Packages/WatchioCore
```

The opt-in test starts a temporary native listener, expects detection within 15 seconds, terminates it, and expects removal within 15 seconds.
