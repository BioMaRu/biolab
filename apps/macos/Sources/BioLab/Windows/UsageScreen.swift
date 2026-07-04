import SwiftUI

/// Full AI-usage dashboard: one card per agent with live Claude plan limits
/// and local token/cost analytics.
struct UsageScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let usage = state.usage {
                    ForEach(usage.providers) { provider in
                        ProviderCard(provider: provider)
                    }
                    Text(
                        "Token counts come from each agent's local logs. Costs are estimates from public model pricing and may differ from your actual bill."
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                } else {
                    // Skeletons hold the real card layout so nothing jumps
                    // when data lands.
                    ForEach(Self.placeholders) { provider in
                        ProviderCard(provider: provider, placeholder: true)
                    }
                    .redacted(reason: .placeholder)
                    .disabled(true)
                    .accessibilityHidden(true)
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("AI Usage")
    }

    private var header: some View {
        HStack {
            if let usage = state.usage {
                let week = usage.providers.reduce(0.0) { $0 + ($1.window("week")?.cost ?? 0) }
                Label {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Fmt.usd(week)).font(.title3.weight(.semibold)).monospacedDigit()
                        Text("est. · 7 days").font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "dollarsign.circle").foregroundStyle(Theme.accentFg)
                }
            } else {
                Label {
                    Text("Reading usage logs…").font(.callout).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "dollarsign.circle").foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let at = state.usageUpdatedAt {
                Text("updated \(Fmt.ago(at))").font(.callout).foregroundStyle(.tertiary)
            }
            Button {
                Task {
                    await state.refreshUsage()
                    await state.refreshLimits()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan usage")
            .accessibilityLabel("Rescan usage")
        }
    }

    /// Sample data behind the redacted loading state — realistic shapes so the
    /// skeleton matches what real cards will occupy.
    private static let placeholders: [ProviderUsage] = ToolID.allCases.map { id in
        var provider = ProviderUsage(id: id, tracked: true, note: nil)
        provider.windows = [
            WindowStat(
                key: "session", label: "Current session",
                input: 900_000, output: 120_000, cost: 4.2, messages: 96, resetsAt: nil),
            WindowStat(
                key: "today", label: "Today",
                input: 2_400_000, output: 300_000, cost: 11.5, messages: 210, resetsAt: nil),
            WindowStat(
                key: "week", label: "Last 7 days",
                input: 9_000_000, output: 1_100_000, cost: 48, messages: 1_400, resetsAt: nil),
            WindowStat(
                key: "all", label: "All time",
                input: 52_000_000, output: 6_000_000, cost: 240, messages: 9_000, resetsAt: nil),
        ]
        provider.sessions = 42
        return provider
    }
}

private struct ProviderCard: View {
    @Environment(AppState.self) private var state
    let provider: ProviderUsage
    var placeholder = false

    private var hasCost: Bool { (provider.window("all")?.cost ?? 0) > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !provider.tracked {
                if let note = provider.note {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
            } else {
                if provider.id == .claude, !placeholder {
                    limitsBlock
                    SectionLabel(text: "Local activity · estimated")
                } else if let note = provider.note {
                    Text(note).font(.caption).foregroundStyle(.tertiary)
                }

                sessionBlock
                windowGrid

                if !provider.models.isEmpty {
                    breakdown(
                        title: "By model",
                        rows: provider.models.prefix(5).map {
                            (Fmt.model($0.model), $0.total, hasCost ? Fmt.usd($0.cost) : nil)
                        })
                }
                if !provider.projects.isEmpty {
                    breakdown(
                        title: "Top projects",
                        rows: provider.projects.prefix(4).map {
                            (Fmt.projectName($0.path), $0.total, nil)
                        })
                }

                footer
            }
        }
        .padding(Theme.Space.l)
        .card()
    }

