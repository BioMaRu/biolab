import SwiftUI

/// Port manager: live table of listening TCP ports with search, quick-kill
/// chips for common + favorite ports, and kill / force-kill actions.
struct PortsScreen: View {
    @Environment(AppState.self) private var state

    @State private var query = ""
    @State private var confirmKill: (port: PortInfo, force: Bool)?
    @State private var quickKillPort: Int?
    @State private var newFavorite = ""
    @State private var addingFavorite = false
    @State private var expanded: String?
    @State private var actionError: String?

    private var filtered: [PortInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return state.ports }
        return state.ports.filter {
            String($0.port).contains(q) || String($0.pid).contains(q)
                || $0.processName.lowercased().contains(q)
                || $0.command.lowercased().contains(q)
                || $0.address.lowercased().contains(q)
        }
    }

    private var quickKillPorts: [Int] {
        Array(Set(Const.commonPorts).union(state.favoritePorts)).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            quickKill
            Divider()

            if let error = state.portsError {
                ErrorBanner(message: error) { Task { await state.refreshPorts() } }
                    .padding(12)
            }

            if !state.portsLoadedOnce {
                Spacer()
                ProgressView("Scanning ports…")
                Spacer()
            } else if filtered.isEmpty {
                if query.isEmpty {
                    EmptyStateView(
                        icon: "network.slash", title: "No listening ports",
                        hint: "Nothing is bound right now. Start a dev server and hit refresh to see it here."
                    )
                } else {
                    EmptyStateView(
                        icon: "magnifyingglass", title: "No matching ports",
                        hint: "Nothing matches “\(query)”.")
                }
            } else {
                list
            }
        }
        .navigationTitle("Ports")
        .task {
            await state.refreshPorts()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await state.refreshPorts()
            }
        }
        .confirmationDialog(
            confirmKill.map {
                "\($0.force ? "Force kill" : "Kill") \($0.port.processName) (PID \($0.port.pid)) on port \($0.port.port)?"
            } ?? "",
            isPresented: Binding(get: { confirmKill != nil }, set: { if !$0 { confirmKill = nil } })
        ) {
            Button(confirmKill?.force == true ? "Force Kill" : "Kill", role: .destructive) {
                if let target = confirmKill {
                    Task {
                        actionError = await state.killProcess(pid: target.port.pid, force: target.force)
                    }
                }
            }
        }
        .confirmationDialog(
            "Kill everything on port \(quickKillPort ?? 0)?",
            isPresented: Binding(get: { quickKillPort != nil }, set: { if !$0 { quickKillPort = nil } })
        ) {
            Button("Kill", role: .destructive) {
                if let port = quickKillPort {
                    Task {
                        for p in state.ports where p.port == port {
                            actionError = await state.killProcess(pid: p.pid, force: false)
                        }
                    }
                }
            }
        }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("Filter by port, process, PID, address…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 420)

            Spacer()

            Text(
                query.isEmpty
                    ? "\(state.ports.count) listening"
                    : "\(filtered.count) of \(state.ports.count)"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            Button {
                Task { await state.refreshPorts() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var quickKill: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Label("Quick-kill", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(quickKillPorts, id: \.self) { port in
                    let active = state.ports.contains { $0.port == port }
                    Button {
                        if active { quickKillPort = port }
                    } label: {
                        Text(String(port))
                            .font(.caption)
                            .monospacedDigit()
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(
                                active
                                    ? AnyShapeStyle(Theme.danger.opacity(0.14))
                                    : AnyShapeStyle(.quaternary.opacity(0.4)),
                                in: Capsule()
                            )
                            .foregroundStyle(
                                active
                                    ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(.tertiary))
                    }
                    .buttonStyle(.plain)
                    .help(active ? "Kill process on port \(port)" : "Port \(port) is free")
                    .contextMenu {
                        if !Const.commonPorts.contains(port) {
                            Button("Remove Favorite") {
                                state.favoritePorts.removeAll { $0 == port }
                            }
                        }
                    }
                }

                if addingFavorite {
                    TextField("port", text: $newFavorite)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onSubmit {
                            if let n = Int(newFavorite), n > 0, n < 65536 {
                                var favorites = state.favoritePorts
                                if !favorites.contains(n) { favorites.append(n) }
                                state.favoritePorts = favorites
                            }
                            newFavorite = ""
                            addingFavorite = false
                        }
                } else {
                    Button {
                        addingFavorite = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary.opacity(0.4), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add a favorite quick-kill port")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(filtered) { port in
                        VStack(spacing: 0) {
                            PortTableRow(
                                port: port,
                                expanded: expanded == port.id,
                                onToggle: { expanded = expanded == port.id ? nil : port.id },
                                onKill: { confirmKill = (port, false) },
                                onForceKill: { confirmKill = (port, true) }
                            )
                            if expanded == port.id {
                                PortDetail(port: port)
                            }
                            Divider().opacity(0.5)
                        }
                    }
                } header: {
                    HStack {
                        Text("PORT").frame(width: 64, alignment: .leading)
                        Text("PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                        Text("PID").frame(width: 70, alignment: .leading)
                        Text("ADDRESS").frame(width: 140, alignment: .leading)
                        Spacer().frame(width: 96)
                    }
                    .font(.caption2.weight(.semibold))
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.bar)
                }
            }
        }
    }
}

private struct PortTableRow: View {
    let port: PortInfo
    let expanded: Bool
    let onToggle: () -> Void
    let onKill: () -> Void
    let onForceKill: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack {
            Text(String(port.port))
                .font(.callout.weight(.semibold))
                .monospaced()
                .frame(width: 64, alignment: .leading)
            Text(port.processName)
                .lineLimit(1)
                .help(port.command)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(port.pid))
                .font(.callout)
                .monospaced()
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(port.address)
                .font(.callout)
                .monospaced()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            HStack(spacing: 2) {
                if hovering || expanded {
                    Button(action: onToggle) {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Details")
                    Button(action: onKill) {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.danger)
                    .help("Kill (SIGTERM)")
                    Button(action: onForceKill) {
                        Image(systemName: "bolt.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.warning)
                    .help("Force kill (SIGKILL)")
                }
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.35)) : AnyShapeStyle(.clear))
        .onHover { hovering = $0 }
    }
}

private struct PortDetail: View {
    let port: PortInfo
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Command")
            Text(port.command)
                .font(.caption)
                .monospaced()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SectionLabel(text: "User")
                Text(port.user.isEmpty ? "—" : port.user).font(.caption)
                Spacer()
                Button(copied ? "Copied" : "Copy command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(port.command, forType: .string)
                    copied = true
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25))
    }
}
