# BioLab

A personal **macOS developer toolkit** that lives in your menu bar: AI-usage
tracking for Claude Code / Codex / OpenCode (with live Claude plan limits), a
Port Manager, and a cross-agent config manager (MCP servers, skills, symlinks,
context files).

## Stack

- **`apps/macos` — the app (primary)**: fully native **Swift 6 / SwiftUI**
  (SPM, macOS 14+). `MenuBarExtra` quick panel (AI Usage + Ports tabs) plus a
  full window (Ports · Agents · AI Usage · Settings). One dependency: TOMLKit.
- **`apps/desktop` — legacy**: the original Tauri v2 + SvelteKit
  implementation, kept until the native app reaches full parity.

## Layout

```
apps/
  macos/          # native SwiftUI app (primary) — Package.swift + build.sh
  desktop/        # legacy SvelteKit UI + src-tauri/ (Rust)
packages/         # shared code (added when a 2nd consumer appears)
```

## Prerequisites

- macOS 14+ and Xcode (full toolchain, for the native app)
- Legacy app only: Rust + Cargo, Node 22+, Bun 1.3+

## Getting started

```bash
make mac-run           # native app: release build → dist/BioLab.app → launch
make mac-dev           # native app: fast debug build + launch

# legacy Tauri app
bun install
bun run tauri dev
```

## Common commands

```bash
bun run tauri dev      # run the desktop app
bun run tauri build    # package .app / .dmg
bun run dev            # SvelteKit dev server only (browser, no native window)
bun run format         # prettier --write
bun run check          # svelte-check (types)
bun run lint           # eslint + stylelint
bun run build          # production build
```

See `AGENTS.md` for conventions and the pre-commit quality gate.

## Releasing a new version (auto-update)

BioLab auto-updates from GitHub Releases via `tauri-plugin-updater`. To ship an update:

1. Bump the version in **`apps/desktop/src-tauri/tauri.conf.json`** (and `apps/desktop/package.json`).
2. Commit, then tag and push:
    ```bash
    git commit -am "release: v0.2.0"
    git tag v0.2.0
    git push origin main --tags
    ```
3. The **`release` GitHub Action** builds a universal macOS app, signs the update, and publishes a GitHub Release with a `latest.json` manifest.
4. Every installed copy of BioLab checks that manifest on launch (and via **Settings → Check for Updates**) and updates itself.

**One-time setup on GitHub** (see the repo secrets):

- `TAURI_SIGNING_PRIVATE_KEY` — the updater private key
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` — its password

The matching **public key** lives in `tauri.conf.json` (`plugins.updater.pubkey`). The repo must be **public** so the updater can fetch release assets without authentication.
