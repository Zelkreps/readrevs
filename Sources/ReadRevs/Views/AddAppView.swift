import SwiftUI

struct AddAppView: View {
    @Environment(\.dismiss) private var dismiss

    let client: any AppleReviewClientProtocol
    let onAdd: (AppMetadata) -> Void

    @State private var query = ""
    @State private var storefront = Storefront.unitedStates
    @State private var searchResults: [AppMetadata] = []
    @State private var isSearching = false
    @State private var didCompleteSearch = false
    @State private var searchErrorMessage: String?
    @State private var addErrorMessage: String?
    @State private var activeSearchID: UUID?
    @State private var lookupRequest: DirectLookupRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            searchControls
            Divider()
            results
            Divider()
            footer
        }
        .frame(width: 640, height: 640)
        .task(id: SearchTask(query: query, storefront: storefront)) {
            await updateSuggestions()
        }
        .task(id: lookupRequest) {
            guard let lookupRequest else { return }
            await addDirectApp(lookupRequest)
        }
        .onDisappear {
            lookupRequest = nil
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add App")
                    .font(.title2.weight(.semibold))
                Text("Search by name, or paste an App Store ID or URL.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                lookupRequest = nil
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Find an app", systemImage: "magnifyingglass")
                .font(.headline)

            HStack(spacing: 10) {
                TextField(
                    "App name, ID, or URL",
                    text: $query,
                    prompt: Text("Yelp, 284910350, or an apps.apple.com URL")
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .onSubmit {
                    useSubmittedInput()
                }
                .disabled(lookupRequest != nil)

                Picker("Storefront", selection: $storefront) {
                    ForEach(sortedStorefronts) { item in
                        Text("\(item.flagEmoji) \(item.displayName)")
                            .tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
                .help("Storefront used for app search and metadata")
                .disabled(lookupRequest != nil)
            }

            Text("Suggestions come from Apple's public App Store search. Reviews are then checked across all \(Storefront.allCases.count) storefronts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    @ViewBuilder
    private var results: some View {
        Group {
            if let directAppID {
                ContentUnavailableView {
                    Label("App ID recognized", systemImage: "checkmark.circle")
                } description: {
                    Text("ReadRevs will look up App Store ID \(directAppID) in \(storefront.displayName).")
                } actions: {
                    Button {
                        beginDirectAdd()
                    } label: {
                        directLookupLabel
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(lookupRequest != nil)
                }
            } else if trimmedQuery.isEmpty {
                CompactSearchPlaceholder()
            } else if trimmedQuery.count < 2 {
                ContentUnavailableView("Keep typing…", systemImage: "ellipsis")
            } else if isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching \(storefront.displayName)…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let searchErrorMessage {
                ContentUnavailableView {
                    Label("Search unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(searchErrorMessage)
                }
            } else if didCompleteSearch, searchResults.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
            } else {
                List(searchResults) { app in
                    Button {
                        select(app)
                    } label: {
                        AppSearchResultRow(app: app)
                    }
                    .buttonStyle(.plain)
                    .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                        dimensions[.leading] + 64
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Public App Store data · no developer account required")
                    .font(.caption)
                Text("The latest written reviews are synced locally and can be removed at any time.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let addErrorMessage {
                Label(addErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 230, alignment: .trailing)
            }

            Button {
                beginDirectAdd()
            } label: {
                directLookupLabel
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(directAppID == nil || lookupRequest != nil)
        }
        .padding(20)
    }

    @ViewBuilder
    private var directLookupLabel: some View {
        if lookupRequest != nil {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Looking up app")
        } else {
            Text("Add by ID or URL")
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var directAppID: Int64? {
        try? AppIdentifierParser.parse(trimmedQuery)
    }

    private var sortedStorefronts: [Storefront] {
        Storefront.allCases.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    @MainActor
    private func updateSuggestions() async {
        let requestID = UUID()
        activeSearchID = requestID
        searchResults = []
        searchErrorMessage = nil
        addErrorMessage = nil
        didCompleteSearch = false
        isSearching = false

        guard directAppID == nil, trimmedQuery.count >= 2 else { return }

        do {
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
        } catch {
            return
        }

        guard activeSearchID == requestID else { return }
        isSearching = true
        defer {
            if activeSearchID == requestID {
                isSearching = false
            }
        }

        do {
            let apps = try await client.searchApps(
                term: trimmedQuery,
                storefront: storefront,
                limit: 20
            )
            guard !Task.isCancelled, activeSearchID == requestID else { return }
            searchResults = apps
            didCompleteSearch = true
        } catch is CancellationError {
            return
        } catch {
            guard activeSearchID == requestID else { return }
            searchErrorMessage = error.localizedDescription
        }
    }

    private func useSubmittedInput() {
        if directAppID != nil {
            beginDirectAdd()
        } else if let firstResult = searchResults.first {
            select(firstResult)
        }
    }

    @MainActor
    private func beginDirectAdd() {
        guard let appID = directAppID, lookupRequest == nil else { return }
        lookupRequest = DirectLookupRequest(
            id: UUID(),
            appID: appID,
            storefront: storefront
        )
    }

    @MainActor
    private func addDirectApp(_ request: DirectLookupRequest) async {
        addErrorMessage = nil
        defer {
            if lookupRequest == request {
                lookupRequest = nil
            }
        }

        do {
            let app = try await client.lookup(
                appID: request.appID,
                storefront: request.storefront
            )
            try Task.checkCancellation()
            guard lookupRequest == request else { return }
            select(app)
        } catch is CancellationError {
            return
        } catch {
            guard lookupRequest == request else { return }
            addErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func select(_ app: AppMetadata) {
        onAdd(app)
        dismiss()
    }
}

private struct CompactSearchPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "app.badge")
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            Text("Search the App Store")
                .font(.title3.weight(.semibold))

            Text("Type at least two characters to see matching apps, or paste an ID or URL.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct SearchTask: Hashable {
    let query: String
    let storefront: Storefront
}

private struct DirectLookupRequest: Hashable {
    let id: UUID
    let appID: Int64
    let storefront: Storefront
}

private struct AppSearchResultRow: View {
    let app: AppMetadata

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: app.artworkURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "app.dashed")
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, height: 52)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(app.sellerName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("ID \(app.appID)")
                    if !app.primaryGenre.isEmpty {
                        Text("·")
                        Text(app.primaryGenre)
                    }
                    if let rating = app.averageRating {
                        Text("·")
                        Label(
                            rating.formatted(.number.precision(.fractionLength(1))),
                            systemImage: "star.fill"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Add")
                .fontWeight(.medium)
                .foregroundStyle(.tint)
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
                .font(.title3)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Add \(app.name) by \(app.sellerName)")
    }
}
