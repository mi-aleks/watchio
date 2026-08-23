# Troubleshooting

## The app runs but no menu appears

Watchio is a menu bar accessory (`LSUIElement`). Look for `w:` in the menu bar. If macOS hides menu extras because of limited space, close another menu bar item temporarily.

## The widget says Open Watchio or Offline

Open the menu bar app and wait for a scan. Widgets read snapshots and do not run the collector. WidgetKit may delay refreshes even after Watchio requests one.

## A known service is missing

1. Confirm it has been stable for at least three seconds.
2. Add its parent project folder under Settings → Detection.
3. Confirm its runtime toggle is enabled.
4. Check Settings → Review for a 40–59 confidence candidate.
5. Check Health for a degraded `lsof` or Docker source.

Watchio intentionally does not inspect raw arguments or environments, so unusual launchers may need project or listener evidence.

## A non-development process appears

Open its detail and note the non-sensitive evidence. File a sanitized false-positive report with runtime, evidence, and whether it had a project marker/listener. Do not paste full paths, arguments, environments, or proprietary names.

## Docker is degraded

Watchio searches common Apple Silicon and Docker Desktop CLI locations and uses the CLI's active context only when it resolves to a local Unix socket. Confirm `docker context inspect` and `docker ps` work in Terminal. Remote contexts are intentionally refused. Compose labels are required; standalone containers are not shown in this alpha.

## The app and widget do not share data in Xcode

Select the same Apple development team for both targets, clean the build folder, delete the old widget from the desktop, run Watchio again, and re-add the widget. Confirm the expanded App Group is identical in both built entitlements.

## Unsigned command-line build fails

Run `xcode-select -p`, confirm Xcode 16.2+, accept Xcode's license if required, then run `make check`. CI uses explicit Xcode application paths documented in `.github/workflows/ci.yml`.
