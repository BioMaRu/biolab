import SwiftUI

/// Port manager: sortable native table of listening TCP ports with search,
/// quick-kill chips for common + favorite ports, an inspector for details,
/// and kill / force-kill via toolbar, context menu, or ⌫.
struct PortsScreen: View {
    @Environment(AppState.self) private var state

    @State private var query = ""
    @State private var selection = Set<PortInfo.ID>()
    @State private var sortOrder = [KeyPathComparator(\PortInfo.port)]
    @State private var confirmKill: KillRequest?
    @State private var quickKillPort: Int?
    @State private var newFavorite = ""
    @State private var addingFavorite = false
    @State private var showInspector = false
    @State private var actionError: String?

    struct KillRequest {
        let ports: [PortInfo]
        let force: Bool
    }

    private var filtered: [PortInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matches =
            q.isEmpty
            ? state.ports
            : state.ports.filter {
                String($0.port).contains(q) || String($0.pid).contains(q)
                    || $0.processName.lowercased().contains(q)
                    || $0.command.lowercased().contains(q)
                    || $0.address.lowercased().contains(q)
            }
        return matches.sorted(using: sortOrder)
    }

    private var selectedPorts: [PortInfo] {
        filtered.filter { selection.contains($0.id) }
    }

    private var quickKillPorts: [Int] {
        Array(Set(Const.commonPorts).union(state.favoritePorts)).sorted()
    }

