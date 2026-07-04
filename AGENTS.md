# BioLab — Agent & Contributor Guide

BioLab is a **personal macOS developer toolkit** — a native-feeling Tauri + Svelte
app that hosts multiple developer features behind a sidebar. Feature #1 is a
**Port Manager**. It mirrors the conventions of `fw-sveltekit-template`, adapted
for a Tauri **static SPA** (no SSR) and a native macOS look & feel.

## Golden rules

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
