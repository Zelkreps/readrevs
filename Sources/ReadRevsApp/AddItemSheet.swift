import ReadRevsCore
import SwiftUI

private enum AddItemMode: String, CaseIterable, Identifiable {
    case app = "App Store App"
    case research = "Research App"

    var id: String { rawValue }
}

private enum AddItemField: Hashable {
    case projectName
    case topic
    case appQuery
}

struct AddItemSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var isPresented: Bool

    @State private var mode: AddItemMode = .research
    @State private var projectName = ""
    @State private var topic = ""
    @State private var researchStore = "us"

    @State private var appQuery = ""
    @State private var appStore = "us"
    @State private var appResults: [StoreAppSearchResult] = []
    @State private var selectedAppID: Int64?
    @State private var isSearching = false
    @State private var searchMessage: String?
    @State private var resultStore: String?
    @State private var searchGeneration = UUID()
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focusedField: AddItemField?

    private let appStoreClient = ITunesAppStoreClient()

    var body: some View {
        VStack(spacing: 0) {
            FullWidthItemTypePicker(selection: $mode)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Group {
                switch mode {
                case .research:
                    researchForm
                case .app:
                    appForm
                }
            }
            .padding(16)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(mode == .research ? "Create Research App" : "Add App") {
                    commit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCommit)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 520)
        .fixedSize(horizontal: true, vertical: true)
        .task {
            await Task.yield()
            focusedField = .projectName
        }
        .onChange(of: mode) { _, value in
            focusedField = value == .research ? .projectName : .appQuery
        }
        .onChange(of: appStore) { _, _ in
            if appQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resetAppSearch()
            } else {
                searchApps(after: .milliseconds(250))
            }
        }
        .onChange(of: appQuery) { _, query in
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resetAppSearch()
            } else {
                searchApps(after: .milliseconds(350))
            }
        }
        .onDisappear {
            searchGeneration = UUID()
            searchTask?.cancel()
        }
    }

    private var researchForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Name", text: $projectName)
                    .textFieldStyle(.plain)
                    .sheetInputStyle()
                    .focused($focusedField, equals: .projectName)
                    .accessibilityLabel("Name")

                TextField("Topic (Optional)", text: $topic)
                    .textFieldStyle(.plain)
                    .sheetInputStyle()
                    .focused($focusedField, equals: .topic)
                    .accessibilityLabel("Topic")
            }

            FlagStorePicker(
                selection: $researchStore,
                stores: ResearchPresets.targets.map(\.target.store),
                accessibilityLabel: "Primary Store",
                fieldLabel: "Primary Store"
            )
        }
    }

    private var appForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                FlagStorePicker(
                    selection: $appStore,
                    stores: ResearchPresets.storeTitles.keys.sorted {
                        storeTitle($0).localizedCaseInsensitiveCompare(storeTitle($1)) == .orderedAscending
                    },
                    accessibilityLabel: "App Store country"
                )
                .frame(width: 168)

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("App name, ID, or App Store URL", text: $appQuery)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .appQuery)
                        .accessibilityLabel("App name, ID, or App Store URL")
                        .onSubmit { searchApps() }

                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator.opacity(0.85))
                }
            }

            if appResults.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: isSearching ? "arrow.trianglehead.2.clockwise.rotate.90" : "magnifyingglass")
                        .font(.title3)
                    Text(searchMessage ?? (isSearching ? "Searching App Store" : "Search App Store"))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 112)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(appResults) { app in
                            Button {
                                selectedAppID = app.adamID
                            } label: {
                                AppSearchResultRow(app: app)
                            }
                            .buttonStyle(.plain)
                            .frame(height: 50)
                            .padding(.horizontal, 8)
                            .background(
                                selectedAppID == app.adamID ? Color.primary.opacity(0.16) : .clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel("\(app.name), \(app.developerName), \(app.primaryGenre)")
                            .accessibilityValue(selectedAppID == app.adamID ? "Selected" : "")

                            if app.id != appResults.last?.id {
                                Divider()
                                    .padding(.leading, 58)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                    .padding(.trailing, 10)
                }
                .scrollIndicators(.visible)
                .accessibilityLabel("App Store search results")
                .frame(height: searchResultsHeight)
                .padding(.trailing, -3)
            }
        }
    }

    private var canCommit: Bool {
        switch mode {
        case .research:
            !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .app:
            selectedAppID != nil && resultStore == appStore
        }
    }

    private func commit() {
        switch mode {
        case .research:
            store.createProject(
                name: projectName,
                topic: topic,
                targets: researchTargets,
                genres: ResearchPresets.defaultGenres,
                seedKeywords: []
            )
        case .app:
            guard let selectedAppID,
                  let result = appResults.first(where: { $0.adamID == selectedAppID }),
                  let resultStore
            else {
                return
            }
            store.addApp(result, store: resultStore, kind: .owned)
        }
        isPresented = false
    }

    private func searchApps(after delay: Duration? = nil) {
        let query = appQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchTask?.cancel()
        let storeSnapshot = appStore
        let generation = UUID()
        searchGeneration = generation
        isSearching = true
        searchMessage = nil
        appResults = []
        selectedAppID = nil
        resultStore = nil

        searchTask = Task {
            do {
                if let delay { try await Task.sleep(for: delay) }
                let results: [StoreAppSearchResult]
                if let identifier = AppStoreIdentifier.parse(query) {
                    results = try await appStoreClient.lookup(adamID: identifier, country: storeSnapshot).map { [$0] } ?? []
                } else {
                    results = try await appStoreClient.search(term: query, country: storeSnapshot, limit: 50)
                }
                guard !Task.isCancelled,
                      searchGeneration == generation,
                      appStore == storeSnapshot
                else {
                    return
                }
                appResults = results
                resultStore = storeSnapshot
                selectedAppID = appResults.first?.adamID
                if appResults.isEmpty { searchMessage = "No Apps Found" }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      searchGeneration == generation,
                      (error as? URLError)?.code != .cancelled
                else {
                    return
                }
                searchMessage = "Search Failed"
                store.showError(title: "App Store Search Failed", error: error)
            }
            if searchGeneration == generation { isSearching = false }
        }
    }

    private func resetAppSearch() {
        searchTask?.cancel()
        searchGeneration = UUID()
        appResults = []
        selectedAppID = nil
        resultStore = nil
        searchMessage = nil
        isSearching = false
    }

    private var researchTargets: [StoreTarget] {
        let primaryTargets = ResearchPresets.targets.filter { $0.target.store == researchStore }
        let remainingTargets = ResearchPresets.targets.filter { $0.target.store != researchStore }
        return (primaryTargets + remainingTargets).map(\.target)
    }

    private var searchResultsHeight: CGFloat {
        min(max(CGFloat(appResults.count) * 54, 132), 280)
    }

    private func storeTitle(_ code: String) -> String {
        ResearchPresets.storeTitles[code] ?? code.uppercased()
    }
}

