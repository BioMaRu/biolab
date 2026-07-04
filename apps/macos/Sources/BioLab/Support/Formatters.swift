import Foundation

enum Fmt {
    /// Compact token count: 1234 → 1.2K, 3.4M, 1.0B.
    static func tokens(_ n: Int64) -> String {
        let f = Double(n)
        switch f {
        case 1e9...: return String(format: "%.1fB", f / 1e9)
        case 1e7...: return String(format: "%.0fM", f / 1e6)
        case 1e6...: return String(format: "%.1fM", f / 1e6)
        case 1e4...: return String(format: "%.0fK", f / 1e3)
        case 1e3...: return String(format: "%.1fK", f / 1e3)
        default: return String(n)
        }
    }

    /// Estimated USD spend.
    static func usd(_ n: Double) -> String {
        if n <= 0 { return "$0.00" }
        if n < 0.01 { return "<$0.01" }
        if n < 1000 { return String(format: "$%.2f", n) }
        return "$" + Int(n.rounded()).formatted(.number.grouping(.automatic))
    }

    static func money(_ n: Double, _ currency: String) -> String {
        String(format: "%@ %.2f", currency, n)
    }

    /// Relative "time ago".
    static func ago(_ date: Date?, now: Date = .init()) -> String {
        guard let date else { return "never" }
        let s = now.timeIntervalSince(date)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86400))d ago"
    }

    /// Reset time for a plan limit: "resets in 1h 24m" near, else "resets Sat 11:59 AM".
    static func reset(_ date: Date?, now: Date = .init()) -> String {
        guard let date else { return "—" }
        let s = date.timeIntervalSince(now)
        if s <= 0 { return "resets now" }
        if s < 24 * 3600 {
            let h = Int(s) / 3600
            let m = (Int(s) % 3600) / 60
            return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
        }
        let df = DateFormatter()
        df.dateFormat = "EEE h:mm a"
        return "resets " + df.string(from: date)
    }

    static func bytes(_ n: UInt64) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1024 * 1024 { return String(format: "%.1f KB", Double(n) / 1024) }
        return String(format: "%.1f MB", Double(n) / (1024 * 1024))
    }

    /// Short model label: claude-opus-4-8 → Opus 4.8, gpt-5.5 → GPT-5.5.
    static func model(_ model: String) -> String {
        let m = model.lowercased()
        let family: String
        if m.contains("opus") { family = "Opus" }
        else if m.contains("sonnet") { family = "Sonnet" }
        else if m.contains("haiku") { family = "Haiku" }
        else if m.contains("fable") { family = "Fable" }
        else if m.hasPrefix("gpt") { return model.uppercased().replacingOccurrences(of: "GPT", with: "GPT") }
        else { return model }
        if let range = model.range(of: #"(\d+[-.]\d+)"#, options: .regularExpression) {
            let ver = model[range].replacingOccurrences(of: "-", with: ".")
            return "\(family) \(ver)"
        }
        return family
    }

    /// Last path segment, for compact project labels.
    static func projectName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

/// ISO-8601 parsing tolerant of fractional seconds (Claude log timestamps).
enum ISO {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String) -> Date? {
        fractional.date(from: s) ?? plain.date(from: s)
    }
}
