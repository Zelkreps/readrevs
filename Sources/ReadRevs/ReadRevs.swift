import AppKit
import SwiftUI

@main
struct ReadRevsApp: App {
    @NSApplicationDelegateAdaptor(ReadRevsAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ReadRevsRootView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1_320, height: 840)
        .windowResizability(.contentMinSize)

        Settings {
            ReadRevsSettingsView()
        }
    }
}

@MainActor
private final class ReadRevsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else {
            return
        }
        NSApplication.shared.applicationIconImage = icon
    }
}