private struct FullWidthItemTypePicker: View {
    @Binding var selection: AddItemMode
    @FocusState private var focusedItem: AddItemMode?

    var body: some View {
        HStack(spacing: 1) {
            ForEach(AddItemMode.allCases) { item in
                Button {
                    selection = item
                } label: {
                    Text(item.rawValue)
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($focusedItem, equals: item)
                .focusEffectDisabled()
                .foregroundStyle(selection == item ? Color.white : Color.primary)
                .background(
                    selection == item ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay {
                    if focusedItem == item, selection != item {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.accentColor, lineWidth: 1)
                    }
                }
                .accessibilityLabel(item.rawValue)
                .accessibilityValue(selection == item ? "Selected" : "")
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator.opacity(0.7))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Item Type")
        .onAppear { focusedItem = selection }
        .onChange(of: selection) { _, value in focusedItem = value }
    }
}

private struct AppSearchResultRow: View {
    let app: StoreAppSearchResult

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: app.artworkURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.quaternary)
                        .overlay { Image(systemName: "app.fill").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)
                    .lineLimit(1)
                Text([app.developerName, app.primaryGenre].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SheetInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator.opacity(0.85))
            }
    }
}

private extension View {
    func sheetInputStyle() -> some View {
        modifier(SheetInputStyle())
    }
}

private struct FlagStorePicker: View {
    @Binding var selection: String
    let stores: [String]
    let accessibilityLabel: String
    let fieldLabel: String?

    @State private var isPresented = false
    @State private var searchText = ""

    init(
        selection: Binding<String>,
        stores: [String],
        accessibilityLabel: String,
        fieldLabel: String? = nil
    ) {
        _selection = selection
        self.stores = stores
        self.accessibilityLabel = accessibilityLabel
        self.fieldLabel = fieldLabel
    }

    var body: some View {
        Button {
            searchText = ""
            isPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                if let fieldLabel {
                    Text(fieldLabel)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                }
                Text(flagEmoji(for: selection))
                Text(storeTitle(selection))
                    .lineLimit(1)
                if fieldLabel == nil {
                    Spacer(minLength: 4)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityLabel), \(storeTitle(selection))")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search Countries", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredStores, id: \.self) { code in
                            Button {
                                selection = code
                                isPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    Text(flagEmoji(for: code))
                                        .font(.title3)
                                    Text(storeTitle(code))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 8)
                                .frame(height: 34)
                                .background(
                                    selection == code ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(storeTitle(code))
                        }
                    }
                    .padding(.trailing, 10)
                }
            }
            .padding(10)
            .frame(width: 270, height: min(CGFloat(filteredStores.count * 36 + 58), 330))
        }
    }

    private var filteredStores: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return stores.filter {
            query.isEmpty
                || storeTitle($0).localizedCaseInsensitiveContains(query)
                || $0.localizedCaseInsensitiveContains(query)
        }
    }

    private func storeTitle(_ code: String) -> String {
        ResearchPresets.storeTitles[code] ?? code.uppercased()
    }

    private func flagEmoji(for countryCode: String) -> String {
        let base: UInt32 = 127_397
        let scalars = countryCode.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(base + $0.value)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

private extension ResearchPresets {
    static var defaultGenres: [String] {
        genres
    }
}
