import AppKit
import SwiftUI

/// BioLab lives in the menu bar (LSUIElement); the full window opens on demand
/// from the panel and returns the app to accessory mode when closed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Start the refresh loops immediately so the menu-bar label is live
        // before the panel is ever opened.
        AppState.shared.bootstrap()
    }
}

@main
struct BioLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environment(state)
        } label: {
            TrayLabel(state: state)
        }
        .menuBarExtraStyle(.window)

        Window("BioLab", id: "main") {
            MainWindow()
                .environment(state)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .defaultSize(width: 980, height: 660)

        Settings {
            SettingsScreen()
                .environment(state)
                .frame(minWidth: 480)
        }
    }

    /// Template menu-bar glyph — falls back to an SF Symbol if the bundled
    /// asset can't be loaded for any reason.
    fileprivate static let trayIcon: NSImage = {
        if let url = Bundle.module.url(forResource: "tray", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        let fallback = NSImage(
            systemSymbolName: "flask", accessibilityDescription: "BioLab")!
        fallback.isTemplate = true
        return fallback
    }()
}

/// Menu-bar label: the tray glyph plus, optionally, the live Claude session
/// usage — the number this app exists to keep in view. Tinted only when the
/// limit turns warning/critical, so the menu bar stays quiet by default.
private struct TrayLabel: View {
    let state: AppState
    @AppStorage("menubar.showUsage") private var showUsage = true

    var body: some View {
        if showUsage, let bar = sessionBar {
            HStack(spacing: 3) {
                Image(nsImage: BioLabApp.trayIcon)
                Text("\(Int(bar.percent.rounded()))%")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(
                        bar.severity == "normal"
                            ? AnyShapeStyle(.primary)
                            : AnyShapeStyle(Theme.severity(bar.severity)))
            }
            .accessibilityLabel(
                "BioLab — Claude session \(Int(bar.percent.rounded())) percent used")
        } else {
            Image(nsImage: BioLabApp.trayIcon)
                .accessibilityLabel("BioLab")
        }
    }

    private var sessionBar: LimitBar? {
        guard let bars = state.limits?.bars else { return nil }
        return bars.first { $0.kind == "session" } ?? bars.first
    }
}
