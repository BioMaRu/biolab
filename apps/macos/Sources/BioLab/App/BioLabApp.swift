import AppKit
import SwiftUI

/// BioLab lives in the menu bar (LSUIElement); the full window opens on demand
/// from the panel and returns the app to accessory mode when closed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
            Image(nsImage: Self.trayIcon)
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
    }

    /// Template menu-bar glyph — falls back to an SF Symbol if the bundled
    /// asset can't be loaded for any reason.
    private static let trayIcon: NSImage = {
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
