import SwiftUI

/// Cross-agent control center: Overview, MCP matrix, Skills, Symlinks and
/// Context files across Claude Code, Codex and OpenCode.
struct AgentsScreen: View {
    @Environment(AppState.self) private var state

    enum Section: String, CaseIterable, Identifiable {
        case overview, mcp, skills, symlinks, context
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: "Overview"
            case .mcp: "MCP"
            case .skills: "Skills"
            case .symlinks: "Symlinks"
            case .context: "Context"
            }
        }
    }

    @State private var section: Section = .overview
    @State private var actionError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if state.inventory == nil {
                Spacer()
                ProgressView("Scanning your agents…")
                Spacer()
            } else {
                switch section {
                case .overview: OverviewSection(jump: { section = $0 })
                case .mcp: McpSection(actionError: $actionError)
                case .skills: SkillsSection(actionError: $actionError)
                case .symlinks: SymlinksSection(actionError: $actionError)
                case .context: ContextSection(actionError: $actionError)
                }
            }
        }
        .navigationTitle("Agents")
        .task { await state.refreshAgents() }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("", selection: $section) {
                ForEach(Section.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            // Live agent presence
            HStack(spacing: 4) {
                ForEach(state.inventory?.tools ?? [], id: \.id) { tool in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(tool.installed ? Theme.success : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(tool.id.shortName).font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.4), in: Capsule())
                    .foregroundStyle(tool.installed ? .secondary : .tertiary)
                    .help(tool.installed ? "\(tool.id.displayName) — installed" : "\(tool.id.displayName) — not found")
                }
            }

            Button {
                Task { await state.refreshAgents() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan agents")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Overview

private struct OverviewSection: View {
    @Environment(AppState.self) private var state
    let jump: (AgentsScreen.Section) -> Void

    var body: some View {
        let inv = state.inventory ?? AgentInventory()
        let broken = inv.symlinks.filter(\.broken).count

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Fleet
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel(text: "Your agents")
                    HStack(spacing: 10) {
                        ForEach(inv.tools, id: \.id) { tool in
                            FleetCard(tool: tool, inventory: inv)
                        }
                    }
                }

                // Health
                if broken > 0 {
                    Button {
                        jump(.symlinks)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.danger)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(broken) broken symlink\(broken > 1 ? "s" : "")")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(Theme.danger)
                                Text("The target no longer exists — repair or remove.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label("Fix in Symlinks", systemImage: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.danger)
                        }
                        .padding(12)
                        .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(Theme.danger.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(Theme.success)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Everything's in sync").font(.callout.weight(.semibold))
                            Text(
                                "\(inv.tools.filter(\.installed).count) of \(inv.tools.count) agents installed · no broken links."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Theme.success.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Theme.success.opacity(0.22), lineWidth: 1))
                }

                // At a glance
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel(text: "At a glance")
                    let uniqueNames = state.mcpNames.count
                    let disabled =
                        inv.disabled.count + inv.mcpServers.filter { !$0.enabled }.count
                    let skills = Set(inv.skills.map(\.name)).count
                    let contexts = inv.contextFiles.filter(\.exists).count
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                        spacing: 10
                    ) {
                        GlanceTile(icon: "powerplug", value: uniqueNames, label: "MCP servers") { jump(.mcp) }
                        GlanceTile(icon: "poweroff", value: disabled, label: "Disabled") { jump(.mcp) }
                        GlanceTile(icon: "sparkles", value: skills, label: "Skills") { jump(.skills) }
                        GlanceTile(icon: "link", value: inv.symlinks.count, label: "Symlinks") { jump(.symlinks) }
                        GlanceTile(icon: "doc.text", value: contexts, label: "Context files") { jump(.context) }
                    }
                }

                // Central store
                HStack(spacing: 10) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Central skill store").font(.callout.weight(.medium))
                        Text(Paths.tilde(inv.centralSkillsDir))
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            URL(fileURLWithPath: inv.centralSkillsDir)
                        ])
                    }
                    .controlSize(.small)
                }
                .padding(11)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
            }
            .padding(16)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FleetCard: View {
    let tool: AgentTool
    let inventory: AgentInventory

    var body: some View {
        let mcp = inventory.mcpServers.filter { $0.tool == tool.id.rawValue }.count
        let skills = inventory.skills.filter { $0.tool == tool.id.rawValue }.count

        VStack(alignment: .leading, spacing: 11) {
            HStack {
                AgentGlyph(tool: tool.id)
                    .frame(width: 26, height: 26)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Text(tool.id.displayName).font(.callout.weight(.semibold))
                Spacer()
                Badge(
                    text: tool.installed ? "Installed" : "Not found",
                    tint: tool.installed ? Theme.success : .secondary)
            }
            if tool.installed {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(mcp)").font(.title3.weight(.semibold)).monospacedDigit()
                        Text("MCP").font(.caption2).foregroundStyle(.tertiary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(skills)").font(.title3.weight(.semibold)).monospacedDigit()
                        Text("skills").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Text(Paths.tilde(tool.configPath))
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text("Not detected on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 1))
        .opacity(tool.installed ? 1 : 0.65)
    }
}

private struct GlanceTile: View {
    let icon: String
    let value: Int
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.accentFg)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(value)").font(.title3.weight(.semibold)).monospacedDigit()
                    Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(11)
            .background(
                hovering ? Theme.accent.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        hovering ? Theme.accent.opacity(0.35) : Color(nsColor: .separatorColor),
                        lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - MCP matrix

private struct McpSection: View {
    @Environment(AppState.self) private var state
    @Binding var actionError: String?

    @State private var query = ""
    @State private var selection: (name: String, tool: ToolID)?
    @State private var editor: McpEditorContext?
    @State private var confirmRemove = false

    private var names: [String] {
        let q = query.lowercased()
        return state.mcpNames.filter { q.isEmpty || $0.lowercased().contains(q) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if state.mcpNames.isEmpty {
                    EmptyStateView(
                        icon: "powerplug", title: "No MCP servers yet",
                        hint: "Connect a Model Context Protocol server to give your agents new tools."
                    )
                } else {
                    matrix
                }
            }
            .frame(minWidth: 460)

            if let sel = selection {
                inspector(sel)
                    .frame(minWidth: 260, idealWidth: 290, maxWidth: 340)
            }
        }
        .sheet(item: $editor) { context in
            McpEditorSheet(context: context, actionError: $actionError) {
                editor = nil
            }
        }
    }

    private var toolbar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("Filter servers…", text: $query).textFieldStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 260)

            Text("\(names.count) of \(state.mcpNames.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Spacer()

            Button {
                editor = McpEditorContext(initial: nil, fixedTool: nil)
            } label: {
                Label("Add server", systemImage: "plus")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var matrix: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(names, id: \.self) { name in
                        row(name)
                        Divider().opacity(0.5)
                    }
                } header: {
                    HStack {
                        Text("SERVER").frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(ToolID.allCases) { tool in
                            Text(tool.shortName.uppercased()).frame(width: 86)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar)
                }
            }
        }
    }

    private func row(_ name: String) -> some View {
        let reach = ToolID.allCases.filter { state.mcpCell(name: name, tool: $0).configured }.count
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.callout.weight(.medium)).monospaced()
                Text("\(reach)/\(ToolID.allCases.count) agents")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(ToolID.allCases) { tool in
                cellButton(name: name, tool: tool).frame(width: 86)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            selection?.name == name
                ? AnyShapeStyle(Theme.accent.opacity(0.05)) : AnyShapeStyle(.clear))
    }

    private func cellButton(name: String, tool: ToolID) -> some View {
        let cell = state.mcpCell(name: name, tool: tool)
        let isSelected = selection?.name == name && selection?.tool == tool
        return Button {
            if cell.configured {
                selection = (name, tool)
            } else {
                editor = McpEditorContext(initial: state.mcpAnyDefinition(name), fixedTool: tool)
            }
        } label: {
            Group {
                if cell.configured {
                    HStack(spacing: 5) {
                        Circle().fill(cell.on ? Theme.success : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(cell.on ? "On" : "Off").font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        (cell.on ? Theme.success : Color.secondary).opacity(0.12),
                        in: Capsule()
                    )
                    .foregroundStyle(cell.on ? Theme.success : .secondary)
                } else {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 5)
                        .frame(width: 46)
                }
            }
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Theme.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .help(
            cell.configured
                ? (cell.on ? "Enabled — click to manage" : "Disabled — click to manage")
                : "Copy “\(name)” to \(tool.displayName)")
    }

    @ViewBuilder
    private func inspector(_ sel: (name: String, tool: ToolID)) -> some View {
        let cell = state.mcpCell(name: sel.name, tool: sel.tool)
        if let server = cell.server {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(server.name).font(.headline).monospaced()
                            Text("in \(sel.tool.displayName)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button {
                            selection = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack(spacing: 6) {
                        Badge(
                            text: server.transport,
                            tint: .secondary)
                        Badge(
                            text: cell.on ? "enabled" : "disabled",
                            tint: cell.on ? Theme.success : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if server.transport == "http" {
                            SectionLabel(text: "URL")
                            defBox(server.url ?? "—")
                        } else {
                            SectionLabel(text: "Command")
                            defBox(([server.command ?? ""] + server.args).joined(separator: " "))
                            if !server.env.isEmpty {
                                SectionLabel(text: "Env")
                                defBox(server.env.keys.sorted().joined(separator: ", "))
                            }
                        }
                    }

                    Divider()

                    Toggle(
                        "Enabled",
                        isOn: Binding(
                            get: { cell.on },
                            set: { on in
                                Task {
                                    actionError = await state.mutateAgents {
                                        try AgentsService.mcpSetEnabled(server, enabled: on)
                                    }
                                }
                            })
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    HStack {
                        Button("Edit") {
                            editor = McpEditorContext(initial: server, fixedTool: sel.tool)
                        }
                        Button("Remove", role: .destructive) { confirmRemove = true }
                    }
                    .controlSize(.small)

                    let missing = ToolID.allCases.filter {
                        !state.mcpCell(name: sel.name, tool: $0).configured
                    }
                    if !missing.isEmpty {
                        Divider()
                        SectionLabel(text: "Copy to other agents")
                        ForEach(missing) { tool in
                            Button {
                                Task {
                                    actionError = await state.mutateAgents {
                                        try AgentsService.mcpSync(server, targets: [tool.rawValue])
                                    }
                                }
                            } label: {
                                Label(tool.displayName, systemImage: "plus")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(14)
            }
            .background(.background.secondary)
            .confirmationDialog(
                "Remove “\(sel.name)” from \(sel.tool.displayName)?",
                isPresented: $confirmRemove
            ) {
                Button("Remove", role: .destructive) {
                    Task {
                        actionError = await state.mutateAgents {
                            try AgentsService.mcpRemove(tool: sel.tool.rawValue, name: sel.name)
                        }
                        selection = nil
                    }
                }
            }
        } else {
            EmptyStateView(icon: "powerplug", title: "Not configured here")
        }
    }

    private func defBox(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .monospaced()
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - MCP editor sheet

struct McpEditorContext: Identifiable {
    let initial: McpServer?
    let fixedTool: ToolID?
    var id: String { "\(initial?.name ?? "new"):\(fixedTool?.rawValue ?? "any")" }
}

private struct McpEditorSheet: View {
    @Environment(AppState.self) private var state
    let context: McpEditorContext
    @Binding var actionError: String?
    let dismiss: () -> Void

    @State private var name = ""
    @State private var transport = "stdio"
    @State private var command = ""
    @State private var argsText = ""
    @State private var envText = ""
    @State private var url = ""
    @State private var targets: Set<ToolID> = [.claude]
    @State private var saving = false
    @State private var localError: String?

    private var isEditing: Bool { context.initial != nil && context.fixedTool != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "Edit MCP server" : "Add MCP server").font(.headline)

            Form {
                TextField("Name", text: $name)
                    .disabled(isEditing)

                if context.fixedTool == nil {
                    HStack {
                        Text("Add to")
                        ForEach(ToolID.allCases) { tool in
                            Toggle(
                                tool.shortName,
                                isOn: Binding(
                                    get: { targets.contains(tool) },
                                    set: { on in
                                        if on { targets.insert(tool) } else { targets.remove(tool) }
                                    })
                            )
                            .toggleStyle(.button)
                        }
                    }
                }

                Picker("Transport", selection: $transport) {
                    Text("stdio (local)").tag("stdio")
                    Text("http (remote)").tag("http")
                }
                .pickerStyle(.segmented)

                if transport == "stdio" {
                    TextField("Command", text: $command, prompt: Text("npx"))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Arguments — one per line").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $argsText)
                            .font(.callout.monospaced())
                            .frame(height: 58)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Environment — KEY=value per line").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $envText)
                            .font(.callout.monospaced())
                            .frame(height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
                    }
                } else {
                    TextField("URL", text: $url, prompt: Text("https://example.com/mcp"))
                }
            }
            .formStyle(.columns)

            if let localError {
                Text(localError).font(.caption).foregroundStyle(Theme.danger)
            }

            HStack {
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                Button(saving ? "Saving…" : (isEditing ? "Save" : "Add")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear(perform: seed)
    }

    private func seed() {
        guard let initial = context.initial else {
            if let fixed = context.fixedTool { targets = [fixed] }
            return
        }
        name = initial.name
        transport = initial.transport
        command = initial.command ?? ""
        argsText = initial.args.joined(separator: "\n")
        envText = initial.env.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        url = initial.url ?? ""
        if let fixed = context.fixedTool { targets = [fixed] }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            localError = "Name is required."
            return
        }
        guard !targets.isEmpty else {
            localError = "Pick at least one agent."
            return
        }
        var env: [String: String] = [:]
        for line in envText.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "="), eq != trimmed.startIndex else { continue }
            env[String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)] =
                String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        }
        let args = argsText.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let base = McpServer(
            name: trimmedName,
            tool: targets.first!.rawValue,
            transport: transport,
            command: transport == "stdio" ? (command.isEmpty ? nil : command) : nil,
            args: transport == "stdio" ? args : [],
            env: transport == "stdio" ? env : [:],
            url: transport == "http" ? (url.isEmpty ? nil : url) : nil
        )

        saving = true
        let targetIDs = targets.map(\.rawValue)
        Task {
            actionError = await state.mutateAgents {
                try AgentsService.mcpSync(base, targets: targetIDs)
            }
            saving = false
            dismiss()
        }
    }
}

// MARK: - Skills

private struct SkillsSection: View {
    @Environment(AppState.self) private var state
    @Binding var actionError: String?

    @State private var query = ""
    @State private var viewing: (name: String, content: String)?
    @State private var unlink: Skill?

    private struct Group: Identifiable {
        let name: String
        var description: String?
        var byTool: [String: Skill] = [:]
        var id: String { name }
    }

    private var groups: [Group] {
        var map: [String: Group] = [:]
        for skill in state.inventory?.skills ?? [] {
            var group = map[skill.name] ?? Group(name: skill.name)
            group.byTool[skill.tool] = skill
            if group.description == nil { group.description = skill.description }
            map[skill.name] = group
        }
        let q = query.lowercased()
        return map.values
            .filter {
                q.isEmpty || $0.name.lowercased().contains(q)
                    || ($0.description?.lowercased().contains(q) ?? false)
            }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Filter skills…", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                .frame(maxWidth: 260)

                Text("One source in ~/.agents/skills, linked everywhere.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if groups.isEmpty && query.isEmpty {
                EmptyStateView(
                    icon: "sparkles", title: "No skills found",
                    hint: "Skills are reusable instruction folders your agents can load.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            skillRow(group)
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
        .sheet(
            isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })
        ) {
            if let viewing {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("\(viewing.name)/SKILL.md", systemImage: "doc.text")
                            .font(.headline)
                        Spacer()
                        Button("Done") { self.viewing = nil }.keyboardShortcut(.defaultAction)
                    }
                    .padding(14)
                    Divider()
                    ScrollView {
                        Text(viewing.content)
                            .font(.caption)
                            .monospaced()
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                }
                .frame(width: 620, height: 480)
            }
        }
        .confirmationDialog(
            "Unlink “\(unlink?.name ?? "")” from \(unlink?.tool ?? "")? The central copy is kept.",
            isPresented: Binding(get: { unlink != nil }, set: { if !$0 { unlink = nil } })
        ) {
            Button("Unlink", role: .destructive) {
                if let skill = unlink {
                    Task {
                        actionError = await state.mutateAgents {
                            try AgentsService.symlinkRemove(path: skill.path)
                        }
                    }
                }
            }
        }
    }

    private func skillRow(_ group: Group) -> some View {
        let shared =
            group.byTool["central"] != nil
            && ToolID.allCases.allSatisfy { group.byTool[$0.rawValue]?.broken == false }

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).font(.callout.weight(.semibold)).monospaced()
                if let desc = group.description {
                    Text(desc).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusChip(group.byTool["central"], clickable: false, group: group, tool: nil)
                .frame(width: 70)
            ForEach(ToolID.allCases) { tool in
                statusChip(
                    group.byTool[tool.rawValue], clickable: true, group: group, tool: tool
                )
                .frame(width: 70)
            }

            HStack(spacing: 6) {
                Button {
                    if let source = group.byTool.values.first(where: { !$0.broken }) {
                        viewing = (
                            group.name, (try? AgentsService.skillRead(path: source.path)) ?? ""
                        )
                    }
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("View SKILL.md")

                Button(shared ? "Shared" : "Share to all") {
                    shareToAll(group)
                }
                .controlSize(.small)
                .disabled(shared)
                .frame(width: 92)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func statusChip(_ skill: Skill?, clickable: Bool, group: Group, tool: ToolID?)
        -> some View
    {
        let (label, tint): (String, Color) =
            if let skill {
                skill.broken
                    ? ("broken", Theme.danger)
                    : skill.isSymlink ? ("linked", Theme.accentFg) : ("folder", .secondary)
            } else {
                ("—", Color.secondary.opacity(0.5))
            }

        Button {
            guard clickable, let tool else { return }
            if let skill {
                if skill.isSymlink { unlink = skill }
            } else if group.byTool["central"] != nil {
                Task {
                    actionError = await state.mutateAgents {
                        try AgentsService.skillLink(tool: tool.rawValue, name: group.name)
                    }
                }
            } else {
                actionError = "Not shared yet — use “Share to all” to create a central copy first."
            }
        } label: {
            Badge(text: label, tint: tint)
        }
        .buttonStyle(.plain)
        .help(
            skill == nil
                ? "Click to link from central"
                : skill!.isSymlink ? "Symlinked — click to unlink" : "Real folder here")
    }

    private func shareToAll(_ group: Group) {
        Task {
            actionError = await state.mutateAgents {
                if group.byTool["central"] == nil {
                    let source = ["claude", "codex", "opencode"]
                        .compactMap { group.byTool[$0] }
                        .first { !$0.isSymlink && !$0.broken }
                    guard let source else {
                        throw AgentsService.AgentsError.message(
                            "No real skill folder found to move.")
                    }
                    try AgentsService.skillShare(name: group.name, sourcePath: source.path)
                }
                for tool in ToolID.allCases where group.byTool[tool.rawValue] == nil {
                    try AgentsService.skillLink(tool: tool.rawValue, name: group.name)
                }
            }
        }
    }
}

// MARK: - Symlinks

private struct SymlinksSection: View {
    @Environment(AppState.self) private var state
    @Binding var actionError: String?

    @State private var query = ""
    @State private var brokenOnly = false
    @State private var repairing: SymlinkEntry?
    @State private var repairTarget = ""
    @State private var removing: SymlinkEntry?

    private var links: [SymlinkEntry] {
        let all = state.inventory?.symlinks ?? []
        let q = query.lowercased()
        return all.filter { link in
            if brokenOnly && !link.broken { return false }
            if q.isEmpty { return true }
            return link.path.lowercased().contains(q) || link.resolved.lowercased().contains(q)
                || link.tool.contains(q) || link.category.contains(q)
        }
    }

    var body: some View {
        let brokenCount = state.inventory?.symlinks.filter(\.broken).count ?? 0

        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Filter links…", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                .frame(maxWidth: 260)

                if brokenCount > 0 {
                    Toggle(isOn: $brokenOnly) {
                        Label("\(brokenCount) broken", systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.medium))
                    }
                    .toggleStyle(.button)
                    .tint(Theme.danger)
                }
                Spacer()
                Text("\(links.count) of \(state.inventory?.symlinks.count ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if links.isEmpty {
                EmptyStateView(
                    icon: "link", title: brokenOnly ? "No broken links — nice." : "No symlinks found",
                    hint: brokenOnly ? nil : "Symlinks across your agents' skill folders show up here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(links) { link in
                            linkRow(link)
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
        .alert(
            "Repoint symlink", isPresented: Binding(get: { repairing != nil }, set: { if !$0 { repairing = nil } })
        ) {
            TextField("Target path", text: $repairTarget)
            Button("Save") {
                if let link = repairing {
                    Task {
                        actionError = await state.mutateAgents {
                            try AgentsService.symlinkRepair(path: link.path, target: repairTarget)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Paths.tilde(repairing?.path ?? ""))
        }
        .confirmationDialog(
            "Remove this symlink?\n\(Paths.tilde(removing?.path ?? ""))",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
        ) {
            Button("Remove", role: .destructive) {
                if let link = removing {
                    Task {
                        actionError = await state.mutateAgents {
                            try AgentsService.symlinkRemove(path: link.path)
                        }
                    }
                }
            }
        }
    }

    private func linkRow(_ link: SymlinkEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Paths.tilde(link.path))
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(link.broken ? Theme.danger : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("→ \(Paths.tilde(link.resolved))")
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)

            Badge(text: link.tool)
            Text(link.category).font(.caption2).foregroundStyle(.tertiary)
            Badge(
                text: link.broken ? "broken" : "ok",
                tint: link.broken ? Theme.danger : Theme.success)

            HStack(spacing: 2) {
                Button {
                    repairTarget = link.resolved
                    repairing = link
                } label: {
                    Image(systemName: "wrench.adjustable")
                }
                .buttonStyle(.borderless)
                .help("Repair (repoint)")
                Button {
                    removing = link
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.danger)
                .help("Remove")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Context files

private struct ContextSection: View {
    @Environment(AppState.self) private var state
    @Binding var actionError: String?

    @State private var editing: ContextFile?

    var body: some View {
        let files = state.inventory?.contextFiles ?? []
        let globals = files.filter { $0.scope == "global" }
        let projects = files.filter { $0.scope != "global" }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Instruction files your agents read on every run. Edits are backed up automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                group("Global", globals)
                if !projects.isEmpty {
                    group("Projects", projects)
                }
            }
            .padding(14)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editing) { file in
            ContextEditorSheet(file: file, actionError: $actionError) { editing = nil }
        }
    }

    private func group(_ title: String, _ files: [ContextFile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                SectionLabel(text: title)
                Text("\(files.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            VStack(spacing: 1) {
                ForEach(files) { file in
                    Button {
                        editing = file
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: file.scope == "global" ? "doc.text" : "folder")
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    .quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Text(file.kind).font(.callout.weight(.medium))
                                    if file.scope != "global" {
                                        Text("· \(file.scope)")
                                            .font(.callout)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Text(Paths.tilde(file.path))
                                    .font(.caption2)
                                    .monospaced()
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Badge(text: file.tool)
                            Text(
                                file.exists
                                    ? "\(Fmt.bytes(file.bytes)) · \(Fmt.ago(file.modified))"
                                    : "not created"
                            )
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            Image(systemName: "square.and.pencil")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }
}

private struct ContextEditorSheet: View {
    @Environment(AppState.self) private var state
    let file: ContextFile
    @Binding var actionError: String?
    let dismiss: () -> Void

    @State private var content = ""
    @State private var original = ""
    @State private var status: String?
    @State private var confirmDiscard = false

    private var dirty: Bool { content != original }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(file.kind).font(.headline)
                        Badge(text: file.tool)
                        if dirty {
                            Circle().fill(Theme.warning).frame(width: 7, height: 7)
                                .help("Unsaved changes")
                        }
                    }
                    Text(Paths.tilde(file.path))
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Close") {
                    if dirty { confirmDiscard = true } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!dirty)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            Divider()

            TextEditor(text: $content)
                .font(.callout.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)

            Divider()
            HStack {
                Text("\(content.count) chars")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer()
                if let status {
                    Text(status).font(.caption).foregroundStyle(Theme.success)
                } else if dirty {
                    Text("Unsaved changes").font(.caption).foregroundStyle(Theme.warning)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .frame(width: 680, height: 520)
        .onAppear {
            content = (try? AgentsService.contextRead(path: file.path)) ?? ""
            original = content
        }
        .confirmationDialog("You have unsaved changes. Discard them?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private func save() {
        let text = content
        Task {
            do {
                let backup = try await Task.detached {
                    try AgentsService.contextWrite(path: file.path, content: text)
                }.value
                original = text
                status = backup != nil ? "Saved · previous version backed up" : "Saved"
                await state.refreshAgents()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}
