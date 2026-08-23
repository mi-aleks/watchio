# Roadmap

The roadmap protects Watchio's observe-only, local-first boundary. Dates are intentionally not promised.

## 0.1 — trustworthy foundation

- Native menu bar Services, Ports, and Health
- Settings for login opt-in, roots, runtimes, Review, Widget, Privacy, and About
- Native include/ignore glob rule editor
- Small, Medium, and Large configurable widgets
- Same-user Node/Bun/Deno, Go, Python, and Docker Compose detection
- Versioned latest-only snapshot, freshness, offline, and fail-closed states
- Source-only public alpha and contributor documentation

## 0.2 — explainability and control

- Curated detection-rule presets and richer inline validation
- Stronger service naming without persisting secrets
- Project-specific widget selection backed by dynamic App Entities
- Expanded keyboard, VoiceOver, reduced-motion, and UI automation coverage
- Opt-in local diagnostic export containing only redacted evidence

## 0.3 — distribution readiness

- Reproducible Release pipeline and artifact provenance
- Developer ID signing and notarization
- DMG only after clean lifecycle and Gatekeeper validation
- Homebrew Cask only after the notarized release channel is stable

## Not planned

- Stopping or restarting processes
- Root helpers or Full Disk Access
- Accounts, cloud sync, telemetry, or persisted activity history
- Environment or raw command-line collection
- A hidden launch daemon

Proposals that cross these boundaries require a public ADR and maintainer approval before implementation.
