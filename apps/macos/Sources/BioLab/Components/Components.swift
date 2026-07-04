import SwiftUI

// MARK: - Agent glyph

/// Each agent's brand mark. Prefers a real logo dropped into
/// `Resources/Brands` (see `BrandAsset`); otherwise falls back to the
/// hand-drawn `BrandMark` — Claude in its terracotta, Codex and OpenCode
/// monochrome, matching their actual identities. Pass `monochrome: true` for
/// tinted/menu contexts (only affects the drawn fallback).
struct AgentGlyph: View {
    let tool: ToolID
    var size: CGFloat = 15
    var monochrome = false

    var body: some View {
        if let logo = BrandAsset.image(for: tool) {
            // Claude's mark carries its own terracotta; Codex and OpenCode are
            // single-color, so template-render them to stay legible on any
            // background and follow the ambient tint.
            let templated = monochrome || tool != .claude
            Image(nsImage: logo)
                .renderingMode(templated ? .template : .original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            BrandMark(tool: tool, size: size, monochrome: monochrome)
        }
    }
}

// MARK: - Segmented tabs

/// The one segmented control used on panel surfaces: tinted accent fill and
/// border for the selected segment, quiet for the rest. Windows keep the
/// native segmented `Picker`; this exists so the panel has exactly one style.
struct SegmentedTabs<Item: Identifiable & Equatable, Label: View>: View {
    let items: [Item]
    @Binding var selection: Item
    @ViewBuilder let label: (Item) -> Label

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(items) { item in
                let selected = item == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = item }
                } label: {
                    HStack(spacing: 5) { label(item) }
                        .font(.callout.weight(.medium))
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            selected
                                ? AnyShapeStyle(Theme.accent.opacity(0.16))
                                : AnyShapeStyle(.quaternary.opacity(0.4)),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.control)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.control)
                                .strokeBorder(
                                    selected ? Theme.accent.opacity(0.5) : .clear, lineWidth: 1)
                        )
                        .foregroundStyle(selected ? AnyShapeStyle(Theme.accentFg) : AnyShapeStyle(.secondary))
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Filter field

/// The one search/filter field. Clears on Escape, shows a clear button while
/// non-empty, and focuses on ⌘F.
struct FilterField: View {
    let prompt: String
    @Binding var text: String
    var maxWidth: CGFloat = 320

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand {
                    if text.isEmpty { focused = false } else { text = "" }
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .frame(maxWidth: maxWidth)
        .background(
            // Invisible ⌘F target — the field itself can't carry a shortcut.
            Button("") { focused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
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
                .foregroundStyle(.secondary)
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
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int(min(1, max(0, fraction)) * 100)) percent")
    }
}

// MARK: - Stat cell

/// Fixed contract on every surface: `value` is the number, `label` names the
/// window, `detail` carries the optional cost/annotation. Never pack two facts
/// into one slot.
struct StatCell: View {
    let value: String
    let label: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let detail {
                    Text("· \(detail)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(
            .quaternary.opacity(0.45),
            in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .accessibilityElement(children: .combine)
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

/// Pinned column-header row for hand-built matrices (Skills, MCP).
struct ColumnHeaderText: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .kerning(0.5)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Card

extension View {
    /// The one card surface: secondary background, hairline stroke, card radius.
    func card() -> some View {
        background(
            .background.secondary,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }
}

// MARK: - Floating panel

extension View {
    /// A trailing detail panel that floats *over* its content and slides in/out,
    /// leaving the layout underneath untouched — unlike `.inspector`, which
    /// splits the view and resizes everything beside it. Use for transient,
    /// click-to-open detail; keep `.inspector` for persistent workspace panes.
    ///
    /// Wrap the presenting state change in `withAnimation` so the slide plays.
    func floatingPanel<Content: View>(
        isPresented: Bool,
        width: CGFloat = 300,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        overlay(alignment: .trailing) {
            if isPresented {
                content()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .strokeBorder(.separator, lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 14, x: -4, y: 2)
                    .padding(.trailing, Theme.Space.m)
                    .padding(.vertical, Theme.Space.m)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    var hint: String?
    var actionLabel: String?
    var action: (() -> Void)?

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
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 6)
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
        .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.block))
    }
}
