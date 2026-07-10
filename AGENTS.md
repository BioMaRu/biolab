# BioLab — Agent & Contributor Guide

BioLab is a **personal macOS developer toolkit**: a Port Manager, a cross-agent
config manager (MCP / skills / symlinks / context files for Claude Code, Codex
and OpenCode), an AI-usage dashboard with live Claude plan limits, and a
menu-bar quick panel.

> **Searching:** prefer `rg` (ripgrep) over `grep`/`grep -r`. It is installed and
> much faster; only fall back to `grep` if `rg` is genuinely unavailable.

## Product direction: SwiftUI only

BioLab is a **fully native SwiftUI app** in `apps/macos/` (Swift 6 / SwiftUI /
SPM, macOS 14+). The legacy Tauri/Svelte implementation has been removed. Build
new features natively; do not introduce webview, Node/Bun, Svelte, Tauri, or
Turborepo infrastructure.

### Native app rules (`apps/macos`)

1. **Pure SwiftUI + SPM.** No storyboards/xibs; the only dependency is TOMLKit
   (Codex `config.toml` editing). Build via `make mac` / `make mac-dev`
   (wraps `apps/macos/build.sh`, which assembles + ad-hoc-signs `dist/BioLab.app`).
2. **Menu bar first.** The app is an `LSUIElement` accessory: a
   `MenuBarExtra(.window)` panel (tabs: AI Usage default, then Ports) is the
   primary surface; the full window opens on demand. **Native UI only — never
   a webview.**
3. **Architecture: Models / Services / AppState / Views.** Services are pure and
   run off-main (`PortsService`, `UsageService` actor with incremental caches,
   `LimitsService`, `AgentsService`); `AppState` (@Observable, @MainActor) is
   the single source of truth for all surfaces.
4. **Safety invariants** (ported from the Rust backend — keep them):
   config mutations back up to `~/.biolab/backups` first; SQLite is opened
   read-only (`mode=ro`); `symlinkRemove` refuses non-symlinks; the Claude
   OAuth token is read via `/usr/bin/security` and sent **only** to Anthropic.
5. **Design language:** system SF Pro type + SF Symbols, Flint indigo accent
   (#3e63dd) via `Theme.swift`, semantic system colors for automatic
   light/dark.

## Quality gate (run before committing)

```
make mac         # release build and app bundle assembly
```

## Commands

- `make mac` — build the native macOS app in release mode
- `make mac-dev` — fast debug build and launch
- `make mac-run` — release build and launch
- `make mac-dmg` — build a DMG in `apps/macos/dist`
