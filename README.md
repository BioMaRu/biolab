# BioLab

A personal, native-feeling **macOS developer toolkit** — a single Tauri + Svelte
app that hosts multiple developer features behind a sidebar. First feature: a
full-featured **Port Manager**.

## Stack

- **Tauri v2** (Rust backend) → native macOS app
- **SvelteKit + Svelte 5 runes** (`@sveltejs/adapter-static`, static SPA)
- **TypeScript**, **SCSS** (own light/dark tokens, native macOS feel)
- **Bun** + **Turborepo** monorepo

## Layout

```
apps/
  desktop/        # SvelteKit UI + src-tauri/ (Rust)
packages/         # shared code (added when a 2nd consumer appears)
```

## Prerequisites

- macOS + Xcode Command Line Tools
- Rust + Cargo (`rustup`)
- Node 22+ and Bun 1.3+ (see `.tool-versions`; `mise install` if you use mise)

## Getting started

```bash
bun install
bun run tauri dev      # launches the native app window
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
