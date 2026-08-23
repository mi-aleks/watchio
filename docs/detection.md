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

The process inventory is collected once per scan and shared by service and AI classification.

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

## AI activity rules

AI activity is a separate process-only classifier. It matches exact executable basenames so generic
application helpers such as `Codex Renderer`, `code-mode-host`, and Cursor UI services do not
become false positives.

| Tool | Recognized executable names |
|---|---|
| Codex | `codex` |
| Claude | `claude` |
| Gemini CLI | `gemini` |
| Aider | `aider`, `aider-chat` |
| OpenCode | `opencode` |
| Goose | `goose` |
| GitHub Copilot CLI | `copilot`, `github-copilot` |
| Cursor Agent | `cursor-agent` |

The known executable contributes 45 points. A recognized installation path contributes 20; a
resolved project, TTY, IDE host, or desktop host contributes 15 each; recognized AI ancestry
contributes 10. Activities require 60 points and have no Review queue. The UI reports only the
non-sensitive evidence used by the score.

The classifier labels an activity as CLI, VS Code, desktop, background, or subagent. Descendant
helper processes contribute CPU, RSS, process count, and uptime to their nearest recognized AI
ancestor. The UI labels CPU and resident RAM as process-tree totals. A separately executable AI
child can remain its own subagent row with independent totals.

Watchio cannot safely infer a tool when macOS exposes only a generic `node` or `python` executable,
because arguments are outside the collection contract. It also cannot enumerate logical agents,
tasks, or conversations multiplexed inside one desktop process. Those cases remain hidden or
appear as one host activity rather than weakening the privacy boundary.

## Grouping

Candidates group by resolved project root plus process group (or PID when no useful process group exists). The representative is the highest-confidence candidate. All same-group processes contribute process count, CPU, RSS, earliest start, and listeners. This treats a runtime and its workers as one logical service without persisting raw arguments.

## Adding a detector

Add a narrow runtime rule, positive fixtures, GUI/daemon false-positive fixtures, and grouping tests. Explain what public metadata creates confidence. A new detector may not require environment values, argument persistence, file-content crawling, outbound requests, or elevated privileges. Detection must never trigger process control; the separately confirmed stop contract is documented in [ADR-0002](adr/0002-safe-process-tree-control.md).