    /// True while any confirmation UI is up — the auto-refresh pauses so rows
    /// don't shift under a pending decision.
    private var interactionPending: Bool {
        confirmKill != nil || quickKillPort != nil || addingFavorite
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            quickKill
            Divider()

            if let error = state.portsError {
                ErrorBanner(message: error) { Task { await state.refreshPorts() } }
                    .padding(Theme.Space.m)
            }

            if !state.portsLoadedOnce {
                Spacer()
                ProgressView("Scanning ports…")
                Spacer()
            } else if filtered.isEmpty {
                if query.isEmpty {
                    EmptyStateView(
                        icon: "network.slash", title: "No listening ports",
                        hint: "Nothing is bound right now. Start a dev server and it shows up here.",
                        actionLabel: "Refresh",
                        action: { Task { await state.refreshPorts() } }
                    )
                } else {
                    EmptyStateView(
                        icon: "magnifyingglass", title: "No matching ports",
                        hint: "Nothing matches “\(query)”.",
                        actionLabel: "Clear Filter",
                        action: { query = "" }
                    )
                }
            } else {
                table
            }
        }
        .inspector(isPresented: $showInspector) {
            PortInspector(
                ports: selectedPorts,
                onKill: { requestKill(force: false) },
                onForceKill: { requestKill(force: true) }
            )
            .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .navigationTitle("Ports")
        .task {
            await state.refreshPorts()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if !interactionPending {
                    await state.refreshPorts()
                }
            }
        }
        .confirmationDialog(
            killTitle,
            isPresented: Binding(get: { confirmKill != nil }, set: { if !$0 { confirmKill = nil } })
        ) {
            Button(confirmKill?.force == true ? "Force Kill" : "Kill", role: .destructive) {
                if let request = confirmKill {
                    execute(request)
                }
            }
        } message: {
            if let request = confirmKill, request.ports.count > 1 {
                Text(request.ports.map { "\($0.processName) (\($0.port))" }.joined(separator: ", "))
            }
        }
        .confirmationDialog(
            "Kill everything on port \(quickKillPort ?? 0)?",
            isPresented: Binding(get: { quickKillPort != nil }, set: { if !$0 { quickKillPort = nil } })
        ) {
            Button("Kill", role: .destructive) {
                if let port = quickKillPort {
                    execute(
                        KillRequest(ports: state.ports.filter { $0.port == port }, force: false))
                }
            }
        }
        .alert(
            "Action failed",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var killTitle: String {
        guard let request = confirmKill else { return "" }
        let verb = request.force ? "Force kill" : "Kill"
        if request.ports.count == 1, let p = request.ports.first {
            return "\(verb) \(p.processName) (PID \(p.pid)) on port \(p.port)?"
        }
        return "\(verb) \(request.ports.count) processes?"
    }

    private func requestKill(force: Bool) {
        let ports = selectedPorts
        guard !ports.isEmpty else { return }
        confirmKill = KillRequest(ports: ports, force: force)
    }

    private func execute(_ request: KillRequest) {
        Task {
            var errors: [String] = []
            for port in request.ports {
                if let error = await state.killProcess(pid: port.pid, force: request.force) {
                    errors.append(error)
                }
            }
            actionError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: Theme.Space.m) {
            FilterField(prompt: "Filter by port, process, PID, address…", text: $query)

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
                requestKill(force: false)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .disabled(selectedPorts.isEmpty)
            .help("Kill selected (SIGTERM)")
            .accessibilityLabel("Kill selected process")

            Button {
                requestKill(force: true)
            } label: {
                Image(systemName: "bolt.circle")
            }
            .disabled(selectedPorts.isEmpty)
            .help("Force kill selected (SIGKILL)")
            .accessibilityLabel("Force kill selected process")

            Button {
                showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Details")
            .accessibilityLabel("Toggle details inspector")

            Button {
                Task { await state.refreshPorts() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .accessibilityLabel("Refresh ports")
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
    }

    // MARK: Quick-kill

    private var quickKill: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Label("Quick-kill", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(quickKillPorts, id: \.self) { port in
                    let active = state.ports.contains { $0.port == port }
                    Button {
                        quickKillPort = port
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
                    .disabled(!active)
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
                    FavoritePortField(
                        text: $newFavorite,
                        onSubmit: {
                            if let n = Int(newFavorite), n > 0, n < 65536 {
                                var favorites = state.favoritePorts
                                if !favorites.contains(n) { favorites.append(n) }
                                state.favoritePorts = favorites
                            }
                            newFavorite = ""
                            addingFavorite = false
                        },
                        onCancel: {
                            newFavorite = ""
                            addingFavorite = false
                        }
                    )
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
                    .accessibilityLabel("Add favorite port")
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
        }
    }

    // MARK: Table

    private var table: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Port", value: \.port) { port in
                Text(String(port.port))
                    .font(.callout.weight(.semibold))
                    .monospaced()
            }
            .width(min: 52, ideal: 64, max: 90)

            TableColumn("Process", value: \.processName) { port in
                Text(port.processName)
                    .lineLimit(1)
                    .help(port.command)
            }

            TableColumn("PID", value: \.pid) { port in
                Text(String(port.pid))
                    .font(.callout)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 64, max: 90)

            TableColumn("Address", value: \.address) { port in
                Text(port.address)
                    .font(.callout)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 140, max: 200)
        }
        .contextMenu(forSelectionType: PortInfo.ID.self) { ids in
            let ports = filtered.filter { ids.contains($0.id) }
            if !ports.isEmpty {
                Button("Kill") { confirmKill = KillRequest(ports: ports, force: false) }
                Button("Force Kill") { confirmKill = KillRequest(ports: ports, force: true) }
                Divider()
                if ports.count == 1, let port = ports.first {
                    Button("Copy Command") { copy(port.command) }
                    Button("Copy Port") { copy(String(port.port)) }
                }
            }
        } primaryAction: { ids in
            selection = ids
            showInspector = true
        }
        .onDeleteCommand {
            requestKill(force: false)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Favorite port field

private struct FavoritePortField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        TextField("port", text: $text)
            .textFieldStyle(.plain)
            .font(.caption)
            .monospacedDigit()
            .frame(width: 48)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.4), in: Capsule())
            .focused($focused)
            .onSubmit(onSubmit)
            .onExitCommand(perform: onCancel)
            .onAppear { focused = true }
    }
}

// MARK: - Inspector

private struct PortInspector: View {
    let ports: [PortInfo]
    let onKill: () -> Void
    let onForceKill: () -> Void

    var body: some View {
        if ports.isEmpty {
            EmptyStateView(
                icon: "sidebar.trailing", title: "No port selected",
                hint: "Select a row to see the full command, user, and actions.")
        } else if ports.count > 1 {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("\(ports.count) processes selected").font(.headline)
                Text(ports.map { "\($0.processName) (\($0.port))" }.joined(separator: "\n"))
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
                killButtons
                Spacer()
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let port = ports.first {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(port.processName).font(.headline)
                        Text("PID \(port.pid) · \(port.user.isEmpty ? "—" : port.user)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    HStack(spacing: 6) {
                        Badge(text: "\(port.protocolName) \(port.port)", tint: Theme.accentFg)
                        Badge(text: port.address)
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        SectionLabel(text: "Command")
                        Text(port.command)
                            .font(.caption)
                            .monospaced()
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Space.s)
                            .background(
                                .quaternary.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                        CopyButton(text: port.command, label: "Copy Command")
                    }

                    Divider()
                    killButtons
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var killButtons: some View {
        HStack {
            Button("Kill", action: onKill)
                .controlSize(.small)
            Button("Force Kill", role: .destructive, action: onForceKill)
                .controlSize(.small)
        }
    }
}

/// Copy-to-pasteboard button with a brief "Copied" acknowledgement.
struct CopyButton: View {
    let text: String
    var label = "Copy"

    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : label) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
        }
        .controlSize(.small)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
