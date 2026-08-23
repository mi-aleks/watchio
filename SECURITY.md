# Security Policy

## Supported versions

Watchio is currently alpha source software. Security fixes target the `main` branch and the latest tagged alpha.

| Version | Supported |
|---|---|
| `main` | Yes |
| Latest `0.1.0-alpha.*` | Yes |
| Older snapshots | No |

## Reporting a vulnerability

Do not open a public issue for a vulnerability or privacy exposure. Use GitHub's [private vulnerability reporting](https://github.com/mi-aleks/watchio/security/advisories/new). Include the affected commit, macOS/Xcode version, impact, reproduction, and any proposed mitigation.

You should receive an acknowledgement within 72 hours and an initial assessment within seven days. Timelines may change for a volunteer-maintained project, but status will be communicated through the private advisory.

## Security boundaries

Watchio runs without root and has no automatic or background process actions. Its only mutating
capability is an explicitly confirmed, per-row stop of a same-user process tree. The control path
re-verifies PID, UID, executable, and inferred start time; refuses Watchio and its ancestors;
stabilizes descendants while frozen; uses `SIGTERM` before `SIGKILL`; and never broadcasts to a
process group. Identity change, unstable inventory, and permission failures fail closed. See
[ADR-0002](docs/adr/0002-safe-process-tree-control.md).

All inventory subprocesses use fixed executable URLs and argument arrays, bounded output, timeouts,
and cancellation. Shell interpolation is prohibited. Snapshot decoders fail closed on unknown schema
versions. See [Architecture](docs/architecture.md) and [Privacy](PRIVACY.md).

Resource alerts are observational and cannot trigger process control. Energy alerts use the local
IOKit power-source state plus sustained aggregate CPU; no privileged energy sampler is invoked.
Optional local notifications contain only snapshot-safe fields and are rate-limited in memory.
