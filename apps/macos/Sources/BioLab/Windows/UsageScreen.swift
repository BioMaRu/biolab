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
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading usage logs…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("AI Usage")
    }

    private var header: some View {
        HStack {
            let week = state.usage?.providers.reduce(0.0) { $0 + ($1.window("week")?.cost ?? 0) } ?? 0
            Label {
                Text("\(Fmt.usd(week)) ").font(.title3.weight(.semibold)).monospacedDigit()
                    + Text("est. · 7 days").font(.callout).foregroundColor(.secondary)
            } icon: {
                Image(systemName: "dollarsign.circle").foregroundStyle(Theme.accentFg)
            }
            Spacer()
            if let at = state.usageUpdatedAt {
                Text("scanned \(Fmt.ago(at))").font(.callout).foregroundStyle(.tertiary)
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
        }
    }
}

private struct ProviderCard: View {
    @Environment(AppState.self) private var state
    let provider: ProviderUsage

    private var hasCost: Bool { (provider.window("all")?.cost ?? 0) > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !provider.tracked {
                if let note = provider.note {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
            } else {
                if provider.id == .claude {
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
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.separator, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 10) {
            AgentGlyph(tool: provider.id)
                .frame(width: 28, height: 28)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            Text(provider.name).font(.headline)
            Text(Fmt.ago(provider.lastActive)).font(.caption).foregroundStyle(.tertiary)
            Spacer()
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

    @ViewBuilder
    private var limitsBlock: some View {
        if let limits = state.limits {
            VStack(alignment: .leading, spacing: 12) {
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
            .padding(13)
            .background(Theme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
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
            .padding(12)
            .background(
                active ? Theme.accent.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        active ? Theme.accent.opacity(0.2) : Color(nsColor: .separatorColor),
                        lineWidth: 1))
        }
    }

    private var windowGrid: some View {
        HStack(spacing: 8) {
            ForEach(["today", "week", "all"], id: \.self) { key in
                if let w = provider.window(key) {
                    StatCell(
                        value: Fmt.tokens(w.total),
                        label: hasCost ? "\(w.label) · \(Fmt.usd(w.cost))" : "\(w.label) · \(w.messages) turns"
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
