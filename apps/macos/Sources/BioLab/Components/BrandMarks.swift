import AppKit
import Foundation
import SwiftUI

/// A real, bundled brand logo for a tool, if one has been dropped into
/// `Resources/Brands` (named `claude.svg` / `codex.pdf` / `opencode.png`, etc.).
/// Returns nil so callers fall back to the hand-drawn `BrandMark`. Results are
/// cached per run — the bundle can't change while the app is open.
@MainActor
enum BrandAsset {
    private static var cache: [ToolID: NSImage?] = [:]

    static func image(for tool: ToolID) -> NSImage? {
        if let cached = cache[tool] { return cached }
        var found: NSImage?
        for ext in ["svg", "pdf", "png"] {
            if let url = Bundle.module.url(
                forResource: tool.rawValue, withExtension: ext, subdirectory: "Brands"),
                let image = NSImage(contentsOf: url)
            {
                found = image
                break
            }
        }
        cache[tool] = found
        return found
    }
}

/// Brand marks for each agent, drawn as native SwiftUI vector paths — no
/// bundled assets and no SVG runtime (the package's only dependency is
/// TOMLKit). Each scales crisply from the 11-pt menu-bar picker to the 28-pt
/// card tile and renders monochrome (template) or in the brand's own color.
///
/// Fidelity: Claude's radial spark is a faithful recreation; Codex is an
/// OpenAI-blossom-style hexagonal knot; OpenCode is a clean terminal-prompt
/// mark (it has no widely published symbol). Swap in an official SVG anytime
/// by replacing the matching `Shape`.
struct BrandMark: View {
    let tool: ToolID
    var size: CGFloat = 15
    /// Force a single-color (template) rendering — for tinted or menu contexts.
    var monochrome = false

    /// Claude / Anthropic terracotta.
    static let claudeColor = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)

    var body: some View {
        Group {
            switch tool {
            case .claude:
                ClaudeSpark()
                    .fill(monochrome ? Color.primary : Self.claudeColor)
            case .codex:
                // OpenAI's mark is monochrome by design, so it ignores color.
                CodexKnot()
                    .stroke(
                        Color.primary,
                        style: StrokeStyle(
                            lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
            case .opencode:
                OpenCodePrompt()
                    .stroke(
                        Color.primary,
                        style: StrokeStyle(
                            lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Claude — radial spark

/// A ring of tapered needles radiating from the center: Claude's spark.
private struct ClaudeSpark: Shape {
    var rays = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let inner = radius * 0.05
        let outer = radius * 0.97
        let mid = (inner + outer) / 2
        // Angular half-width of each needle at its midpoint.
        let spread = (.pi / Double(rays)) * 0.55

        for i in 0..<rays {
            let angle = (Double(i) / Double(rays)) * 2 * .pi - .pi / 2
            let tipInner = point(center, inner, angle)
            let tipOuter = point(center, outer, angle)
            let bulgeA = point(center, mid, angle - spread)
            let bulgeB = point(center, mid, angle + spread)
            path.move(to: tipInner)
            path.addQuadCurve(to: tipOuter, control: bulgeA)
            path.addQuadCurve(to: tipInner, control: bulgeB)
            path.closeSubpath()
        }
        return path
    }

    private func point(_ c: CGPoint, _ r: CGFloat, _ a: Double) -> CGPoint {
        CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
    }
}

// MARK: - Codex — hexagonal knot

/// Three stadium (capsule) rings rotated 60° apart — the six-fold interlocked
/// silhouette of the OpenAI blossom.
private struct CodexKnot: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let length = radius * 1.74
        let thickness = radius * 0.66

        for k in 0..<3 {
            let angle = Double(k) * .pi / 3
            let bounds = CGRect(
                x: center.x - length / 2, y: center.y - thickness / 2,
                width: length, height: thickness)
            let strand = Path(roundedRect: bounds, cornerRadius: thickness / 2)
                .applying(
                    CGAffineTransform(translationX: center.x, y: center.y)
                        .rotated(by: angle)
                        .translatedBy(x: -center.x, y: -center.y))
            path.addPath(strand)
        }
        return path
    }
}

// MARK: - OpenCode — terminal prompt

/// A rounded chevron prompt with a cursor tick: `>_`.
private struct OpenCodePrompt: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let top = rect.minY + h * 0.28
        let bottom = rect.minY + h * 0.72
        let mid = rect.midY

        // Chevron ">"
        path.move(to: CGPoint(x: rect.minX + w * 0.24, y: top))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.50, y: mid))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.24, y: bottom))

        // Cursor underscore
        path.move(to: CGPoint(x: rect.minX + w * 0.58, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.78, y: bottom))
        return path
    }
}
