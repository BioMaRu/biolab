import SwiftUI

/// BioLab's design language, adapted from the Flint system (flintsystem.design)
/// for native macOS: the Radix Indigo 9 brand accent over system materials and
/// semantic colors (which track light/dark automatically). Typography is the
/// system stack — SF Pro — as befits a native app.
enum Theme {
    /// Brand accent — Radix Indigo 9 (#3e63dd), identical in both appearances.
    static let accent = Color(red: 0x3E / 255, green: 0x63 / 255, blue: 0xDD / 255)

    /// Legible accent for text/icons sitting on a subtle accent tint.
    static let accentFg = Color(
        light: .init(red: 0x33 / 255, green: 0x58 / 255, blue: 0xD4 / 255),
        dark: .init(red: 0x9E / 255, green: 0xB1 / 255, blue: 0xFF / 255)
    )

    static let success = Color(
        light: .init(red: 0x30 / 255, green: 0xA4 / 255, blue: 0x6C / 255),
        dark: .init(red: 0x33 / 255, green: 0xB0 / 255, blue: 0x74 / 255)
    )
    static let warning = Color(
        light: .init(red: 0xF7 / 255, green: 0x6B / 255, blue: 0x15 / 255),
        dark: .init(red: 0xFF / 255, green: 0x80 / 255, blue: 0x1F / 255)
    )
    static let danger = Color(
        light: .init(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255),
        dark: .init(red: 0xEC / 255, green: 0x5D / 255, blue: 0x5E / 255)
    )

    static func severity(_ s: String) -> Color {
        switch s {
        case "warning": warning
        case "critical": danger
        default: accent
        }
    }

    /// Corner radii — exactly three, so surfaces at the same nesting depth
    /// always agree.
    enum Radius {
        /// Chips, fields, small buttons, glyph tiles.
        static let control: CGFloat = 6
        /// Nested blocks inside cards: banners, limit blocks, code boxes.
        static let block: CGFloat = 8
        /// Cards and other top-level surfaces.
        static let card: CGFloat = 10
    }

    /// Spacing on a 4-pt grid.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    /// One measure for scrollable content columns across every screen.
    static let contentMaxWidth: CGFloat = 800
}

extension Color {
    /// A dynamic color with distinct light/dark variants.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    init(light: Color, dark: Color) {
        self.init(light: NSColor(light), dark: NSColor(dark))
    }
}
