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

Watchio is observe-only and runs without root. All subprocesses use fixed executable URLs and argument arrays, bounded output, timeouts, and cancellation. Shell interpolation is prohibited. Snapshot decoders fail closed on unknown schema versions. See [Architecture](docs/architecture.md) and [Privacy](PRIVACY.md).
