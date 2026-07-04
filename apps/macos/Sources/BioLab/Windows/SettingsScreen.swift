import ServiceManagement
import SwiftUI

struct SettingsScreen: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

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
                LabeledContent("Menu bar refresh", value: "usage every 2 min · limits every 5 min")
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
