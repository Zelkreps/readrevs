import SwiftUI

@main
struct ReadRevsApp: App {
    @StateObject private var store = LibraryStore.makeDefault()

    var body: some Scene {
        WindowGroup("ReadRevs") {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 1_180, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            AppSettingsView()
                .environmentObject(store)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["READREVS_COLOR_SCHEME"]?.lowercased() {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
