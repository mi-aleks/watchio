# Architecture

Watchio is a native menu bar collector and a sandboxed WidgetKit reader separated by one minimal, versioned snapshot.

## Components

| Component | Responsibility | Security posture |
|---|---|---|
| `WatchioApp` | Owns the scan loop, menu bar UI, Settings, login-item opt-in, in-memory trend | Visible, same-user, nonsandboxed, no root |
| `WatchioWidget` | Reads and renders the latest snapshot | App Sandbox enabled, read-only product behavior |
| `WatchioModels` | Codable snapshot and transient inventory value types | No side effects |
| `WatchioDetection` | Process/listener/container inventory, project resolution, scoring, grouping | Fixed executables and arguments, bounded output |
| `WatchioStorage` | Atomic latest-snapshot and shared preferences | Unknown schema versions fail closed |

There are no runtime dependencies and no generated project. `Watchio.xcodeproj` links a local Swift package so the core can be tested without launching an app.

## Data flow

1. `AppModel` asks `DetectionEngine` to scan every ten seconds.
2. Providers inventory process metadata and TCP listeners, resolve candidates, then inspect UDP only for qualified service process groups. Compose inspection accepts local Docker CLI contexts only.
3. The engine filters by current UID and three-second stability. One process inventory feeds both development-service classification and the separate AI identity/ancestry classifier.
4. The app renders the result and atomically replaces the latest redacted snapshot.
5. WidgetKit loads that snapshot, applies its view/scope configuration, and renders a freshness or fail-closed state.

The app asks WidgetKit to reload for service/port/collector changes, coarse resource buckets, or a throttled 30-second freshness heartbeat. The heartbeat prevents an unchanged live collector from looking offline while still avoiding per-scan reload pressure.

## Protocol boundaries

- `ProcessInventoryProviding`
- `ListenerInventoryProviding`
- `ContainerInventoryProviding`
- `ProjectResolving`
- `SnapshotStoring`

Tests inject deterministic providers. The production runner never invokes a shell and cannot interpolate inventory values into executable source text.

## Storage contract

`WatchioSnapshot` schema version 2 contains generated time, collector state, services, AI activities,
review suggestions, and source health. A service contains only display-safe project path,
normalized listeners, aggregate resources, representative PID, process count, start time,
confidence, and non-sensitive evidence. An AI activity contains the recognized tool and host plus
the same bounded process/resource metadata; it contains no prompt, conversation, task, or raw
command data.

Raw arguments, environment values, full home paths, executable paths, CWDs, and Docker inspection payloads cannot enter the persisted service shape. The snapshot store keeps one file with owner-only permissions. An unsupported schema produces Update Required, never a best-effort decode.

## Sandboxing and signing

The collector is nonsandboxed because sandboxed apps cannot reliably inspect arbitrary same-user development processes. It has no privilege helper, root path, LaunchAgent, automation permission, or Full Disk Access request. The widget is sandboxed. Release builds enable Hardened Runtime.

Both targets share `$(DEVELOPMENT_TEAM).io.github.mi-aleks.watchio.shared`, a team-prefixed group suitable for source builders selecting their own team.

## Trade-offs

- Avoiding arguments and environment data protects secrets but limits exact service naming.
- Process-only AI classification cannot distinguish logical agents multiplexed in one host or generic script runners.
- Conservative scoring creates occasional Review items but reduces surprising GUI/system false positives.
- Snapshot-only widgets can be stale because WidgetKit owns scheduling; the app is the authoritative live view.
- Docker collection fails closed when the active CLI context is not a local Unix socket.

See [ADR-0001](adr/0001-native-observe-only.md) and [Detection](detection.md).
