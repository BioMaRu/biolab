# BioLab

A personal **macOS developer toolkit** that lives in your menu bar: AI-usage
tracking for Claude Code / Codex / OpenCode (with live Claude plan limits), a
Port Manager, and a cross-agent config manager (MCP servers, skills, symlinks,
context files).

## Stack

- **`apps/macos` — the app (primary)**: fully native **Swift 6 / SwiftUI**
  (SPM, macOS 14+). `MenuBarExtra` quick panel (AI Usage + Ports tabs) plus a
  full window (Ports · Agents · AI Usage · Settings). One dependency: TOMLKit.

## Layout

```
apps/
  macos/          # native SwiftUI app — Package.swift + build.sh
```

## Prerequisites

- macOS 14+
- Xcode with the full Swift toolchain

## Getting started

```bash
make mac-run           # release build → apps/macos/dist/BioLab.app → launch
make mac-dev           # fast debug build + launch
```

## Common commands

```bash
make mac               # build the native macOS app
make mac-dev           # debug build + launch
make mac-run           # release build + launch
make mac-dmg           # build a DMG in apps/macos/dist
```

See `AGENTS.md` for native app conventions and verification guidance.

## Releasing a new version

BioLab checks GitHub Releases for native app archives. To ship an update:

1. Bump the `VERSION` value in **`apps/macos/build.sh`**.
2. Commit the version change, then tag and push:
    ```bash
    git commit -am "release: v0.2.0"
    git tag v0.2.0
    git push origin main --tags
    ```
3. The **`release` GitHub Action** builds `BioLab.app`, packages it as a zip
   asset, and publishes a GitHub Release.
4. Installed copies can check for the latest release from **Settings → Check for
   Updates** and install the zip asset.
