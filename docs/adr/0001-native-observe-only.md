# ADR-0001: Native, visible collection

- Status: Amended by [ADR-0002](0002-safe-process-tree-control.md)
- Date: 2026-08-23

## Context

Watchio needs same-user process and socket metadata, a menu bar experience, and WidgetKit presentation. A hidden helper could make collection more continuous, while a cross-platform runtime could accelerate development. Both add operational or privacy cost to a small local observer.

## Decision

Build Watchio in SwiftUI for macOS 14+ with a standard Xcode project and dependency-free local Swift package. Run collection only inside the visible menu bar app. Do not install a LaunchAgent, daemon, or privileged helper. Offer an explicit `SMAppService.mainApp` Launch at Login toggle. The initial decision excluded process control; ADR-0002 later permits one narrow, confirmed local stop capability.

The collector is nonsandboxed, restricted in product behavior to same-UID read-only inventory, and uses fixed subprocess executable URLs/arguments. The widget is sandboxed and consumes a latest-only versioned snapshot.

## Consequences

- The product integrates naturally with MenuBarExtra, Settings, ServiceManagement, App Intents, and WidgetKit.
- Collection stops when the app stops, and widgets must communicate freshness/offline state.
- Nonsandboxed collector code requires unusually strong review around subprocesses, persistence, and future features.
- Apple Silicon and modern macOS can be the initial optimized target.
- Cross-platform support and automatic, bulk, remote, or privileged process control remain outside the architecture.
