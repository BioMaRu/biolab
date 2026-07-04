import Foundation
import TOMLKit

/// Cross-agent config manager: discover and control MCP servers, skills,
/// symlinks and context files (CLAUDE.md / AGENTS.md) across Claude Code,
/// Codex and OpenCode. Every mutation backs the target file up first
/// (~/.biolab/backups).
enum AgentsService {
    enum AgentsError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let m) = self { return m }
            return nil
        }
    }

    // MARK: JSON / TOML helpers

    private static func readJSON(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func writeJSON(_ url: URL, _ obj: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try (String(data: data, encoding: .utf8)! + "\n").write(
            to: url, atomically: true, encoding: .utf8)
    }

    private static func readTOML(_ url: URL) throws -> TOMLTable {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        do {
            return try TOMLTable(string: text)
        } catch {
            throw AgentsError.message("Failed to parse \(Paths.tilde(url.path)): \(error.localizedDescription)")
        }
    }

    private static func writeTOML(_ url: URL, _ table: TOMLTable) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try table.convert().write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: MCP — parsing each tool's format into the normalized McpServer

    private static func str(_ v: [String: Any], _ key: String) -> String? {
        v[key] as? String
    }

    private static func args(_ v: [String: Any]) -> [String] {
        (v["args"] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func env(_ v: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, value) in v["env"] as? [String: Any] ?? [:] {
            if let s = value as? String { out[k] = s }
        }
        return out
    }

    private static func scanClaudeMCP() -> [McpServer] {
        let json = readJSON(Paths.claudeJSON)
        let source = Paths.claudeJSON.path
        var out: [McpServer] = []
        for (name, def) in json["mcpServers"] as? [String: Any] ?? [:] {
            guard let def = def as? [String: Any] else { continue }
            let url = str(def, "url")
            let declared = str(def, "type") ?? ""
            let transport =
                (declared == "http" || declared == "sse" || (url != nil && declared.isEmpty))
                ? "http" : "stdio"
            out.append(
                McpServer(
                    name: name, tool: "claude", transport: transport,
                    command: str(def, "command"), args: args(def), env: env(def),
                    url: url, enabled: true, source: source))
        }
        return out
    }

    private static func scanCodexMCP() -> [McpServer] {
        guard let doc = try? readTOML(Paths.codexTOML),
            let servers = doc["mcp_servers"]?.table
        else { return [] }
        let source = Paths.codexTOML.path
        var out: [McpServer] = []
        for (name, item) in servers {
            guard let t = item.table else { continue }
            let url = t["url"]?.string
            var envMap: [String: String] = [:]
            if let envTable = t["env"]?.table {
                for (k, v) in envTable {
                    if let s = v.string { envMap[k] = s }
                }
            }
            let argsList: [String] = t["args"]?.array.map { arr in
                arr.compactMap { ($0 as? TOMLValue)?.string ?? $0.tomlValue.string }
            } ?? []
            out.append(
                McpServer(
                    name: name, tool: "codex",
                    transport: url != nil ? "http" : "stdio",
                    command: t["command"]?.string, args: argsList, env: envMap,
                    url: url, enabled: true, source: source))
        }
        return out
    }

    private static func scanOpenCodeMCP() -> [McpServer] {
        let json = readJSON(Paths.opencodeJSON)
        let source = Paths.opencodeJSON.path
        var out: [McpServer] = []
        for (name, def) in json["mcp"] as? [String: Any] ?? [:] {
            guard let def = def as? [String: Any] else { continue }
            let kind = str(def, "type") ?? ""
            let isRemote = kind == "remote" || def["url"] != nil
            // OpenCode "local" packs the command + args into one array.
            let cmdArray = (def["command"] as? [Any])?.compactMap { $0 as? String } ?? []
            out.append(
                McpServer(
                    name: name, tool: "opencode",
                    transport: isRemote ? "http" : "stdio",
                    command: cmdArray.first,
                    args: Array(cmdArray.dropFirst()),
                    env: env(def),
                    url: str(def, "url"),
                    enabled: def["enabled"] as? Bool ?? true,
                    source: source))
        }
        return out
    }

    // MARK: Disabled stash (Claude/Codex have no native enabled flag)

    private static func readStash() -> [McpServer] {
        guard let data = try? Data(contentsOf: Paths.disabledStash),
            let list = try? JSONDecoder().decode([McpServer].self, from: data)
        else { return [] }
        return list
    }

    private static func writeStash(_ list: [McpServer]) throws {
        try FileManager.default.createDirectory(
            at: Paths.biolabDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (try encoder.encode(list)).write(to: Paths.disabledStash)
    }

    // MARK: MCP — serializing back to each tool's format

    private static func claudeValue(_ s: McpServer) -> [String: Any] {
        var m: [String: Any] = ["type": s.transport]
        if s.transport == "http" {
            if let url = s.url { m["url"] = url }
        } else {
            if let cmd = s.command { m["command"] = cmd }
            m["args"] = s.args
            m["env"] = s.env
        }
        return m
    }

    private static func opencodeValue(_ s: McpServer) -> [String: Any] {
        var m: [String: Any] = [:]
        if s.transport == "http" {
            m["type"] = "remote"
            if let url = s.url { m["url"] = url }
        } else {
            m["type"] = "local"
            var cmd: [String] = []
            if let c = s.command { cmd.append(c) }
            cmd.append(contentsOf: s.args)
            m["command"] = cmd
        }
        m["enabled"] = s.enabled
        return m
    }

    private static func codexTable(_ s: McpServer) -> TOMLTable {
        let t = TOMLTable()
        if s.transport == "http" {
            if let url = s.url { t["url"] = url }
        } else {
            if let cmd = s.command { t["command"] = cmd }
            t["args"] = TOMLArray(s.args)
            if !s.env.isEmpty {
                let envTable = TOMLTable()
                for (k, v) in s.env { envTable[k] = v }
                t["env"] = envTable
            }
        }
        return t
    }

    /// Insert or replace a server in its destination tool's config.
    static func mcpUpsert(_ server: McpServer) throws {
        guard let tool = ToolID(rawValue: server.tool) else {
            throw AgentsError.message("Unknown tool: \(server.tool)")
        }
        let path = Paths.toolConfig(tool)
        backupFile(path)
        switch tool {
        case .claude:
            var json = readJSON(path)
            var servers = json["mcpServers"] as? [String: Any] ?? [:]
            servers[server.name] = claudeValue(server)
            json["mcpServers"] = servers
            try writeJSON(path, json)
        case .opencode:
            var json = readJSON(path)
            if json.isEmpty { json["$schema"] = "https://opencode.ai/config.json" }
            var servers = json["mcp"] as? [String: Any] ?? [:]
            servers[server.name] = opencodeValue(server)
            json["mcp"] = servers
            try writeJSON(path, json)
        case .codex:
            let doc = try readTOML(path)
            let servers = doc["mcp_servers"]?.table ?? {
                let t = TOMLTable()
                doc["mcp_servers"] = t
                return t
            }()
            servers[server.name] = codexTable(server)
            try writeTOML(path, doc)
        }
    }

    /// Remove a server from a tool's config (and the disabled stash).
    static func mcpRemove(tool: String, name: String) throws {
        guard let toolID = ToolID(rawValue: tool) else {
            throw AgentsError.message("Unknown tool: \(tool)")
        }
        let path = Paths.toolConfig(toolID)
        backupFile(path)
        switch toolID {
        case .claude:
            var json = readJSON(path)
            var servers = json["mcpServers"] as? [String: Any] ?? [:]
            servers.removeValue(forKey: name)
            json["mcpServers"] = servers
            try writeJSON(path, json)
        case .opencode:
            var json = readJSON(path)
            var servers = json["mcp"] as? [String: Any] ?? [:]
            servers.removeValue(forKey: name)
            json["mcp"] = servers
            try writeJSON(path, json)
        case .codex:
            let doc = try readTOML(path)
            if let servers = doc["mcp_servers"]?.table {
                servers.remove(at: name)
            }
            try writeTOML(path, doc)
        }

        var stash = readStash()
        let before = stash.count
        stash.removeAll { $0.tool == tool && $0.name == name }
        if stash.count != before { try writeStash(stash) }
    }

    /// Copy a server's definition into each target tool (format-translated).
    static func mcpSync(_ server: McpServer, targets: [String]) throws {
        for tool in targets {
            var copy = server
            copy.tool = tool
            copy.source = ""
            try mcpUpsert(copy)
        }
    }

    /// Enable/disable. OpenCode flips its native flag; Claude and Codex have no
    /// such flag, so the definition is stashed and removed from the live config
    /// (and restored on re-enable).
    static func mcpSetEnabled(_ server: McpServer, enabled: Bool) throws {
        if server.tool == "opencode" {
            let path = Paths.opencodeJSON
            backupFile(path)
            var json = readJSON(path)
            var servers = json["mcp"] as? [String: Any] ?? [:]
            if var def = servers[server.name] as? [String: Any] {
                def["enabled"] = enabled
                servers[server.name] = def
            }
            json["mcp"] = servers
            try writeJSON(path, json)
            return
        }

        var stash = readStash()
        if enabled {
            if let index = stash.firstIndex(where: { $0.tool == server.tool && $0.name == server.name }) {
                var restored = stash.remove(at: index)
                restored.enabled = true
                try mcpUpsert(restored)
                try writeStash(stash)
            }
        } else {
            var stashed = server
            stashed.enabled = false
            stash.removeAll { $0.tool == stashed.tool && $0.name == stashed.name }
            stash.append(stashed)
            try writeStash(stash)
            try mcpRemove(tool: server.tool, name: server.name)
        }
    }

    // MARK: Skills & symlinks

    private static func skillDescription(_ dir: URL) -> String? {
        guard let text = try? String(contentsOf: dir.appending(path: "SKILL.md"), encoding: .utf8)
        else { return nil }
        var inFrontmatter = false
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if inFrontmatter { break }
                inFrontmatter = true
                continue
            }
            if inFrontmatter, trimmed.hasPrefix("description:") {
                let value = trimmed.dropFirst("description:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func isSymlink(_ path: String) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    private static func scanSkills(in dir: URL, tool: String, into skills: inout [Skill]) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where !name.hasPrefix(".") {
            let url = dir.appending(path: name)
            let link = isSymlink(url.path)
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            // Only surface directories (real or via symlink), not stray files.
            if !link && !(exists && isDir.boolValue) { continue }

            let target = link ? (try? fm.destinationOfSymbolicLink(atPath: url.path)) : nil
            let broken = link && !exists
            skills.append(
                Skill(
                    name: name, tool: tool, path: url.path,
                    isSymlink: link, target: target, broken: broken,
                    description: broken ? nil : skillDescription(url)))
        }
    }

    private static func collectSymlinks(
        in dir: URL, category: String, tool: String, into out: inout [SymlinkEntry]
    ) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names {
            let url = dir.appending(path: name)
            guard isSymlink(url.path) else { continue }
            let target = (try? fm.destinationOfSymbolicLink(atPath: url.path)) ?? ""
            let broken = !fm.fileExists(atPath: url.path) // follows the link
            let resolved: String
            if broken {
                // Best-effort resolution for display when the link is dangling.
                resolved = target.hasPrefix("/") ? target : dir.appending(path: target).path
            } else {
                resolved = url.resolvingSymlinksInPath().path
            }
            out.append(
                SymlinkEntry(
                    path: url.path, target: target, resolved: resolved,
                    broken: broken, category: category, tool: tool))
        }
    }

    // MARK: Context files

    private static func contextFile(scope: String, tool: String, kind: String, url: URL)
        -> ContextFile
    {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return ContextFile(
            scope: scope, tool: tool, kind: kind, path: url.path,
            exists: attrs != nil,
            bytes: (attrs?[.size] as? NSNumber)?.uint64Value ?? 0,
            modified: attrs?[.modificationDate] as? Date)
    }

    private static func scanContextFiles() -> [ContextFile] {
        var list: [ContextFile] = [
            // Global instruction files, always shown (creatable when absent).
            contextFile(
                scope: "global", tool: "claude", kind: "CLAUDE.md",
                url: Paths.home.appending(path: ".claude/CLAUDE.md")),
            contextFile(
                scope: "global", tool: "codex", kind: "AGENTS.md",
                url: Paths.home.appending(path: ".codex/AGENTS.md")),
            contextFile(
                scope: "global", tool: "opencode", kind: "AGENTS.md",
                url: Paths.home.appending(path: ".config/opencode/AGENTS.md")),
        ]

        // Per-project files discovered from Claude's known project list.
        let claude = readJSON(Paths.claudeJSON)
        let fm = FileManager.default
        for dir in (claude["projects"] as? [String: Any] ?? [:]).keys.sorted() {
            let base = URL(fileURLWithPath: dir)
            let scope = base.lastPathComponent
            for (kind, tool) in [("CLAUDE.md", "claude"), ("AGENTS.md", "shared")] {
                let url = base.appending(path: kind)
                if fm.fileExists(atPath: url.path) {
                    list.append(contextFile(scope: scope, tool: tool, kind: kind, url: url))
                }
            }
        }
        return list
    }

    // MARK: Inventory

    static func scan() -> AgentInventory {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        func installed(_ path: String) -> Bool {
            fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }

        var inventory = AgentInventory()
        inventory.tools = [
            AgentTool(
                id: .claude, installed: installed(Paths.home.appending(path: ".claude").path),
                configPath: Paths.claudeJSON.path),
            AgentTool(
                id: .codex, installed: installed(Paths.home.appending(path: ".codex").path),
                configPath: Paths.codexTOML.path),
            AgentTool(
                id: .opencode,
                installed: installed(Paths.home.appending(path: ".config/opencode").path),
                configPath: Paths.opencodeJSON.path),
        ]

        inventory.mcpServers = (scanClaudeMCP() + scanCodexMCP() + scanOpenCodeMCP())
            .sorted { ($0.name, $0.tool) < ($1.name, $1.tool) }
        inventory.disabled = readStash()

        var skills: [Skill] = []
        scanSkills(in: Paths.centralSkills, tool: "central", into: &skills)
        scanSkills(in: Paths.claudeSkills, tool: "claude", into: &skills)
        scanSkills(in: Paths.codexSkills, tool: "codex", into: &skills)
        scanSkills(in: Paths.opencodeSkills, tool: "opencode", into: &skills)
        inventory.skills = skills.sorted { ($0.name, $0.tool) < ($1.name, $1.tool) }

        var symlinks: [SymlinkEntry] = []
        collectSymlinks(in: Paths.claudeSkills, category: "skill", tool: "claude", into: &symlinks)
        collectSymlinks(in: Paths.claudeAgents, category: "agent", tool: "claude", into: &symlinks)
        collectSymlinks(in: Paths.codexSkills, category: "skill", tool: "codex", into: &symlinks)
        collectSymlinks(
            in: Paths.opencodeSkills, category: "skill", tool: "opencode", into: &symlinks)
        collectSymlinks(in: Paths.centralSkills, category: "skill", tool: "central", into: &symlinks)
        inventory.symlinks = symlinks.sorted { $0.path < $1.path }

        inventory.contextFiles = scanContextFiles()
        inventory.centralSkillsDir = Paths.centralSkills.path
        return inventory
    }

    // MARK: Skills — share & link

    static func skillRead(path: String) throws -> String {
        let md = URL(fileURLWithPath: path).appending(path: "SKILL.md")
        do {
            return try String(contentsOf: md, encoding: .utf8)
        } catch {
            throw AgentsError.message("Failed to read \(Paths.tilde(md.path))")
        }
    }

    /// Move a skill folder into the central store and replace the original
    /// location with a symlink, so it can be shared across agents.
    static func skillShare(name: String, sourcePath: String) throws {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: sourcePath)
        try fm.createDirectory(at: Paths.centralSkills, withIntermediateDirectories: true)
        let dest = Paths.centralSkills.appending(path: name)

        if source.path == dest.path { return } // already central

        let sourceIsLink = isSymlink(source.path)
        if !fm.fileExists(atPath: dest.path) {
            let origin = sourceIsLink ? source.resolvingSymlinksInPath() : source
            try fm.copyItem(at: origin, to: dest)
        }
        if fm.fileExists(atPath: source.path) || sourceIsLink {
            try fm.removeItem(at: source)
        }
        try fm.createSymbolicLink(at: source, withDestinationURL: dest)
    }

    /// Symlink a central skill into a tool's skills directory.
    static func skillLink(tool: String, name: String) throws {
        let fm = FileManager.default
        let central = Paths.centralSkills.appending(path: name)
        guard fm.fileExists(atPath: central.path) else {
            throw AgentsError.message("No central skill named \(name)")
        }
        guard let dir = Paths.skillsDir(tool) else {
            throw AgentsError.message("Unknown tool: \(tool)")
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let link = dir.appending(path: name)
        if isSymlink(link.path) || fm.fileExists(atPath: link.path) {
            throw AgentsError.message("\(Paths.tilde(link.path)) already exists")
        }
        try fm.createSymbolicLink(at: link, withDestinationURL: central)
    }

    // MARK: Symlinks

    /// Remove a symlink. Refuses non-symlinks for safety.
    static func symlinkRemove(path: String) throws {
        guard isSymlink(path) else {
            throw AgentsError.message("\(Paths.tilde(path)) is not a symlink")
        }
        try FileManager.default.removeItem(atPath: path)
    }

    /// Repoint a broken/existing symlink at a new target.
    static func symlinkRepair(path: String, target: String) throws {
        let fm = FileManager.default
        if isSymlink(path) { try fm.removeItem(atPath: path) }
        try fm.createSymbolicLink(atPath: path, withDestinationPath: target)
    }

    // MARK: Context files

    static func contextRead(path: String) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else { return "" }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    /// Write an instruction file, backing up any existing version first.
    @discardableResult
    static func contextWrite(path: String, content: String) throws -> String? {
        let url = URL(fileURLWithPath: path)
        let backup = backupFile(url)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return backup
    }
}
