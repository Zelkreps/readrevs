import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var isAddingItem = false
    @State private var researchManager = CodexResearchSessionManager()

    var body: some View {
        @Bindable var researchManager = researchManager

        NavigationSplitView {
            SidebarView(isAddingItem: $isAddingItem)
                .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 290)
        } detail: {
            detail
        }
        .environment(researchManager)
        .frame(minWidth: 980, minHeight: 560)
        .sheet(isPresented: $isAddingItem) {
            AddItemSheet(isPresented: $isAddingItem)
                .environmentObject(store)
        }
        .sheet(item: $researchManager.presentedSession) { session in
            CodexResearchChatView(
                model: session,
                sessionManager: researchManager
            )
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
        .alert(item: $store.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: researchManager.presentedSession?.id) { _, sessionID in
            if sessionID == nil {
                researchManager.discardUnsubmittedSessions()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selection {
        case let .project(id):
            if store.project(id: id) != nil {
                ResearchProjectDetailView(projectID: id)
                    .id(id)
            } else {
                EmptySelectionView(isAddingItem: $isAddingItem)
            }
        case let .app(adamID):
            if store.app(adamID: adamID) != nil {
                TrackedAppDetailView(adamID: adamID)
                    .id(adamID)
            } else {
                EmptySelectionView(isAddingItem: $isAddingItem)
            }
        case nil:
            EmptySelectionView(isAddingItem: $isAddingItem)
        }
    }
}

private struct EmptySelectionView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var isAddingItem: Bool

    var body: some View {
        ContentUnavailableView {
            Label("No Selection", systemImage: "square.grid.2x2")
        } actions: {
            Button("Add Item") {
                isAddingItem = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(store.isReadOnly)
        }
    }
}
