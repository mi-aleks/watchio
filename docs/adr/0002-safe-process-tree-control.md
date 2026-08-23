# ADR-0002: Safe, explicit process-tree control

- Status: Accepted
- Date: 2026-08-23

## Context

Watchio can identify a development service yet still leave the user to find and terminate its
individual PIDs. A naïve `killpg`, shell command, or stale-PID action could stop an IDE, terminal,
Watchio itself, another user's process, or a newly reused PID. Graceful termination alone can also
leave descendants alive.

## Decision

Permit one local mutating action: **Stop tree…** on an expanded service or AI activity with a local
representative PID. Require a destructive confirmation for every invocation. Widgets, scans,
timers, launch-at-login, and deep links cannot invoke the action.

`ProcessTreeTerminator` must:

1. Reject PID 1, foreign UIDs, Watchio, and every ancestor of the current Watchio process.
2. Match the selected root by PID, UID, executable path, and inferred start time.
3. Send `SIGSTOP` to the root, repeatedly inventory and freeze same-user descendants, and abort if
   the tree cannot stabilize within the fixed pass limit.
4. Re-verify every frozen identity before sending destructive signals.
5. Send `SIGTERM` deepest-first, then `SIGCONT`, and watch for descendants of still-live tracked
   processes during a five-second grace period.
6. Send `SIGKILL` only to identities that still match, poll again, and report survivors.
7. Fail closed on identity change, unavailable inventory, ownership mismatch, or signal failure.

Do not invoke a shell, interpolate process data, broadcast to a process group, climb to unrelated
ancestors, control Docker containers through a local backend PID, request privileges, or persist
termination identities. Keep POSIX signaling behind an injectable protocol and test the state
machine with fake inventory and signal implementations.

## Consequences

- The common runtime-and-worker tree is stopped without leaving verified descendants behind.
- PID reuse and shared terminal/IDE process groups do not become termination authority.
- A small `SIGSTOP` race remains inherent to PID-based macOS APIs, but a mismatch never receives
  `SIGTERM` or `SIGKILL`. If UID and start identity still match after an `exec`, Watchio may send the
  same kernel process a cleanup `SIGCONT` so it is not left frozen.
- A supervisor outside the selected tree may spawn a replacement. Preventing that would require
  broader authority and is intentionally out of scope.
- Docker lifecycle control, restart, bulk stop, and automatic cleanup require separate future ADRs.
