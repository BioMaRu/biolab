import Foundation

// MARK: - Agents

enum ToolID: String, CaseIterable, Identifiable, Codable {
    case claude, codex, opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        }
    }

    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        }
    }
}

struct AgentTool: Identifiable, Hashable {
    let id: ToolID
    let installed: Bool
    let configPath: String
}

struct McpServer: Identifiable, Hashable, Codable {
    var name: String
    var tool: String
    var transport: String // "stdio" | "http"
    var command: String?
    var args: [String]
    var env: [String: String]
    var url: String?
    var enabled: Bool
    var source: String

    var id: String { "\(tool):\(name)" }

    init(
        name: String, tool: String, transport: String, command: String? = nil,
        args: [String] = [], env: [String: String] = [:], url: String? = nil,
        enabled: Bool = true, source: String = ""
    ) {
        self.name = name
        self.tool = tool
        self.transport = transport
        self.command = command
        self.args = args
        self.env = env
        self.url = url
        self.enabled = enabled
        self.source = source
    }
}

struct Skill: Identifiable, Hashable {
    let name: String
    let tool: String
    let path: String
    let isSymlink: Bool
    let target: String?
    let broken: Bool
    let description: String?

    var id: String { "\(tool):\(name)" }
}

struct SymlinkEntry: Identifiable, Hashable {
    let path: String
    let target: String
    let resolved: String
    let broken: Bool
    let category: String // "skill" | "agent"
    let tool: String

    var id: String { path }
}

struct ContextFile: Identifiable, Hashable {
    let scope: String // "global" or a project name
    let tool: String // "claude" | "codex" | "opencode" | "shared"
    let kind: String // "CLAUDE.md" | "AGENTS.md"
    let path: String
    let exists: Bool
    let bytes: UInt64
    let modified: Date?

    var id: String { path }
}

struct AgentInventory {
    var tools: [AgentTool] = []
    var mcpServers: [McpServer] = []
    var disabled: [McpServer] = []
    var skills: [Skill] = []
    var symlinks: [SymlinkEntry] = []
    var contextFiles: [ContextFile] = []
    var centralSkillsDir: String = ""
}

/// Resolved state of one MCP server name within one tool.
struct McpCell {
    let configured: Bool
    let on: Bool
    let server: McpServer?
}

// MARK: - Ports

struct PortInfo: Identifiable, Hashable {
    let pid: Int32
    let processName: String
    let user: String
    let protocolName: String
    let address: String
    let port: Int
    let command: String

    var id: String { "\(pid):\(port):\(address)" }
}

// MARK: - Usage

/// One normalized usage event (a Claude assistant message, a Codex turn, or an
/// OpenCode session) — the unit both caching and window aggregation work on.
struct UsageEvent {
    let timestamp: Date
    let model: String
    let input: Int64
    let output: Int64
    let cacheRead: Int64
    let cacheCreation: Int64
    let cost: Double
    let project: String?
    let session: String?
    var webSearch: Int64 = 0
    var webFetch: Int64 = 0

    var total: Int64 { input + output + cacheRead + cacheCreation }
}

struct WindowStat: Identifiable {
    let key: String // session | today | week | all
    let label: String
    var input: Int64 = 0
    var output: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheCreation: Int64 = 0
    var cost: Double = 0
    var messages: Int = 0
    var resetsAt: Date?

    var id: String { key }
    var total: Int64 { input + output + cacheRead + cacheCreation }
}

struct ModelStat: Identifiable {
    let model: String
    var total: Int64
    var cost: Double
    var messages: Int

    var id: String { model }
}

struct ProjectStat: Identifiable {
    let path: String
    var total: Int64
    var messages: Int

    var id: String { path }
}

struct ProviderUsage: Identifiable {
    let id: ToolID
    let tracked: Bool
    var note: String?
    var windows: [WindowStat] = []
    var models: [ModelStat] = []
    var projects: [ProjectStat] = []
    var webSearch: Int64 = 0
    var webFetch: Int64 = 0
    var sessions: Int = 0
    var lastActive: Date?

    var name: String { id.displayName }

    func window(_ key: String) -> WindowStat? {
        windows.first { $0.key == key }
    }
}

struct UsageReport {
    var generatedAt: Date = .init()
    var providers: [ProviderUsage] = []

    func provider(_ id: ToolID) -> ProviderUsage? {
        providers.first { $0.id == id }
    }
}

// MARK: - Claude plan limits (live)

struct LimitBar: Identifiable {
    let kind: String // session | weekly_all | weekly_scoped | …
    let label: String
    let percent: Double
    let severity: String // normal | warning | critical
    let resetsAt: Date?
    let isActive: Bool

    var id: String { kind + label }
}

struct ExtraUsage {
    let enabled: Bool
    let used: Double
    let limit: Double
    let currency: String
    let percent: Double
}

struct ClaudeLimits {
    let plan: String?
    let bars: [LimitBar]
    let extra: ExtraUsage?
    let fetchedAt: Date
}

// MARK: - Constants

enum Const {
    /// Common developer ports offered as quick-kill chips.
    static let commonPorts: [Int] = [
        3000, 3001, 4200, 5000, 5173, 5432, 6379, 8000, 8080, 8888, 9000, 27017,
    ]

    static let sessionWindow: TimeInterval = 5 * 3600
    static let dayWindow: TimeInterval = 24 * 3600
    static let weekWindow: TimeInterval = 7 * 24 * 3600
}
