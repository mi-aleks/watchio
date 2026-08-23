# Detection contract

Detection is heuristic, local, explainable, and intentionally biased against false positives.

## Inventory

Every scan invokes:

- `/bin/ps -axo uid=,pid=,ppid=,pgid=,tty=,etime=,%cpu=,rss=,comm=`
- `/usr/sbin/lsof` with an explicit same-user TCP-listener query
- `lsof` CWD queries for supported-runtime or TCP-listener candidates, batched to 64
- PID-scoped UDP queries only after a candidate reaches the visible or Review threshold
- local Docker-context inspection, then `docker ps -q --no-trunc`; `docker inspect` only for new container IDs

All commands have fixed executable URLs, argument arrays, timeouts, cancellation, and a two-megabyte output cap. Status 1 with empty output is accepted for valid no-match `lsof` queries. Output and error text are transient; source-health messages are sanitized.

Only records matching `getuid()` and at least three seconds old proceed. Watchio does not request arguments from `ps` and never requests process environments.

## Project resolution

Default roots are existing `~/Code`, `~/Developer`, and `~/Projects`. Users can add roots. Starting from a candidate CWD, the resolver walks upward only inside configured roots and stops at the first supported marker:

- `.git`
- `package.json`
- `go.mod`
- `pyproject.toml`, `uv.lock`, or `Pipfile`
- `Package.swift`
- `Cargo.toml` (project evidence only; Rust runtime classification is not yet first-class)

No configured root is recursively crawled.

## Confidence

| Evidence | Points |
|---|---:|
| Project marker CWD | +40 |
| Supported runtime executable | +25 |
| Listening endpoint | +20 |
| Terminal/IDE ancestry or TTY | +15 |
| Known toolchain path | +10 |
| Explicit include glob | force include |

System libraries, `libexec`, GUI app executables, Watchio, Docker backend, generic unexplained processes, and launchd-owned processes without project evidence receive strong penalties. Ignore globs always win.

- 60–100: visible service
- 40–59: Review suggestion
- 0–39: hidden

Every visible or Review result carries only the non-sensitive evidence labels responsible for its score.

## Runtime rules

- Node.js: executable basename `node` or `node-*`
- Bun: `bun` or `bunx`
- Deno: `deno`
- Go: `go` or executable path containing `/go-build`
- Python: `python`, `python2*`, or `python3*`
- Docker Compose: required `com.docker.compose.project` and `.service` labels

Compose rows use published host ports and suppress raw Docker backend processes. Containers without Compose labels remain hidden. Non-Unix-socket Docker contexts fail closed before container listing.

## Grouping

Candidates group by resolved project root plus process group (or PID when no useful process group exists). The representative is the highest-confidence candidate. All same-group processes contribute process count, CPU, RSS, earliest start, and listeners. This treats a runtime and its workers as one logical service without persisting raw arguments.

## Adding a detector

Add a narrow runtime rule, positive fixtures, GUI/daemon false-positive fixtures, and grouping tests. Explain what public metadata creates confidence. A new detector may not require environment values, argument persistence, file-content crawling, outbound requests, elevated privileges, or an action that changes a process.
