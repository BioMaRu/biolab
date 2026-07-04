import SwiftUI

/// The menu-bar popover: BioLab's quick surface. Two tabs — AI Usage (default)
/// and Ports — with a footer for the full window, refresh and quit.
struct MenuBarPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @AppStorage("panel.tab") private var tabRaw = PanelTab.usage.rawValue

    enum PanelTab: String, CaseIterable {
        case usage, ports

        var title: String {
            switch self {
            case .usage: "AI Usage"
            case .ports: "Ports"
            }
        }

        var icon: String {
            switch self {
            case .usage: "waveform.path.ecg"
            case .ports: "network"
            }
        }
    }

    private var tab: PanelTab { PanelTab(rawValue: tabRaw) ?? .usage }

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider()

            ScrollView {
                switch tab {
                case .usage: UsageTab()
                case .ports: PortsTab()
                }
            }
            .frame(maxHeight: 480)

            Divider()
            footer
        }
        .frame(width: 356)
        .task {
            state.bootstrap()
            await state.refreshPorts()
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases, id: \.rawValue) { t in
                Button {
                    tabRaw = t.rawValue
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: t.icon).font(.caption)
                        Text(t.title).font(.callout.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        tab == t ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .foregroundStyle(tab == t ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                openWindow(id: "main")
                dismiss()
            } label: {
                Label("Open BioLab", systemImage: "macwindow")
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentFg)
            .keyboardShortcut("o", modifiers: .command)

            Button {
                Task { await state.refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise").font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("r", modifiers: .command)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power").font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .keyboardShortcut("q", modifiers: .command)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

// MARK: - AI Usage tab

private struct UsageTab: View {
    @Environment(AppState.self) private var state
    @AppStorage("panel.agent") private var agentRaw = ToolID.claude.rawValue

    private var agent: ToolID { ToolID(rawValue: agentRaw) ?? .claude }
    private var provider: ProviderUsage? { state.usage?.provider(agent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            agentPicker

            if let provider {
                header(provider)

                if agent == .claude {
                    claudeLimits
                }

                if provider.tracked {
                    if agent != .claude, let note = provider.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    stats(provider)
                    if let top = provider.models.first {
                        Text("Top model: **\(Fmt.model(top.model))** · active \(Fmt.ago(provider.lastActive))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let note = provider.note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if agent == .claude, let extra = state.limits?.extra, extra.enabled {
                    Divider()
                    extraUsage(extra)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading usage logs…").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(12)
    }

    private var agentPicker: some View {
        HStack(spacing: 4) {
            ForEach(ToolID.allCases) { tool in
                Button {
                    agentRaw = tool.rawValue
                } label: {
                    HStack(spacing: 5) {
                        AgentGlyph(tool: tool, size: 11)
                        Text(tool.shortName).font(.callout.weight(.medium))
                    }
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        agent == tool
                            ? AnyShapeStyle(Theme.accent.opacity(0.16))
                            : AnyShapeStyle(.quaternary.opacity(0.4)),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                agent == tool ? Theme.accent.opacity(0.5) : .clear, lineWidth: 1)
                    )
                    .foregroundStyle(agent == tool ? Theme.accentFg : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func header(_ provider: ProviderUsage) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(provider.name).font(.headline)
            Text(updatedLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            if agent == .claude, let plan = state.limits?.plan {
                Badge(text: plan, tint: Theme.accentFg)
            }
        }
    }

    private var updatedLabel: String {
        guard let at = state.usageUpdatedAt else { return "updating…" }
        return "updated \(Fmt.ago(at))"
    }

    @ViewBuilder
    private var claudeLimits: some View {
        if let limits = state.limits {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(limits.bars) { bar in
                    LimitBarRow(bar: bar, compact: true)
                }
            }
            .padding(12)
            .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1)
            )
        } else if state.limitsLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading plan limits…").font(.callout).foregroundStyle(.secondary)
            }
        } else if let error = state.limitsError {
            ErrorBanner(message: error) {
                Task { await state.refreshLimits() }
            }
        }
    }

    private func stats(_ provider: ProviderUsage) -> some View {
        let hasCost = (provider.window("all")?.cost ?? 0) > 0
        func line(_ key: String) -> String {
            guard let w = provider.window(key) else { return "—" }
            return hasCost ? "\(Fmt.tokens(w.total)) · \(Fmt.usd(w.cost))" : Fmt.tokens(w.total)
        }
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Local activity · estimated")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8
            ) {
                StatCell(value: line("today"), label: "Today")
                StatCell(value: line("week"), label: "Last 7 days")
                StatCell(value: line("all"), label: "All time")
                StatCell(value: "\(provider.sessions)", label: "Sessions")
            }
        }
    }

    private func extraUsage(_ extra: ExtraUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Extra usage").font(.callout.weight(.semibold))
                Spacer()
                Text("\(Int(extra.percent.rounded()))% used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressTrack(fraction: extra.percent / 100)
            Text(
                "Monthly cap: \(Fmt.money(extra.used, extra.currency)) / \(Fmt.money(extra.limit, extra.currency))"
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }
}

// MARK: - Ports tab

private struct PortsTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: "Listening ports")
                Spacer()
                Text("\(state.ports.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)

            if let error = state.portsError {
                ErrorBanner(message: error) {
                    Task { await state.refreshPorts() }
                }
            } else if state.ports.isEmpty {
                EmptyStateView(
                    icon: "network.slash", title: "No listening ports",
                    hint: "Start a dev server and refresh."
                )
                .frame(minHeight: 140)
            } else {
                ForEach(state.ports.prefix(16)) { port in
                    PortRow(port: port)
                }
                if state.ports.count > 16 {
                    Text("+\(state.ports.count - 16) more · open BioLab")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
        }
        .padding(10)
        .task { await state.refreshPorts() }
    }
}

private struct PortRow: View {
    @Environment(AppState.self) private var state
    let port: PortInfo
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Text(String(port.port))
                .font(.callout.weight(.semibold))
                .monospaced()
                .frame(width: 52, alignment: .leading)
            Text(port.processName)
                .font(.callout)
                .lineLimit(1)
                .help(port.command)
            Spacer()
            Text(String(port.pid))
                .font(.caption)
                .monospaced()
                .foregroundStyle(.tertiary)
            Button {
                Task { _ = await state.killProcess(pid: port.pid, force: false) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(
                        hovering ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(.quaternary))
            }
            .buttonStyle(.plain)
            .help("Kill \(port.processName) (SIGTERM)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
    }
}
