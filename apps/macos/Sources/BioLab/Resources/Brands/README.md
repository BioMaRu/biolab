# Brand logos (optional drop-in)

Drop a real logo file here to override the hand-drawn mark for an agent.
Name it after the tool id, in your preferred vector-or-raster format:

    claude.svg      codex.pdf       opencode.png

Lookup order per tool is `svg`, then `pdf`, then `png` (first match wins).
Prefer a vector format (svg/pdf) so it stays crisp at every size.

`AgentGlyph` loads these via `BrandAsset`; if no file is present it falls back
to the native `BrandMark` shapes, so the app is never broken by a missing logo.

Source logos from each vendor's official brand / press kit — not a third-party
aggregator — so the marks are current and correctly licensed. Using a product's
logo to identify it inside BioLab is nominative use.

After adding or changing a file, rebuild (`make mac`).
