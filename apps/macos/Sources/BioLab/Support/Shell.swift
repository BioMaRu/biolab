import Foundation

enum ShellError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(Int32, String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let cmd): "Failed to launch \(cmd)"
        case .nonZeroExit(let code, let cmd): "\(cmd) exited with status \(code)"
        }
    }
}

enum Shell {
    /// Run a command and capture stdout. `allowFailure` tolerates non-zero exit
    /// (lsof exits 1 when nothing matches — that's not an error for us).
    @discardableResult
    static func run(
        _ executable: String, _ arguments: [String], allowFailure: Bool = false
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(executable)
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 && !allowFailure {
            throw ShellError.nonZeroExit(process.terminationStatus, executable)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum Paths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var claudeJSON: URL { home.appending(path: ".claude.json") }
    static var claudeSkills: URL { home.appending(path: ".claude/skills") }
    static var claudeAgents: URL { home.appending(path: ".claude/agents") }
    static var claudeProjects: URL { home.appending(path: ".claude/projects") }
    static var codexTOML: URL { home.appending(path: ".codex/config.toml") }
    static var codexSkills: URL { home.appending(path: ".codex/skills") }
    static var codexLogsDB: URL { home.appending(path: ".codex/logs_2.sqlite") }
    static var opencodeJSON: URL { home.appending(path: ".config/opencode/opencode.json") }
    static var opencodeSkills: URL { home.appending(path: ".config/opencode/skills") }
    static var opencodeDB: URL { home.appending(path: ".local/share/opencode/opencode.db") }
    static var centralSkills: URL { home.appending(path: ".agents/skills") }
    static var biolabDir: URL { home.appending(path: ".biolab") }
    static var backupsDir: URL { biolabDir.appending(path: "backups") }
    static var disabledStash: URL { biolabDir.appending(path: "disabled-mcp.json") }

    static func toolConfig(_ tool: ToolID) -> URL {
        switch tool {
        case .claude: claudeJSON
        case .codex: codexTOML
        case .opencode: opencodeJSON
        }
    }

    static func skillsDir(_ tool: String) -> URL? {
        switch tool {
        case "claude": claudeSkills
        case "codex": codexSkills
        case "opencode": opencodeSkills
        case "central": centralSkills
        default: nil
        }
    }

    /// Shorten an absolute path with ~ for $HOME.
    static func tilde(_ path: String) -> String {
        let h = home.path
        return path.hasPrefix(h) ? "~" + path.dropFirst(h.count) : path
    }
}

/// Copy a file into ~/.biolab/backups with a timestamp prefix before mutating
/// it. No-op when the file doesn't exist yet. Returns the backup path.
@discardableResult
func backupFile(_ url: URL) -> String? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else { return nil }
    let ts = Int(Date().timeIntervalSince1970)
    let dest = Paths.backupsDir.appending(path: "\(ts)-\(url.lastPathComponent)")
    try? fm.createDirectory(at: Paths.backupsDir, withIntermediateDirectories: true)
    try? fm.copyItem(at: url, to: dest)
    return dest.path
}
