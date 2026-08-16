import ReadRevsCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var isAddingItem: Bool
    @State private var pendingRemoval: SidebarRemovalRequest?

    private var ownedApps: [TrackedApp] {
        store.library.apps.filter { $0.kind == .owned }
    }

    private var competitors: [TrackedApp] {
        store.library.apps.filter { $0.kind == .competitor }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $store.selection) {
                Section("My Apps") {
                    ForEach(ownedApps) { app in
                        AppSidebarRow(app: app)
                            .tag(SidebarSelection.app(app.adamID))
                            .contextMenu {
                                removalButton(for: app)
                            }
                    }
                }

                Section("Research Apps") {
                    ForEach(store.sidebarProjects) { project in
                        SidebarRow(title: project.name, symbol: "scope")
                            .tag(SidebarSelection.project(project.id))
                            .contextMenu {
                                removalButton(for: project)
                            }
                    }
                }

                if !competitors.isEmpty {
                    Section("Competitors") {
                        ForEach(competitors) { app in
                            AppSidebarRow(app: app)
                                .tag(SidebarSelection.app(app.adamID))
                                .contextMenu {
                                    removalButton(for: app)
                                }
                        }
                    }
                }
            }

            Divider()

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 38)
            .padding(.horizontal, 16)
            .help("Settings and Apple Ads Connection")
            .accessibilityLabel("Settings and Apple Ads Connection")
        }
        .navigationTitle("ReadRevs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add App or Research App")
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("Add App or Research App")
                .disabled(store.isReadOnly)
            }
        }
        .onDeleteCommand {
            requestRemoval(of: store.selection)
        }
        .alert(item: $pendingRemoval) { request in
            Alert(
                title: Text(request.title),
                message: Text(request.message),
                primaryButton: .destructive(Text(request.actionTitle)) {
                    remove(request.selection)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func removalButton(for app: TrackedApp) -> some View {
        Button(role: .destructive) {
            pendingRemoval = .app(app)
        } label: {
            Label("Remove App", systemImage: "trash")
        }
        .disabled(store.isReadOnly)
    }

    private func removalButton(for project: ResearchProject) -> some View {
        Button(role: .destructive) {
            pendingRemoval = .project(project)
        } label: {
            Label("Delete Research App", systemImage: "trash")
        }
        .disabled(store.isReadOnly)
    }

    private func requestRemoval(of selection: SidebarSelection?) {
        guard !store.isReadOnly, let selection else { return }
        switch selection {
        case let .app(adamID):
            if let app = store.app(adamID: adamID) {
                pendingRemoval = .app(app)
            }
        case let .project(id):
            if let project = store.project(id: id) {
                pendingRemoval = .project(project)
            }
        }
    }

    private func remove(_ selection: SidebarSelection) {
        switch selection {
        case let .app(adamID):
            store.removeApp(adamID: adamID)
        case let .project(id):
            store.removeProject(id: id)
        }
    }
}

private struct SidebarRemovalRequest: Identifiable {
    let selection: SidebarSelection
    let name: String
    let kind: Kind

    enum Kind {
        case app
        case project
    }

    var id: SidebarSelection { selection }

    var title: String {
        switch kind {
        case .app: "Remove App?"
        case .project: "Delete Research App?"
        }
    }

    var message: String {
        switch kind {
        case .app:
            "Remove \"\(name)\" from ReadRevs? This does not affect the App Store."
        case .project:
            "Delete \"\(name)\" and all of its saved keywords and ranking scans from this Mac?"
        }
    }

    var actionTitle: String {
        kind == .app ? "Remove" : "Delete"
    }

    static func app(_ app: TrackedApp) -> SidebarRemovalRequest {
        SidebarRemovalRequest(selection: .app(app.adamID), name: app.name, kind: .app)
    }

    static func project(_ project: ResearchProject) -> SidebarRemovalRequest {
        SidebarRemovalRequest(selection: .project(project.id), name: project.name, kind: .project)
    }
}

private struct AppSidebarRow: View {
    let app: TrackedApp

    var body: some View {
        HStack(spacing: 8) {
            AsyncImage(url: app.artworkURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(.quaternary)
                        Image(systemName: app.kind == .owned ? "app.fill" : "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 25, height: 25)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityHidden(true)

            Text(app.name)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
                .lineLimit(2)
        } icon: {
            Image(systemName: symbol)
        }
        .padding(.vertical, 2)
    }
}
