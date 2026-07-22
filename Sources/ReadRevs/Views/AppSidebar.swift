import SwiftUI

struct AppSidebar: View {
    let apps: [AppMetadata]
    @Binding var selection: Int64?
    let onAdd: () -> Void
    let onRemove: (AppMetadata) -> Void

    var body: some View {
        List(selection: $selection) {
            Section("Review Apps") {
                ForEach(apps) { app in
                    AppSidebarRow(app: app)
                        .tag(app.appID)
                        .contextMenu {
                            if let appStoreURL = app.appStoreURL {
                                Link(destination: appStoreURL) {
                                    Label("Open in App Store", systemImage: "arrow.up.right.square")
                                }
                            }
                            Divider()
                            Button("Remove…", role: .destructive) {
                                onRemove(app)
                            }
                        }
                }
            }
        }
        .overlay {
            if apps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Saved apps appear here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Add App", action: onAdd)
                }
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onAdd) {
                Label("Add App", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle("ReadRevs")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
    }
}

private struct AppSidebarRow: View {
    let app: AppMetadata

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: app.artworkURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "app.dashed")
                        .resizable()
                        .scaledToFit()
                        .padding(9)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 38, height: 38)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .lineLimit(1)
                    .fontWeight(.medium)
                Text(app.primaryStorefront.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
