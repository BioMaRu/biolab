import SwiftUI

// MARK: - Agent glyph

/// Small brand-evocative glyph tile for each agent (SF Symbols keep it native).
struct AgentGlyph: View {
    let tool: ToolID
    var size: CGFloat = 15

    private var symbol: String {
        switch tool {
        case .claude: "sparkle"
        case .codex: "hexagon"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        }
    }

    private var tint: Color {
        switch tool {
        case .claude: Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
        case .codex: .primary
        case .opencode: .primary
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(tint)
    }
}

// MARK: - Limit bar

/// One plan-limit row: label, % used, severity-tinted progress track, reset.
struct LimitBarRow: View {
    let bar: LimitBar
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text(bar.label)
                        .font(compact ? .callout.weight(.medium) : .body.weight(.medium))
                    if bar.isActive {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 6, height: 6)
                            .help("Active window")
                    }
                }
                Spacer()
                Text("\(Int(bar.percent.rounded()))% used")
                    .font(compact ? .callout.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressTrack(fraction: bar.percent / 100, tint: Theme.severity(bar.severity))
            Text(Fmt.reset(bar.resetsAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bar.label), \(Int(bar.percent)) percent used, \(Fmt.reset(bar.resetsAt))")
    }
}

struct ProgressTrack: View {
    let fraction: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.6))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}

// MARK: - Stat cell

struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Badges & headers

struct Badge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    var hint: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)
            Text(title).font(.headline)
            if let hint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - Inline error banner

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
