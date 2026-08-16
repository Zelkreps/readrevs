import ReadRevsCore
import AppKit
import SwiftUI

private enum TrackedAppSection: String, CaseIterable, Identifiable {
    case reviews = "Reviews"
    case searchPresence = "Search Presence"

    var id: String { rawValue }
}

struct TrackedAppDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var reviewModel = ReviewDashboardController()
    @StateObject private var searchPresenceModel = AppSearchPresenceController()
    @State private var section: TrackedAppSection = .reviews

    let adamID: Int64

    var body: some View {
        if let app = store.app(adamID: adamID) {
            VStack(spacing: 0) {
                AppDetailHeader(
                    app: reviewModel.metadata ?? app,
                    isRefreshing: reviewModel.isRefreshing,
                    onRefresh: refresh
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                TrackedAppSectionPicker(selection: $section)
                    .frame(maxWidth: .infinity)
                .frame(height: 24)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                Divider()

                Group {
                    switch section {
                    case .reviews:
                        ReviewDashboardView(model: reviewModel)
                    case .searchPresence:
                        AppSearchPresenceView(
                            controller: searchPresenceModel,
                            app: reviewModel.metadata ?? app
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(app.name)
            .task(id: adamID) {
                guard let current = store.app(adamID: adamID) else { return }
                searchPresenceModel.refresh(app: current, store: store)
                if let refreshed = await reviewModel.load(current) {
                    store.updateAppMetadata(refreshed)
                    if let updated = store.app(adamID: adamID),
                       updated.name != current.name
                            || updated.primaryGenre != current.primaryGenre
                            || updated.primaryStore != current.primaryStore
                    {
                        searchPresenceModel.refresh(app: updated, store: store)
                    }
                }
            }
            .onDisappear {
                reviewModel.cancel()
                searchPresenceModel.cancel()
            }
        }
    }

    private func refresh() {
        Task {
            guard let refreshed = await reviewModel.refresh() else {
                return
            }
            store.updateAppMetadata(refreshed)
        }
    }

}

private struct TrackedAppSectionPicker: NSViewRepresentable {
    @Binding var selection: TrackedAppSection

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: TrackedAppSection.allCases.map(\.rawValue),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.segmentDistribution = .fillEqually
        control.setAccessibilityLabel("App Detail")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.selectedSegment = TrackedAppSection.allCases.firstIndex(of: selection) ?? 0
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<TrackedAppSection>

        init(selection: Binding<TrackedAppSection>) {
            self.selection = selection
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            guard TrackedAppSection.allCases.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = TrackedAppSection.allCases[sender.selectedSegment]
        }
    }
}

private struct AppDetailHeader: View {
    let app: TrackedApp
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: app.artworkURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: 11)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: app.kind == .owned ? "app.fill" : "person.2.fill")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Text(app.developerName)
                    Text("·")
                    Text("ID: \(app.adamID)")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

                HStack(spacing: 12) {
                    if let version = app.version, !version.isEmpty {
                        Label("v\(version)", systemImage: "shippingbox")
                    }
                    if !app.primaryGenre.isEmpty {
                        Label(app.primaryGenre, systemImage: "square.grid.2x2")
                    }
                    Label(reviewStoreTitle(app.primaryStore), systemImage: "globe")
                    if let date = app.currentVersionReleaseDate ?? app.releaseDate {
                        Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(action: onRefresh) {
                ZStack {
                    Image(systemName: "arrow.clockwise")
                        .opacity(isRefreshing ? 0 : 1)
                    ProgressView()
                        .controlSize(.small)
                        .opacity(isRefreshing ? 1 : 0)
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing)
            .help("Refresh Metadata and Reviews")
            .accessibilityLabel("Refresh Metadata and Reviews")

            if let appStoreURL = app.appStoreURL {
                Link(destination: appStoreURL) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open in App Store")
                .accessibilityLabel("Open \(app.name) in App Store")
            }
        }
    }
}