    private var header: some View {
        HStack(spacing: 10) {
            AgentGlyph(tool: provider.id)
                .frame(width: 28, height: 28)
                .background(
                    .quaternary.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            Text(provider.name).font(.headline)
            Text(Fmt.ago(provider.lastActive)).font(.caption).foregroundStyle(.tertiary)
            Spacer()
            if !placeholder {
                if provider.id == .claude, let plan = state.limits?.plan {
                    Badge(text: plan, tint: Theme.accentFg)
                }
                if hasCost {
                    Badge(text: Fmt.usd(provider.window("all")?.cost ?? 0), tint: Theme.accentFg)
                        .help("All-time estimated spend")
                }
                if !provider.tracked {
                    Badge(text: "Not tracked")
                }
            }
        }
    }

    @ViewBuilder
    private var limitsBlock: some View {
        if let limits = state.limits {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack {
                    SectionLabel(text: "Plan limits")
                    Spacer()
                    Text("live from Anthropic · \(Fmt.ago(limits.fetchedAt))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                ForEach(limits.bars) { bar in
                    LimitBarRow(bar: bar)
                }
                if let extra = limits.extra, extra.enabled {
                    Divider()
                    HStack {
                        Text("Extra usage").font(.callout.weight(.medium))
                        Spacer()
                        Text(
                            "\(Fmt.money(extra.used, extra.currency)) / \(Fmt.money(extra.limit, extra.currency)) · \(Int(extra.percent.rounded()))%"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    ProgressTrack(fraction: extra.percent / 100)
                }
            }
            .padding(Theme.Space.m)
            .background(
                Theme.accent.opacity(0.05),
                in: RoundedRectangle(cornerRadius: Theme.Radius.block))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.block)
                    .strokeBorder(Theme.accent.opacity(0.16), lineWidth: 1))
        } else if let error = state.limitsError {
            ErrorBanner(message: error) { Task { await state.refreshLimits() } }
        } else if state.limitsLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading plan limits…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sessionBlock: some View {
        if let session = provider.window("session") {
            let active = session.total > 0
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: session.label)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.tokens(session.total))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Text("tokens").font(.caption).foregroundStyle(.tertiary)
                        if hasCost {
                            Text("· \(Fmt.usd(session.cost))")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Theme.accentFg)
                        }
                        Text("· \(session.messages) msgs")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Label(
                        active
                            ? Fmt.reset(session.resetsAt)
                            : "no active window",
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    if active, let resets = session.resetsAt {
                        let elapsed =
                            1 - resets.timeIntervalSinceNow / Const.sessionWindow
                        ProgressTrack(fraction: elapsed, height: 5)
                            .frame(width: 120)
                    }
                }
            }
            .padding(Theme.Space.m)
            .background(
                active ? Theme.accent.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: Theme.Radius.block)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.block)
                    .strokeBorder(
                        active
                            ? AnyShapeStyle(Theme.accent.opacity(0.2))
                            : AnyShapeStyle(.separator),
                        lineWidth: 1))
        }
    }

    private var windowGrid: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(["today", "week", "all"], id: \.self) { key in
                if let w = provider.window(key) {
                    StatCell(
                        value: Fmt.tokens(w.total),
                        label: w.label,
                        detail: hasCost ? Fmt.usd(w.cost) : "\(w.messages) turns"
                    )
                }
            }
        }
    }

    private func breakdown(title: String, rows: [(String, Int64, String?)]) -> some View {
        let maxTotal = max(1, rows.map(\.1).max() ?? 1)
        return VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: title)
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 10) {
                    Text(row.0)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                    ProgressTrack(
                        fraction: Double(row.1) / Double(maxTotal),
                        tint: Theme.accent.opacity(0.75), height: 6)
                    Text(Fmt.tokens(row.1))
                        .font(.callout)
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                    if let cost = row.2 {
                        Text(cost)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("\(provider.sessions) sessions", systemImage: "rectangle.stack")
            if provider.webSearch > 0 {
                Label("\(provider.webSearch)", systemImage: "magnifyingglass")
                    .help("Web search tool calls")
            }
            if provider.webFetch > 0 {
                Label("\(provider.webFetch)", systemImage: "arrow.down.doc")
                    .help("Web fetch tool calls")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
}
