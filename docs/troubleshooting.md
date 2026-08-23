# Troubleshooting

## The app runs but no menu appears

Watchio is a menu bar accessory (`LSUIElement`). Look for `w:` in the menu bar. If macOS hides menu extras because of limited space, close another menu bar item temporarily.

## The widget says Open Watchio or Offline

Open the menu bar app and wait for a scan. Widgets read snapshots and do not run the collector. WidgetKit may delay refreshes even after Watchio requests one.

## Resource alert or notification does not appear

- Keep the menu bar collector running for at least three scans; the widget extension does not sample processes itself.
- Energy alerts only apply while macOS reports that the Mac is drawing from its battery.
- Check Settings → Widget for the memory/CPU thresholds and notification toggle.
- If macOS permission was denied or later revoked, re-enable Watchio in System Settings → Notifications.
- WidgetKit may delay rendering a changed snapshot; the menu bar Health view is the freshest source.

## A known service is missing

1. Confirm it has been stable for at least three seconds.
2. Add its parent project folder under Settings → Detection.
3. Confirm its runtime toggle is enabled.
4. Check Settings → Review for a 40–59 confidence candidate.
5. Check Health for a degraded `lsof` or Docker source.

Watchio intentionally does not inspect raw arguments or environments, so unusual launchers may need project or listener evidence.

## A known AI tool is missing

1. Confirm AI activity is enabled under Settings → Detection.
2. Confirm the process has been stable for at least three seconds.
3. Confirm the executable retains a supported name from [Detection](detection.md#ai-activity-rules).
4. Add the project parent under Settings → Detection if the installation path is not recognized.

Script-based tools sometimes appear to macOS only as `node` or `python`. Watchio does not inspect
arguments to guess their identity, so those processes intentionally remain hidden. Likewise, a
desktop tool may host several internal tasks in one process; Watchio reports the host activity and
does not read its session database to enumerate conversations.

## A non-development process appears

Open its detail and note the non-sensitive evidence. File a sanitized false-positive report with runtime, evidence, and whether it had a project marker/listener. Do not paste full paths, arguments, environments, or proprietary names.

## Stop tree was refused or reported survivors

Watchio refuses a stop when the PID disappeared or changed identity, belongs to another user,
owns the running Watchio instance, cannot be re-inventoried, or keeps changing descendants while
frozen. Start a new scan and inspect the row again; do not retry against a copied PID.

A survivor means macOS still reported a verified process after `SIGKILL`. The process may be in an
uninterruptible kernel wait. An external supervisor may also create a new replacement with a new
identity after Watchio finishes; that replacement is intentionally outside the selected tree.
Docker Compose rows have no Stop tree action in this release.

## Docker is degraded

Watchio searches common Apple Silicon and Docker Desktop CLI locations and uses the CLI's active context only when it resolves to a local Unix socket. Confirm `docker context inspect` and `docker ps` work in Terminal. Remote contexts are intentionally refused. Compose labels are required; standalone containers are not shown in this alpha.

## The app and widget do not share data in Xcode

Select the same Apple development team for both targets, clean the build folder, delete the old widget from the desktop, run Watchio again, and re-add the widget. Confirm the expanded App Group is identical in both built entitlements.

## Unsigned command-line build fails

Run `xcode-select -p`, confirm Xcode 16.2+, accept Xcode's license if required, then run `make check`. CI uses explicit Xcode application paths documented in `.github/workflows/ci.yml`.
