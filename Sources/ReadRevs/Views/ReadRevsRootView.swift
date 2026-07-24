import SwiftUI

struct ReadRevsRootView: View {
    @State private var library = SavedAppsStore()
    @State private var dashboard = ReviewDashboardModel()
    @State private var researchManager = CodexResearchSessionManager()
    @State private var isAddingApp = false
    @State private var isShowingResearchCenter = false
    @State private var appPendingRemoval: AppMetadata?
    @State private var selectedHistoryEntry: CodexResearchHistoryEntry?

    var body: some View {
        @Bindable var library = library
        @Bindable var researchManager = researchManager

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
                    researchManager.refreshHistory()
                    isShowingResearchCenter = true
                } label: {
                    ResearchToolbarLabel(runningCount: researchManager.runningSessionCount)
                }
                .help("Open current and saved review research")
                .popover(isPresented: $isShowingResearchCenter, arrowEdge: .top) {
                    CodexResearchCenterPopover(
                        sessions: researchManager.researchCenterSessions,
                        entries: researchManager.historyEntries,
                        errorMessage: researchManager.historyErrorMessage,
                        onOpenSession: openResearchSession,
                        onOpenHistory: openHistoryEntry
                    )
                }

                Button {
                    isAddingApp = true
                } label: {
                    Label("Add App", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Add an App Store app (⌘N)")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("ReadRevs Settings (⌘,)")
            }
        }
        .environment(researchManager)
        .sheet(
            item: $researchManager.presentedSession,
            onDismiss: researchManager.discardUnsubmittedSessions
        ) { session in
            CodexResearchChatView(
                model: session,
                sessionManager: researchManager
            )
        }
        .sheet(item: $selectedHistoryEntry) { entry in
            CodexResearchHistoryDetailView(entry: entry)
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
        .overlay(alignment: .bottomTrailing) {
            if let notice = researchManager.completionNotice {
                CodexResearchCompletionToast(
                    notice: notice,
                    onOpen: researchManager.openCompletionNotice,
                    onDismiss: researchManager.dismissCompletionNotice
                )
                .padding(20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: researchManager.completionNotice?.id)
    }

    private func refreshSelectedApp() async {
        await dashboard.refresh()
        if let refreshed = dashboard.metadata {
            library.upsert(refreshed, select: false)
        }
    }

    private func openResearchSession(_ session: CodexResearchChatModel) {
        isShowingResearchCenter = false
        researchManager.present(session)
    }

    private func openHistoryEntry(_ entry: CodexResearchHistoryEntry) {
        isShowingResearchCenter = false
        selectedHistoryEntry = entry
    }
}

private struct ResearchToolbarLabel: View {
    let runningCount: Int

    var body: some View {
        Label {
            Text("Research")
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
                .overlay(alignment: .topTrailing) {
                    if runningCount > 0 {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .overlay {
                                Circle()
                                    .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
                            }
                            .offset(x: 3, y: -2)
                    }
                }
        }
        .accessibilityLabel(
            runningCount == 0
                ? "Research"
                : "Research, \(runningCount) running"
        )
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
            Button(action: onAdd) {
                Label("Add Your First App", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }
}
