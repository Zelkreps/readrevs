import SwiftUI

struct ReadRevsRootView: View {
    @State private var library = SavedAppsStore()
    @State private var dashboard = ReviewDashboardModel()
    @State private var isAddingApp = false
    @State private var appPendingRemoval: AppMetadata?

    var body: some View {
        @Bindable var library = library

        NavigationSplitView {
            AppSidebar(
                apps: library.apps,
                selection: $library.selectedAppID,
                onAdd: { isAddingApp = true },
                onRemove: { appPendingRemoval = $0 }
            )
        } detail: {
            if library.selectedApp != nil {
                ReviewDashboardView(model: dashboard)
            } else {
                FirstAppView(onAdd: { isAddingApp = true })
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if library.selectedApp != nil {
                    Button {
                        Task { await refreshSelectedApp() }
                    } label: {
                        Label("Refresh Reviews", systemImage: "arrow.clockwise")
                    }
                    .disabled(dashboard.isRefreshing)
                    .help("Refresh metadata and reviews")
                }

                Button {
                    isAddingApp = true
                } label: {
                    Label("Add App", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Add an App Store app (⌘N)")
            }
        }
        .sheet(isPresented: $isAddingApp) {
            AddAppView(client: AppleReviewClient()) { app in
                library.upsert(app)
            }
        }
        .confirmationDialog(
            "Remove \(appPendingRemoval?.name ?? "this app")?",
            isPresented: Binding(
                get: { appPendingRemoval != nil },
                set: { if !$0 { appPendingRemoval = nil } }
            )
        ) {
            Button("Remove from ReadRevs", role: .destructive) {
                if let appPendingRemoval {
                    library.remove(appID: appPendingRemoval.appID)
                }
                appPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                appPendingRemoval = nil
            }
        } message: {
            Text("Only the local saved entry is removed. Nothing changes in App Store Connect.")
        }
        .task(id: library.selectedAppID) {
            guard let app = library.selectedApp else {
                dashboard.clear()
                return
            }
            await dashboard.load(app)
            if let refreshed = dashboard.metadata {
                library.upsert(refreshed, select: false)
            }
        }
    }

    private func refreshSelectedApp() async {
        await dashboard.refresh()
        if let refreshed = dashboard.metadata {
            library.upsert(refreshed, select: false)
        }
    }
}

private struct FirstAppView: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Your review inbox is empty", systemImage: "text.bubble")
        } description: {
            Text("Add any public App Store app by pasting its URL or numeric ID.")
        } actions: {
            Button("Add Your First App", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}
