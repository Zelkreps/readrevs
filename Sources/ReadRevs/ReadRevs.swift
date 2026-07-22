import SwiftUI

@main
struct ReadRevsApp: App {
    var body: some Scene {
        WindowGroup {
            ReadRevsRootView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1_320, height: 840)
        .windowResizability(.contentMinSize)
    }
}
