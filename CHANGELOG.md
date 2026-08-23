# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added a process-only AI activity view and widget mode for Codex, Claude, Gemini CLI, Aider,
  OpenCode, Goose, GitHub Copilot CLI, and Cursor Agent.
- Added host classification for CLI, VS Code, desktop, background, and separately executable
  subagent processes, with descendant resource aggregation and explainable confidence evidence.
- Added always-visible CPU and resident RAM totals to AI rows and Medium/Large AI widgets.

### Changed

- Reworked the menu bar and every widget family around the darker, denser visual language from
  the original Watchio concept.
- Replaced generic text badges with original runtime glyphs and database-aware Docker Compose
  presentation.

## [0.1.0-alpha.1] - 2026-08-23

### Added

- Native macOS menu bar collector, Settings, and configurable Small/Medium/Large widgets.
- Same-user `ps`/`lsof` inventory and explainable confidence classification.
- Node.js, Bun, Deno, Go, Python, and Docker Compose detection.
- Versioned atomic snapshot storage with stale, offline, corrupt, and update-required states.
- Deterministic demo data, core fixtures, privacy checks, and Xcode 16/26 CI.
- Native onboarding, detection-rule editing, deep links, and deterministic UI automation.
- Open-source governance, architecture, detection, build, troubleshooting, and release documentation.

[Unreleased]: https://github.com/mi-aleks/watchio/compare/0.1.0-alpha.1...HEAD
[0.1.0-alpha.1]: https://github.com/mi-aleks/watchio/releases/tag/0.1.0-alpha.1
