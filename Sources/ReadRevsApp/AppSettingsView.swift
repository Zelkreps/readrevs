import SwiftUI

struct AppSettingsView: View {
    var body: some View {
        TabView {
            AppleAdsSettingsView()
                .tabItem {
                    Label("Apple Ads", systemImage: "chart.bar.xaxis")
                }

            CodexResearchSettingsView()
                .tabItem {
                    Label("Codex", systemImage: "sparkles")
                }
        }
        .frame(width: 680, height: 690)
    }
}
