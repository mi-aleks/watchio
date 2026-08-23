# Contributing to Watchio

Thank you for helping make local development state easier to understand. Watchio accepts bug fixes, detection fixtures, accessibility improvements, documentation, and carefully scoped features.

## Before you start

- Search existing issues and discussions.
- Open an issue before a large behavior, privacy, storage, or architecture change.
- Never add telemetry, outbound application networking, environment collection, raw argument persistence, root access, or process-changing actions.
- Treat false positives as more costly than a candidate entering Review.

By participating, you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Local setup

Requirements are an Apple Silicon Mac, macOS 14.5+, Xcode 16.2+, and Git.

```bash
git clone https://github.com/mi-aleks/watchio.git
cd watchio
make check
```

Choose your Apple development team on both Xcode targets to run the app and widget together. No third-party runtime dependency or project generator is required.

## Change workflow

1. Create a focused branch.
2. Add a fixture or test that describes detection changes.
3. Implement the smallest coherent change.
4. Run `make format` and `make check`.
5. Update public docs and `CHANGELOG.md` when behavior changes.
6. Open a pull request using the template and include screenshots for visible UI changes.

Use deterministic demo data for screenshots. Never publish real usernames, home paths, PIDs, project names, or ports from your workstation.

## Testing expectations

Detection changes should cover positive and false-positive cases, malformed output, and unavailable/timeout behavior where relevant. Storage changes must fail closed for unknown schema versions. Privacy-sensitive changes must include a persisted-output assertion.

The real listener integration test is opt-in locally:

```bash
WATCHIO_RUN_INTEGRATION_TESTS=1 swift test --package-path Packages/WatchioCore
```

## Style and commits

Apple `swift-format` is authoritative. Prefer clear domain terms, small protocol-backed units, and no comments that merely restate code. Commit messages should be imperative and explain one change.

## Developer Certificate of Origin

By contributing, you certify that you have the right to submit the work under this repository's MIT License. Add a sign-off with `git commit -s` when your organization requires DCO tracking.
