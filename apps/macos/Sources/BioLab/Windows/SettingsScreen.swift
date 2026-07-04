import ServiceManagement
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppState.self) private var state
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage("menubar.showUsage") private var showUsageInMenuBar = true
    @AppStorage("updates.autoCheck") private var autoCheckUpdates = true

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(Theme.danger)
                }
                Toggle("Show session usage in menu bar", isOn: $showUsageInMenuBar)
                Text("Displays your current Claude session limit (e.g. 62%) next to the menu bar icon, tinted as it nears the cap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Usage rescans every 2 minutes; plan limits refresh every 5 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        if state.updateInstalling {
                            ProgressView().controlSize(.small)
                            Text("Updating…").foregroundStyle(.secondary)
                        } else if state.updateChecking {
                            ProgressView().controlSize(.small)
                            Text("Checking…").foregroundStyle(.secondary)
                        } else if state.updateAvailable, let release = state.latestRelease {
                            Text("v\(release.version) available")
                                .foregroundStyle(Theme.accentFg)
                            Button("Update & Relaunch") {
                                Task { await state.installUpdate() }
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            Button("Notes") {
                                NSWorkspace.shared.open(release.url)
                            }
                            .controlSize(.small)
                        } else if let error = state.updateError {
                            Text(error).foregroundStyle(Theme.danger).lineLimit(1)
                        } else if state.updateCheckedAt != nil {
                            Text("Up to date").foregroundStyle(.secondary)
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                        Button("Check Now") {
                            Task { await state.checkForUpdates(manual: true) }
                        }
                        .controlSize(.small)
                        .disabled(state.updateChecking || state.updateInstalling)
                    }
                }
                if let error = state.updateInstallError {
                    Text(error).font(.caption).foregroundStyle(Theme.danger)
                } else if let at = state.updateCheckedAt {
                    Text("Last checked \(Fmt.ago(at)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                LabeledContent("Config backups") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Paths.backupsDir])
                    }
                    .controlSize(.small)
                }
                Text("Every config mutation (MCP edits, context saves) writes a timestamped backup to ~/.biolab/backups first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("Data sources") {
                    Text("~/.claude · ~/.codex · ~/.config/opencode")
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                Text(
                    "BioLab reads your agent CLIs' local data directly — nothing leaves this Mac except the Claude limits request, which goes only to Anthropic using your own token."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
