import Observation
import SwiftUI

/// Central observable state: every screen (menu bar panel and main window)
/// reads from here; services are only ever touched through these refreshers,
/// which run the work off the main actor.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    // MARK: Data

    var ports: [PortInfo] = []
    var portsError: String?
    var portsLoadedOnce = false

    var usage: UsageReport?
    var usageError: String?
    var usageUpdatedAt: Date?

    var limits: ClaudeLimits?
    var limitsError: String?
    var limitsLoading = false

    var inventory: AgentInventory?
    var agentsError: String?
    var agentsLoading = false

    var latestRelease: UpdateService.Release?
    var updateChecking = false
    var updateCheckedAt: Date?
    var updateError: String?
    private var dismissedUpdateVersion: String? =
        UserDefaults.standard.string(forKey: "updates.dismissedVersion")

    // MARK: Settings (persisted)

    var favoritePorts: [Int] {
        get { UserDefaults.standard.array(forKey: "ports.favorites") as? [Int] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "ports.favorites") }
    }

    private var started = false

    /// Kick off initial loads + background refresh loops. Idempotent.
    func bootstrap() {
        guard !started else { return }
        started = true
        Task { await refreshUsage() }
        Task { await refreshLimits() }
        Task { await refreshPorts() }
        Task { await refreshAgents() }

        // Usage stays fresh for the menu bar; limits are polled gently to be
        // kind to Anthropic's endpoint.
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                await refreshUsage()
            }
        }
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await refreshLimits()
            }
        }
        // Update checks: once on launch, then every 12 hours.
        Task { await checkForUpdates() }
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12 * 3600))
                await checkForUpdates()
            }
        }
    }

    // MARK: Updates

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// A newer release exists than the running build (ignored for unpackaged
    /// "dev" builds).
    var updateAvailable: Bool {
        guard let release = latestRelease, currentVersion != "dev" else { return false }
        return UpdateService.isNewer(release.version, than: currentVersion)
    }

    /// Whether to surface the banner — available and not dismissed for this version.
    var showUpdateBanner: Bool {
        updateAvailable && latestRelease?.version != dismissedUpdateVersion
    }

    func checkForUpdates(manual: Bool = false) async {
        let auto = UserDefaults.standard.object(forKey: "updates.autoCheck") as? Bool ?? true
        guard manual || auto else { return }
        guard currentVersion != "dev" else { return }  // unpackaged build — nothing to update
        updateChecking = true
        defer {
            updateChecking = false
            updateCheckedAt = Date()
        }
        do {
            latestRelease = try await UpdateService.latest()
            updateError = nil
        } catch {
            updateError = error.localizedDescription
        }
    }

    /// Hide the banner for the current latest version until a newer one ships.
    func dismissUpdate() {
        dismissedUpdateVersion = latestRelease?.version
        UserDefaults.standard.set(dismissedUpdateVersion, forKey: "updates.dismissedVersion")
    }

    // MARK: Refreshers

    func refreshPorts() async {
        do {
            let list = try await Task.detached(priority: .userInitiated) {
                try PortsService.list()
            }.value
            ports = list
            portsError = nil
        } catch {
            portsError = error.localizedDescription
        }
        portsLoadedOnce = true
    }

    func refreshUsage() async {
        let report = await UsageService.shared.report()
        usage = report
        usageUpdatedAt = Date()
    }

    func refreshLimits() async {
        limitsLoading = true
        defer { limitsLoading = false }
        do {
            limits = try await LimitsService.fetch()
            limitsError = nil
        } catch {
            limitsError = error.localizedDescription
        }
    }

    func refreshAgents() async {
        agentsLoading = inventory == nil
        defer { agentsLoading = false }
        inventory = await Task.detached(priority: .userInitiated) {
            AgentsService.scan()
        }.value
        agentsError = nil
    }

    func refreshAll() async {
        async let a: () = refreshUsage()
        async let b: () = refreshLimits()
        async let c: () = refreshPorts()
        async let d: () = refreshAgents()
        _ = await (a, b, c, d)
    }

    // MARK: Actions

    func killProcess(pid: Int32, force: Bool) async -> String? {
        do {
            try await Task.detached { try PortsService.kill(pid: pid, force: force) }.value
            try? await Task.sleep(for: .milliseconds(300))
            await refreshPorts()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Run an agents-config mutation off-main, then rescan so the UI stays
    /// truthful. Returns an error message on failure.
    func mutateAgents(_ work: @escaping @Sendable () throws -> Void) async -> String? {
        do {
            try await Task.detached(priority: .userInitiated) { try work() }.value
            await refreshAgents()
            return nil
        } catch {
            await refreshAgents()
            return error.localizedDescription
        }
    }

    // MARK: Derived — MCP matrix

    var mcpNames: [String] {
        guard let inv = inventory else { return [] }
        return Set(inv.mcpServers.map(\.name)).union(inv.disabled.map(\.name)).sorted()
    }

    func mcpCell(name: String, tool: ToolID) -> McpCell {
        guard let inv = inventory else { return McpCell(configured: false, on: false, server: nil) }
        if let live = inv.mcpServers.first(where: { $0.name == name && $0.tool == tool.rawValue }) {
            return McpCell(configured: true, on: live.enabled, server: live)
        }
        if let stashed = inv.disabled.first(where: { $0.name == name && $0.tool == tool.rawValue }) {
            return McpCell(configured: true, on: false, server: stashed)
        }
        return McpCell(configured: false, on: false, server: nil)
    }

    /// Any known definition of a name, used to seed a "copy here" edit.
    func mcpAnyDefinition(_ name: String) -> McpServer? {
        inventory?.mcpServers.first { $0.name == name }
            ?? inventory?.disabled.first { $0.name == name }
    }
}
