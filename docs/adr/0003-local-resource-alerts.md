# ADR-0003: Local, sustained resource alerts

- Status: Accepted
- Date: 2026-08-23

## Context

Watchio already records aggregate CPU and resident memory for detected development service and AI
process trees. A useful warning must avoid reacting to normal compiler spikes, must work without
root or private APIs, and must respect WidgetKit's snapshot-based execution model.

macOS does not expose a stable, unprivileged per-process battery-consumption percentage suitable for
this project. Widget extensions are also not continuously active and cannot own process sampling.

## Decision

The visible collector evaluates resource pressure after logical process grouping:

- Memory alerts compare aggregate process-tree RSS with a configurable threshold.
- Energy alerts compare aggregate process-tree CPU with a configurable threshold only while IOKit
  reports battery power. The UI calls this an energy proxy and never presents it as battery percent.
- Activation requires three consecutive high samples. Recovery requires two samples below 80% of
  the threshold.
- Active alerts enter the latest versioned snapshot so every widget family can render a subtle amber
  state. Evaluator streaks and recovery state remain in memory.
- Quiet macOS notifications are opt-in, contain no sound or sensitive process data, deep-link to the
  affected row, and use a one-hour in-memory cooldown per alert.
- Alerts remain observational. They never invoke process control or another mutating action.

## Consequences

Brief build spikes should not notify. A real alert normally appears after roughly 30 seconds at the
default scan interval, and WidgetKit may render it later. Restarting Watchio resets the streak and
cooldown. Energy alerts are conservative and comparable to CPU pressure, not to Activity Monitor's
private Energy Impact calculation.
