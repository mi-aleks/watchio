# Release process

Watchio `0.1.x` starts as source-only. A release tag does not imply a signed executable.

## Alpha checklist

1. Ensure `main` is clean and CI is green on Xcode 16.2 and Xcode 26.
2. Run `make check` and `make release-build` from a clean clone.
3. Run the opt-in listener integration test on macOS 14 and the current macOS.
4. Verify no privilege prompt or outbound Watchio traffic and record idle CPU/RSS observations.
5. Render deterministic demo screenshots and inspect them for private data.
6. Update `CHANGELOG.md` and version settings together.
7. Create an annotated Git tag named exactly like the version, for example `0.1.0-alpha.1`; sign it when maintainer signing is configured.
8. Publish GitHub release notes that say **source-only**. Do not attach an app bundle or DMG.

## Version locations

- App and widget `MARKETING_VERSION` in `Watchio.xcodeproj/project.pbxproj`
- About UI in `WatchioApp/Views/SettingsView.swift`
- Changelog and README release status
- Snapshot schema only when the persisted contract changes

## Distribution gate

Do not create a DMG, automatic updater, or Homebrew Cask until all of these exist:

- Developer ID Application signing
- Apple notarization and stapling
- Reproducible, least-privilege release workflow
- Provenance/attestation policy and documented key handling
- Clean install/upgrade/uninstall testing
- Security review of the shipping artifact

Hardened Runtime is already enabled in Release as preparation; it is not a substitute for signing and notarization.
