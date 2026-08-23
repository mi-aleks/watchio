# Watchio Privacy Promise

Watchio observes local development services without creating a behavioral history or sending data elsewhere.

## Data Watchio uses

For processes owned by the current Unix user, collection uses PID relationships, executable path, process group, TTY presence, elapsed time, CPU, resident memory, working directory, and already-qualified TCP/UDP listeners. Docker Compose metadata is read from the active local Docker CLI context.

For supported AI tools, Watchio uses only exact executable identity, trusted installation-path
fragments, project working directory, TTY presence, and process ancestry to classify OS-level
activity. It does not connect to an AI provider or application API.

Working directories are used transiently to locate nearby project markers. Watchio does not crawl arbitrary user directories. Persisted display paths replace the current home directory with `~`; paths outside it are reduced to a final component.

## Data Watchio never collects

- Environment variable names or values
- Raw process command lines or arguments in snapshots or diagnostics
- Prompts, responses, conversation/session files, task titles, or agent transcripts
- File contents, source code, browser data, credentials, or shell history
- Account identity, telemetry, analytics, crash uploads, or advertising identifiers
- Remote Docker engines or cloud data; non-local Docker contexts are refused before listing

## Storage and retention

Watchio atomically replaces a single versioned widget snapshot. AI rows contain only tool, host,
display-safe project, representative PID, aggregate resource values, uptime, confidence, and
non-sensitive evidence. Watchio does not persist historical samples. A bounded resource trend
exists only in process memory and disappears when the owning process exits. Detection preferences
are stored in shared local defaults.

## Network and privileges

Watchio contains no application networking client and makes no Watchio-originated outbound requests. It does not ask for root, Full Disk Access, Accessibility, or Automation permission. The visible collector is nonsandboxed solely to inspect same-user process metadata; the widget is sandboxed.

## Verify the promise

The repository is source-only and includes `make privacy-check`, persisted-model tests, and CI. Please report a suspected privacy issue through [private vulnerability reporting](https://github.com/mi-aleks/watchio/security/advisories/new).
