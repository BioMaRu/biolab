# BioLab — Agent & Contributor Guide

BioLab is a **personal macOS developer toolkit**: a Port Manager, a cross-agent
config manager (MCP / skills / symlinks / context files for Claude Code, Codex
and OpenCode), an AI-usage dashboard with live Claude plan limits, and a
menu-bar quick panel.

> **Searching:** prefer `rg` (ripgrep) over `grep`/`grep -r`. It is installed and
> much faster; only fall back to `grep` if `rg` is genuinely unavailable.

## ⚠️ Product direction: `apps/macos` (native Swift) is the primary app

As of 2026-07-05 BioLab is being rewritten as a **fully native SwiftUI app** in
`apps/macos/` (Swift 6 / SwiftUI / SPM, macOS 14+). The Tauri + Svelte app in
`apps/desktop/` is the **legacy implementation**, kept until the native app
reaches full parity — prefer building new features natively.

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

## Legacy web app rules (`apps/desktop` — Tauri + Svelte)

1. **Bun only.** Never use npm / pnpm / yarn. The lockfile is `bun.lock`.
2. **Turborepo monorepo.** Apps live in `apps/*`, shared code in `packages/*`.
   Promote code into a package **only when there is a real second consumer** —
   until then it lives in the app.
3. **Svelte 5 runes only.** Use `$state` / `$derived` / `$props` / `$effect`.
   No legacy stores, no `export let`. Reactive logic in `.ts` goes in
   `*.svelte.ts` files. Shared state is a **singleton class instance**.
4. **Thin routes, logic in `features/`.** Route files wire things together;
   real logic lives in vertical feature slices under `src/features/*`.
5. **Never fight the formatters.** Prettier + ESLint + Stylelint are the source
   of truth. Run `bun run format` before committing.
6. **Static SPA.** SvelteKit uses `@sveltejs/adapter-static` with `ssr = false`.
   There is no server — anything that needs the OS goes through a **Tauri
   command** (Rust, in `apps/desktop/src-tauri/`) invoked via `@tauri-apps/api`.
7. **Styling = SCSS** with our own light/dark design tokens (see
   `apps/desktop/src/style`). `[data-theme]` on `<html>` drives the theme. No
   Tailwind, no external brand design system.

## Quality gate (run before committing)

```
bun run format   # prettier --write
bun run check    # svelte-check (types)
bun run lint     # eslint + stylelint
bun run build    # production build
```

## Commands

- `bun run tauri dev` — run the desktop app (from repo root; filters to `@biolab/desktop`)
- `bun run tauri build` — package the `.app` / `.dmg`
- `bun run dev` — run the SvelteKit dev server only (no native window)

## Version discipline

`prettier`, `prettier-plugin-svelte`, and `svelte` must be identical across every
`package.json`; the root `overrides` block enforces it.
