import ReadRevsCore
import SwiftUI
import UniformTypeIdentifiers

struct KeywordWorkspaceView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var discoveryController = DiscoveryController()
    @StateObject private var rankingController = RankingScanController()
    @State private var selectedStore = ""
    @State private var searchText = ""
    @State private var storeSearchText = ""
    @State private var isChoosingStore = false
    @State private var isAddingKeywords = false
    @State private var isShowingSuggestions = false
    @State private var isShowingStatusDetails = false
    @State private var isImporting = false
    @State private var usedSuggestionExpansionSeedsByStore: [String: Set<String>] = [:]
    @State private var sortOrder = [
        KeyPathComparator(\KeywordWorkspaceRow.popularitySortValue, order: .reverse),
    ]
    @State private var metricFilters = KeywordMetricFilters()

    let projectID: UUID

    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                let trackedRows = workspaceRows(project: project, tracked: true)
                let suggestions = workspaceRows(project: project, tracked: false)
                let filteredRows = sortedWorkspaceRows(
                    filteredTrackedRows(trackedRows),
                    using: sortOrder
                )

                VStack(spacing: 0) {
                    workspaceToolbar(
                        project: project,
                        trackedRows: trackedRows,
                        suggestions: suggestions,
                        filteredCount: filteredRows.count
                    )

                    Divider()

                    ZStack(alignment: .top) {
                        if filteredRows.isEmpty {
                            emptyState(project: project, hasTrackedKeywords: !trackedRows.isEmpty)
                        } else {
                            keywordTable(filteredRows)
                        }

                        if isAddingKeywords {
                            InlineKeywordEntry(
                                storeCode: selectedStore,
                                onCancel: { isAddingKeywords = false },
                                onAdd: addKeywordsAndFetch
                            )
                            .padding(.top, 8)
                            .zIndex(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle(project.name)
                .onAppear { selectInitialStore(from: project) }
                .onChange(of: project.targets) { _, _ in selectInitialStore(from: project) }
                .task(id: selectedStore) {
                    let storeSnapshot = selectedStore
                    await Task.yield()
                    guard !Task.isCancelled,
                          selectedStore == storeSnapshot,
                          let latestProject = store.project(id: projectID)
                    else {
                        return
                    }
                    backfillMissingMetricsIfNeeded(project: latestProject)
                }
                .onDisappear {
                    discoveryController.cancel()
                    rankingController.cancel()
                }
                .sheet(isPresented: $isShowingSuggestions) {
                    SuggestionsSheet(
                        storeCode: selectedStore,
                        rows: suggestions,
                        progressText: suggestionProgressText,
                        onRefresh: { refreshSuggestions(project: project) },
                        onSearchMore: { searchMoreSuggestions(project: project) },
                        onAdd: addKeywordsAndFetch
                    )
                }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.commaSeparatedText],
                    allowsMultipleSelection: false,
                    onCompletion: importCSV
                )
            }
        }
        .searchable(text: $searchText, prompt: "Filter Keywords")
    }

    private func workspaceToolbar(
        project: ResearchProject,
        trackedRows: [KeywordWorkspaceRow],
        suggestions: [KeywordWorkspaceRow],
        filteredCount: Int
    ) -> some View {
        HStack(spacing: 8) {
            storeSelector(project: project)

            Text(keywordCountLabel(filtered: filteredCount, total: trackedRows.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer(minLength: 8)

            activityStatus

            Button {
                isAddingKeywords = true
            } label: {
                Label("Add Keywords", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("k", modifiers: .command)
            .disabled(store.isReadOnly || selectedStore.isEmpty)

            suggestionsButton(project: project, count: suggestions.count)

            MetricFiltersButton(
                filters: $metricFilters,
                showsDifficulty: true,
                showsPosition: true
            )

            if discoveryController.isRunning || rankingController.isRunning {
                Button {
                    discoveryController.cancel()
                    rankingController.cancel()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Cancel Update")
                .accessibilityLabel("Cancel Keyword Update")
            } else {
                Button {
                    refreshAll(project: project, trackedRows: trackedRows)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Update Popularity, Difficulty, Position, and Ranking Apps")
                .accessibilityLabel("Update Keyword Data")
                .disabled(store.isReadOnly || selectedStore.isEmpty)
            }

            moreMenu(project: project)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private func storeSelector(project: ResearchProject) -> some View {
        Button {
            storeSearchText = ""
            isChoosingStore.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(flagEmoji(for: selectedStore))
                Text(storeTitle(selectedStore))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .help("Choose App Store country")
        .accessibilityLabel("Store, \(storeTitle(selectedStore))")
        .popover(isPresented: $isChoosingStore, arrowEdge: .bottom) {
            StoreChooser(
                stores: storeOptions(project: project),
                selectedStore: selectedStore,
                searchText: $storeSearchText,
                trackedCount: { trackedKeywordCount(for: $0, in: project) },
                onSelect: { storeCode in
                    selectedStore = storeCode
                    isChoosingStore = false
                }
            )
        }
    }

    @ViewBuilder
    private var activityStatus: some View {
        if discoveryController.isRunning && rankingController.isRunning {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                Text("Updating metrics")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if discoveryController.isRunning {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                Text(discoveryController.progressLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if rankingController.isRunning {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                Text("Rankings \(rankingController.completed)/\(rankingController.total)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let status = combinedStatusText {
            HStack(spacing: 5) {
                Image(systemName: statusIsWarning(status) ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(statusIsWarning(status) ? .orange : .green)

                Text(status)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(status)

                Button {
                    isShowingStatusDetails.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .help(status)
                .accessibilityLabel("Show Keyword Update Details")
                .accessibilityValue(status)
                .popover(isPresented: $isShowingStatusDetails, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            statusIsWarning(status) ? "Keyword Update Needs Attention" : "Keyword Update Complete",
                            systemImage: statusIsWarning(status) ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(statusIsWarning(status) ? .orange : .green)

                        Text(status)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(width: 320, alignment: .leading)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 260, alignment: .trailing)
        }
    }

    private var combinedStatusText: String? {
        let messages = [discoveryController.statusText, rankingController.statusText].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private func statusIsWarning(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized.contains("unavailable") || normalized.contains("failed")
    }

    private func suggestionsButton(project: ResearchProject, count: Int) -> some View {
        Button {
            presentSuggestions(project: project)
        } label: {
            Label(
                count == 0 ? "Suggestions" : "\(count) Suggestions",
                systemImage: "lightbulb.fill"
            )
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(store.isReadOnly || discoveryController.isRunning || selectedStore.isEmpty)
    }

    private func presentSuggestions(project: ResearchProject) {
        isShowingSuggestions = true
        if workspaceRows(project: project, tracked: false).isEmpty {
            refreshSuggestions(project: project)
        }
    }

    private func refreshSuggestions(project: ResearchProject) {
        let storeCode = selectedStore
        guard !storeCode.isEmpty else { return }
        usedSuggestionExpansionSeedsByStore[suggestionExpansionScope(storeCode)] = []
        let target = target(for: storeCode, in: project)
        let focusAppName = project.focusAppAdamID.flatMap { store.app(adamID: $0)?.name }
        let seeds = KeywordSuggestionSeedBuilder.seeds(
            project: project,
            store: storeCode,
            focusAppName: focusAppName
        )

        startSuggestionDiscovery(
            project: project,
            target: target,
            storeCode: storeCode,
            seeds: seeds,
            appendsResults: false
        )
    }

    private func searchMoreSuggestions(project: ResearchProject) {
        let storeCode = selectedStore
        guard !storeCode.isEmpty,
              let latestProject = store.project(id: projectID)
        else {
            return
        }

        let scope = suggestionExpansionScope(storeCode)
        let usedKeys = usedSuggestionExpansionSeedsByStore[scope] ?? []
        let rows = workspaceRows(project: latestProject, tracked: false)
        let orderedRows = rows.sorted { lhs, rhs in
            switch (lhs.metrics.focusAppPosition, rhs.metrics.focusAppPosition) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.hasPopularityData != rhs.hasPopularityData {
                    return lhs.hasPopularityData
                }
                if lhs.popularity != rhs.popularity {
                    return lhs.popularity > rhs.popularity
                }
                if lhs.suggestionScoreSortValue != rhs.suggestionScoreSortValue {
                    return lhs.suggestionScoreSortValue > rhs.suggestionScoreSortValue
                }
                return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
            }
        }
        let seeds = Array(
            stableUniqueKeywords(orderedRows.map(\.keyword)).filter {
                !usedKeys.contains(normalizedKeyword($0))
            }.prefix(8)
        )
        guard !seeds.isEmpty else {
            discoveryController.statusText = "No unused suggestion layer remains. Refresh suggestions to start over."
            return
        }
        usedSuggestionExpansionSeedsByStore[scope, default: []].formUnion(
            seeds.map(normalizedKeyword)
        )

        startSuggestionDiscovery(
            project: latestProject,
            target: target(for: storeCode, in: latestProject),
            storeCode: storeCode,
            seeds: seeds,
            appendsResults: true
        )
    }

    private func startSuggestionDiscovery(
        project: ResearchProject,
        target: StoreTarget,
        storeCode: String,
        seeds: [String],
        appendsResults: Bool
    ) {
        discoveryController.startSuggestions(
            project: project,
            target: target,
            seeds: seeds,
            store: store,
            appendsResults: appendsResults
        ) { keywords in
            guard selectedStore.caseInsensitiveCompare(storeCode) == .orderedSame,
                  let latestProject = store.project(id: projectID)
            else {
                return
            }
            let pendingKeywords = rankingKeywordsNeedingRefresh(
                keywords,
                project: latestProject,
                storeCode: storeCode
            )
            guard !pendingKeywords.isEmpty else { return }
            rankingController.start(
                project: latestProject,
                keywords: pendingKeywords,
                storeCode: storeCode,
                store: store,
                prioritize: false
            )
        }
    }

    private func suggestionExpansionScope(_ storeCode: String) -> String {
        "\(projectID.uuidString)|\(storeCode.lowercased())"
    }

    private var suggestionProgressText: String? {
        if discoveryController.isRunning {
            return discoveryController.progressLabel
        }
        if rankingController.isRunning {
            return "Difficulty \(rankingController.completed)/\(rankingController.total)"
        }
        return nil
    }

    private func moreMenu(project: ResearchProject) -> some View {
        Menu {
            Menu {
                Button {
                    store.setFocusApp(nil, for: projectID)
                } label: {
                    Label("No Linked App", systemImage: project.focusAppAdamID == nil ? "checkmark" : "app.dashed")
                }

                ForEach(ownedApps) { app in
                    Button {
                        store.setFocusApp(app.adamID, for: projectID)
                    } label: {
                        Label(app.name, systemImage: project.focusAppAdamID == app.adamID ? "checkmark" : "app")
                    }
                }
            } label: {
                Label("Position App", systemImage: "app.badge.checkmark")
            }
            .disabled(ownedApps.isEmpty)

            Divider()

            Button {
                isImporting = true
            } label: {
                Label("Import CSV", systemImage: "square.and.arrow.down")
            }
            .disabled(store.isReadOnly)

            Divider()

            Text("Popularity: Apple Ads when connected")
            Text("Difficulty: rating-volume estimate")
            Text("Position: iTunes Search API order")
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More Keyword Actions and Data Sources")
        .accessibilityLabel("More Keyword Actions")
    }

    private func keywordTable(_ rows: [KeywordWorkspaceRow]) -> some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("Keyword", value: \.keyword) { row in
                Text(row.keyword)
                    .lineLimit(1)
                    .help(row.keyword)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.stopTracking(keyword: row.keyword, store: row.store, projectID: projectID)
                        } label: {
                            Label("Stop Tracking", systemImage: "minus.circle")
                        }
                    }
            }
            .width(min: 145, ideal: 190)

            TableColumn("Notes", value: \.noteSortValue) { row in
                KeywordNoteEditor(keyword: row.keyword, note: row.note) { note in
                    store.setNote(note, keyword: row.keyword, store: row.store, projectID: projectID)
                }
            }
            .width(min: 110, ideal: 150)

            TableColumn("Last Update", value: \.updateSortValue) { row in
                Text(updateLabel(row))
                    .foregroundStyle(.secondary)
            }
            .width(78)

            TableColumn("Popularity", value: \.popularitySortValue) { row in
                MetricBar(value: row.hasPopularityData ? row.popularity : nil, kind: .popularity)
            }
            .width(105)

            TableColumn("Difficulty", value: \.difficultySortValue) { row in
                MetricBar(value: row.metrics.difficulty, kind: .difficulty)
                    .help("Estimated from rating volume in the first iTunes Search API results")
            }
            .width(105)

            TableColumn("Position", value: \.positionSortValue) { row in
                if let position = row.metrics.focusAppPosition {
                    Text("#\(position)")
                        .monospacedDigit()
                        .foregroundStyle(position <= 3 ? .orange : .secondary)
                        .help("Observed iTunes Search API result order; not a guaranteed organic rank")
                } else {
                    Text("# —")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(58)

            TableColumn("Apps in Ranking", value: \.rankingAppCount) { row in
                RankingAppsCell(apps: row.metrics.topApps)
            }
            .width(min: 120, ideal: 160)
        }
        .alternatingRowBackgrounds(.enabled)
    }

    private func emptyState(project: ResearchProject, hasTrackedKeywords: Bool) -> some View {
        Group {
            if hasTrackedKeywords {
                if metricFilters.isActive {
                    ContentUnavailableView {
                        Label("No Keywords in Range", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No tracked keywords match the selected metric ranges.")
                    } actions: {
                        Button("Reset Filters") {
                            metricFilters = KeywordMetricFilters()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Matching Keywords", systemImage: "magnifyingglass")
                    } description: {
                        Text("No tracked keywords match \"\(searchText)\".")
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Keywords for \(selectedStore.uppercased())", systemImage: "text.magnifyingglass")
                } description: {
                    Text("Add keywords directly or explore suggestions for this store.")
                } actions: {
                    HStack(spacing: 8) {
                        Button("Add Keywords", systemImage: "plus") { isAddingKeywords = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isReadOnly || discoveryController.isRunning)
                        Button("Suggestions", systemImage: "lightbulb") {
                            presentSuggestions(project: project)
                        }
                        .disabled(discoveryController.isRunning)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ownedApps: [TrackedApp] {
        store.library.apps.filter { $0.kind == .owned }
    }

    private func storeOptions(project: ResearchProject) -> [String] {
        var seen: Set<String> = []
        return (project.targets.map(\.store) + ResearchPresets.targets.map(\.target.store))
            .filter { seen.insert($0).inserted }
    }

    private func selectInitialStore(from project: ResearchProject) {
        let options = storeOptions(project: project)
        if !options.contains(selectedStore) {
            selectedStore = options.first ?? ""
        }
    }

    private func filteredTrackedRows(_ rows: [KeywordWorkspaceRow]) -> [KeywordWorkspaceRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter {
            (query.isEmpty || $0.keyword.localizedCaseInsensitiveContains(query))
                && metricFilters.matches($0)
        }
    }

    private func keywordCountLabel(filtered: Int, total: Int) -> String {
        if filtered != total {
            return "\(filtered) of \(total) keywords"
        }
        return "\(total) keywords"
    }

    private func workspaceRows(project: ResearchProject, tracked: Bool) -> [KeywordWorkspaceRow] {
        let suggestionKeywords = Set(project.keywords.lazy.filter {
            $0.store == selectedStore
                && ($0.source == .appleSearchHints || $0.isAppleAdsSuggestion)
                && !$0.isActivelyTracked
        }.map { normalizedKeyword($0.keyword) })
        let records = project.keywords.filter {
            $0.store == selectedStore
                && $0.isActivelyTracked == tracked
                && (tracked || suggestionKeywords.contains(normalizedKeyword($0.keyword)))
        }
        let observationGroups = Dictionary(grouping: project.rankingObservations.filter {
            $0.store == selectedStore
        }) { normalizedKeyword($0.keyword) }
        let scanDates = project.rankingScans.filter {
            $0.store == selectedStore
        }.reduce(into: [String: Date]()) { result, scan in
            let key = normalizedKeyword(scan.keyword)
            result[key] = max(result[key] ?? .distantPast, scan.checkedAt)
        }

        return Dictionary(grouping: records) { normalizedKeyword($0.keyword) }
            .compactMap { normalized, groupedRecords in
                let measuredRecords = groupedRecords.filter(\.hasPopularityMeasurement)
                guard let representative = groupedRecords.max(by: { lhs, rhs in
                    if lhs.opportunityScore != rhs.opportunityScore {
                        return lhs.opportunityScore < rhs.opportunityScore
                    }
                    let lhsExact = lhs.hasPopularityMeasurement ? lhs.popularity : -1
                    let rhsExact = rhs.hasPopularityMeasurement ? rhs.popularity : -1
                    if lhsExact != rhsExact { return lhsExact < rhsExact }
                    return (lhs.effectiveSuggestionScore ?? -1)
                        < (rhs.effectiveSuggestionScore ?? -1)
                }) else {
                    return nil
                }
                let metrics = RankingIndex.searchMetrics(
                    keyword: representative.keyword,
                    store: selectedStore,
                    focusAppAdamID: project.focusAppAdamID,
                    observations: observationGroups[normalized] ?? []
                )
                let note = groupedRecords.lazy.compactMap(\.note).first { !$0.isEmpty }
                var updateDates = groupedRecords.compactMap(\.updatedAt)
                    + groupedRecords.compactMap(\.popularityCheckedAt)
                if let scanDate = scanDates[normalized] { updateDates.append(scanDate) }
                if let observationDate = observationGroups[normalized]?.map(\.checkedAt).max() {
                    updateDates.append(observationDate)
                }
                let updatedAt = updateDates.max()
                return KeywordWorkspaceRow(
                    id: "\(selectedStore)|\(normalized)",
                    keyword: representative.keyword,
                    store: selectedStore,
                    popularity: measuredRecords.map(\.popularity).max() ?? 0,
                    hasPopularityData: !measuredRecords.isEmpty,
                    suggestionScore: groupedRecords.compactMap(\.effectiveSuggestionScore).max(),
                    opportunityScore: groupedRecords.map(\.opportunityScore).max() ?? 0,
                    note: note,
                    mainKeyword: groupedRecords.first(where: {
                        $0.source == .appleSearchHints || $0.isAppleAdsSuggestion
                    })?
                        .matchedTerms.first
                        ?? representative.matchedTerms.first
                        ?? project.seedKeywords.first
                        ?? representative.genre,
                    updatedAt: updatedAt,
                    popularityCheckedAt: groupedRecords.compactMap { record in
                        if record.isAppleAdsSuggestion, record.suggestionScore == nil {
                            return nil
                        }
                        return record.popularityCheckedAt
                    }.max(),
                    month: groupedRecords.compactMap(\.month).max(),
                    metrics: metrics
                )
            }
            .sorted {
                if $0.opportunityScore != $1.opportunityScore {
                    return $0.opportunityScore > $1.opportunityScore
                }
                if $0.hasPopularityData != $1.hasPopularityData { return $0.hasPopularityData }
                if $0.popularity != $1.popularity { return $0.popularity > $1.popularity }
                if $0.suggestionScoreSortValue != $1.suggestionScoreSortValue {
                    return $0.suggestionScoreSortValue > $1.suggestionScoreSortValue
                }
                return $0.keyword.localizedCaseInsensitiveCompare($1.keyword) == .orderedAscending
            }
    }

    private func addKeywordsAndFetch(_ keywords: [String]) {
        guard let project = store.project(id: projectID), !selectedStore.isEmpty else { return }
        let requested = stableUniqueKeywords(keywords)
        guard !requested.isEmpty else { return }

        isAddingKeywords = false
        store.addKeywords(requested, store: selectedStore, to: projectID)
        discoveryController.startPopularityLookup(
            project: project,
            keywords: requested,
            target: target(for: selectedStore, in: project),
            store: store
        )
        rankingController.start(
            project: project,
            keywords: requested,
            storeCode: selectedStore,
            store: store
        )
    }

    private func rankingKeywordsNeedingRefresh(
        _ keywords: [String],
        project: ResearchProject,
        storeCode: String
    ) -> [String] {
        let staleBefore = Date().addingTimeInterval(-24 * 60 * 60)
        let latestScans = project.rankingScans.lazy.filter {
            $0.store.caseInsensitiveCompare(storeCode) == .orderedSame
        }.reduce(into: [String: Date]()) { result, scan in
            let key = normalizedKeyword(scan.keyword)
            result[key] = max(result[key] ?? .distantPast, scan.checkedAt)
        }
        return stableUniqueKeywords(keywords).filter {
            (latestScans[normalizedKeyword($0)] ?? .distantPast) < staleBefore
        }
    }

    private func refreshAll(project: ResearchProject, trackedRows: [KeywordWorkspaceRow]) {
        let keywords = trackedRows.map(\.keyword)
        guard !keywords.isEmpty else { return }
        discoveryController.startPopularityLookup(
            project: project,
            keywords: keywords,
            target: target(for: selectedStore, in: project),
            store: store
        )
        rankingController.start(
            project: project,
            keywords: keywords,
            storeCode: selectedStore,
            store: store
        )
    }

    private func backfillMissingMetricsIfNeeded(project: ResearchProject) {
        guard !store.isReadOnly,
              !selectedStore.isEmpty
        else {
            return
        }

        let rows = workspaceRows(project: project, tracked: true)
        let staleBefore = Date().addingTimeInterval(-24 * 60 * 60)
        let missingPopularity = rows.filter {
            !$0.hasPopularityData
                && ($0.popularityCheckedAt == nil || $0.popularityCheckedAt! < staleBefore)
        }.map(\.keyword)
        if !missingPopularity.isEmpty {
            discoveryController.startPopularityLookup(
                project: project,
                keywords: missingPopularity,
                target: target(for: selectedStore, in: project),
                store: store
            )
        }

        let scannedKeywords = Set(project.rankingScans.lazy.filter {
            $0.store.caseInsensitiveCompare(selectedStore) == .orderedSame
        }.map { normalizedKeyword($0.keyword) })
        let missingRankings = rows.filter {
            !scannedKeywords.contains(normalizedKeyword($0.keyword))
        }.map(\.keyword)
        if !missingRankings.isEmpty {
            rankingController.start(
                project: project,
                keywords: missingRankings,
                storeCode: selectedStore,
                store: store,
                prioritize: false
            )
        }
    }

    private func target(for storeCode: String, in project: ResearchProject) -> StoreTarget {
        project.targets.first { $0.store.caseInsensitiveCompare(storeCode) == .orderedSame }
            ?? ResearchPresets.target(for: storeCode)
            ?? StoreTarget(language: "en", store: storeCode)
    }

    private func stableUniqueKeywords(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(normalizedKeyword(trimmed)).inserted else { return nil }
            return trimmed
        }
    }

    private func trackedKeywordCount(for storeCode: String, in project: ResearchProject) -> Int {
        Set(project.keywords.lazy.filter {
            $0.store == storeCode && $0.isActivelyTracked
        }.map { normalizedKeyword($0.keyword) }).count
    }

    private func storeTitle(_ storeCode: String) -> String {
        ResearchPresets.storeTitles[storeCode.lowercased()] ?? storeCode.uppercased()
    }

    private func updateLabel(_ row: KeywordWorkspaceRow) -> String {
        if let date = row.updatedAt {
            if Calendar.current.isDateInToday(date) { return "Today" }
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return row.month ?? "—"
    }

    private func importCSV(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            Task { await store.importKeywords(data, into: projectID) }
        } catch {
            store.showError(title: "CSV Could Not Be Imported", error: error)
        }
    }

    private func normalizedKeyword(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct StoreChooser: View {
    let stores: [String]
    let selectedStore: String
    @Binding var searchText: String
    let trackedCount: (String) -> Int
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Countries", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredStores, id: \.self) { storeCode in
                        Button {
                            onSelect(storeCode)
                        } label: {
                            HStack(spacing: 8) {
                                Text(flagEmoji(for: storeCode))
                                    .font(.title3)
                                Text(storeTitle(storeCode))
                                Spacer()
                                Text(trackedCount(storeCode).formatted())
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 8)
                            .frame(height: 34)
                            .background(
                                selectedStore == storeCode ? Color.accentColor.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(storeTitle(storeCode)), \(trackedCount(storeCode)) keywords")
                    }
                }
                .padding(.trailing, 10)
            }
        }
        .padding(10)
        .frame(width: 280, height: min(CGFloat(filteredStores.count * 36 + 58), 330))
    }

    private var filteredStores: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return stores.filter {
            query.isEmpty
                || storeTitle($0).localizedCaseInsensitiveContains(query)
                || $0.localizedCaseInsensitiveContains(query)
        }
    }

    private func storeTitle(_ storeCode: String) -> String {
        ResearchPresets.storeTitles[storeCode.lowercased()] ?? storeCode.uppercased()
    }
}

private struct KeywordWorkspaceRow: Identifiable {
    let id: String
    let keyword: String
    let store: String
    let popularity: Int
    let hasPopularityData: Bool
    let suggestionScore: Int?
    let opportunityScore: Double
    let note: String?
    let mainKeyword: String
    let updatedAt: Date?
    let popularityCheckedAt: Date?
    let month: String?
    let metrics: KeywordSearchMetrics

    var noteSortValue: String { note ?? "" }
    var updateSortValue: Date { updatedAt ?? .distantPast }
    var popularitySortValue: Int { hasPopularityData ? popularity : -1 }
    var suggestionScoreSortValue: Int { suggestionScore ?? -1 }
    var difficultySortValue: Int { metrics.difficulty ?? -1 }
    var positionSortValue: Int { metrics.focusAppPosition ?? Int.max }
    var rankingAppCount: Int { metrics.topApps.count }
}

private func sortedWorkspaceRows(
    _ rows: [KeywordWorkspaceRow],
    using comparators: [KeyPathComparator<KeywordWorkspaceRow>]
) -> [KeywordWorkspaceRow] {
    let sorted = rows.sorted(using: comparators)
    guard let keyPath = comparators.first?.keyPath else { return sorted }

    let isAvailable: ((KeywordWorkspaceRow) -> Bool)?
    if keyPath == \KeywordWorkspaceRow.popularitySortValue {
        isAvailable = { $0.hasPopularityData }
    } else if keyPath == \KeywordWorkspaceRow.difficultySortValue {
        isAvailable = { $0.metrics.difficulty != nil }
    } else if keyPath == \KeywordWorkspaceRow.positionSortValue {
        isAvailable = { $0.metrics.focusAppPosition != nil }
    } else if keyPath == \KeywordWorkspaceRow.updateSortValue {
        isAvailable = { $0.updatedAt != nil || $0.month != nil }
    } else {
        isAvailable = nil
    }

    guard let isAvailable else { return sorted }
    return sorted.filter(isAvailable) + sorted.filter { !isAvailable($0) }
}

private struct KeywordMetricFilters: Equatable {
    var popularity = MetricRangeFilter()
    var difficulty = MetricRangeFilter()
    var position = MetricRangeFilter()

    var isActive: Bool {
        popularity.isActive || difficulty.isActive || position.isActive
    }

    var activeCount: Int {
        [popularity, difficulty, position].count(where: \.isActive)
    }

    func matches(_ row: KeywordWorkspaceRow) -> Bool {
        popularity.matches(row.hasPopularityData ? row.popularity : nil)
            && difficulty.matches(row.metrics.difficulty)
            && position.matches(row.metrics.focusAppPosition)
    }
}

private struct KeywordNoteEditor: View {
    @FocusState private var isFocused: Bool
    @State private var text: String

    let keyword: String
    let note: String?
    let onCommit: (String) -> Void

    init(keyword: String, note: String?, onCommit: @escaping (String) -> Void) {
        self.keyword = keyword
        self.note = note
        self.onCommit = onCommit
        _text = State(initialValue: note ?? "")
    }

    var body: some View {
        TextField("Add note", text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { wasFocused, isFocused in
                if wasFocused && !isFocused { commit() }
            }
            .onChange(of: note) { _, note in
                if !isFocused { text = note ?? "" }
            }
            .accessibilityLabel("Note for \(keyword)")
    }

    private func commit() {
        guard text != (note ?? "") else { return }
        onCommit(text)
    }
}

private enum MetricKind {
    case popularity
    case difficulty
}

private struct MetricBar: View {
    let value: Int?
    let kind: MetricKind

    var body: some View {
        HStack(spacing: 7) {
            Text(value?.formatted() ?? "—")
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(value == nil ? .tertiary : .primary)
                .frame(width: 30, alignment: .trailing)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    if let value {
                        Capsule()
                            .fill(color(for: value))
                            .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 100)) / 100)
                    }
                }
            }
            .frame(width: 64, height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(value.map { "\($0) out of 100" } ?? unavailableHelp)
    }

    private var unavailableHelp: String {
        switch kind {
        case .popularity: "Apple Ads returned no exact popularity for this term."
        case .difficulty: "Update keyword data to calculate an estimate"
        }
    }

    private func color(for value: Int) -> Color {
        switch kind {
        case .popularity:
            if value >= 65 { return .green }
            if value >= 25 { return .yellow }
            return .red
        case .difficulty:
            if value >= 70 { return .red }
            if value >= 40 { return .yellow }
            return .green
        }
    }
}

private struct RankingAppsCell: View {
    @State private var isShowingDetails = false

    let apps: [RankingObservation]

    var body: some View {
        if apps.isEmpty {
            Text("—")
                .foregroundStyle(.tertiary)
        } else {
            Button {
                isShowingDetails.toggle()
            } label: {
                HStack(spacing: 4) {
                    ForEach(apps.prefix(5)) { app in
                        AppArtwork(app: app)
                    }
                    if apps.count > 5 {
                        Text("+\(apps.count - 5)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Show ranking apps")
            .accessibilityLabel("Show \(apps.count) apps in ranking")
            .popover(isPresented: $isShowingDetails, arrowEdge: .trailing) {
                RankingAppsPopover(apps: apps)
            }
        }
    }
}

private struct RankingAppsPopover: View {
    let apps: [RankingObservation]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Apps in Ranking")
                .font(.headline)
                .padding(12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(apps) { app in
                        HStack(spacing: 9) {
                            Text("#\(app.position)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)

                            AppArtwork(app: app)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.appName)
                                    .lineLimit(1)
                                Text(app.developerName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if let count = app.userRatingCount {
                                Text(count.formatted(.number.notation(.compactName)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            if let url = app.appStoreURL {
                                Link(destination: url) {
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .help("Open in App Store")
                                .accessibilityLabel("Open \(app.appName) in App Store")
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                    }
                }
            }
        }
        .frame(width: 360, height: min(CGFloat(apps.count * 44 + 46), 400))
    }
}

private struct AppArtwork: View {
    let app: RankingObservation

    var body: some View {
        AsyncImage(url: app.artworkURL) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(.quaternary)
                    Image(systemName: "app.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .help("#\(app.position) · \(app.appName)")
        .accessibilityLabel("\(app.appName), API result \(app.position)")
    }
}

private struct MetricFiltersButton: View {
    @State private var isPresented = false

    @Binding var filters: KeywordMetricFilters
    let showsDifficulty: Bool
    let showsPosition: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: visibleFilterCount > 0
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .help(filterHelp)
        .accessibilityLabel(filterHelp)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            MetricFiltersPopover(
                filters: $filters,
                showsDifficulty: showsDifficulty,
                showsPosition: showsPosition
            )
        }
    }

    private var visibleFilterCount: Int {
        var count = filters.popularity.isActive ? 1 : 0
        if showsDifficulty, filters.difficulty.isActive { count += 1 }
        if showsPosition, filters.position.isActive { count += 1 }
        return count
    }

    private var filterHelp: String {
        visibleFilterCount == 0 ? "Filter Metric Ranges" : "Filter Metric Ranges, \(visibleFilterCount) active"
    }
}

private struct MetricFiltersPopover: View {
    @Binding var filters: KeywordMetricFilters
    let showsDifficulty: Bool
    let showsPosition: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Metric Ranges")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    resetVisibleFilters()
                }
                .disabled(visibleFilterCount == 0)
            }

            MetricRangeEditor(
                title: "Popularity",
                range: $filters.popularity,
                allowedValues: 0...100
            )

            if showsDifficulty {
                MetricRangeEditor(
                    title: "Difficulty",
                    range: $filters.difficulty,
                    allowedValues: 0...100
                )
            }

            if showsPosition {
                MetricRangeEditor(
                    title: "Position",
                    range: $filters.position,
                    allowedValues: 1...100
                )
            }
        }
        .padding(12)
        .frame(width: 310)
    }

    private var visibleFilterCount: Int {
        var count = filters.popularity.isActive ? 1 : 0
        if showsDifficulty, filters.difficulty.isActive { count += 1 }
        if showsPosition, filters.position.isActive { count += 1 }
        return count
    }

    private func resetVisibleFilters() {
        filters.popularity = MetricRangeFilter()
        if showsDifficulty { filters.difficulty = MetricRangeFilter() }
        if showsPosition { filters.position = MetricRangeFilter() }
    }
}

private struct MetricRangeEditor: View {
    let title: String
    @Binding var range: MetricRangeFilter
    let allowedValues: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("Include unavailable", isOn: $range.includesUnavailable)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .disabled(!range.isActive)
            }

            HStack(spacing: 7) {
                TextField("Min", text: valueBinding(\.minimum))
                    .accessibilityLabel("Minimum \(title)")
                Text("to")
                    .foregroundStyle(.secondary)
                TextField("Max", text: valueBinding(\.maximum))
                    .accessibilityLabel("Maximum \(title)")
                Text("\(allowedValues.lowerBound)-\(allowedValues.upperBound)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func valueBinding(_ keyPath: WritableKeyPath<MetricRangeFilter, Int?>) -> Binding<String> {
        Binding(
            get: {
                range[keyPath: keyPath].map(String.init) ?? ""
            },
            set: { input in
                let digits = input.filter(\.isNumber)
                guard let value = Int(digits) else {
                    range[keyPath: keyPath] = nil
                    return
                }
                range[keyPath: keyPath] = min(max(value, allowedValues.lowerBound), allowedValues.upperBound)
            }
        )
    }
}

private struct InlineKeywordEntry: View {
    @FocusState private var isFieldFocused: Bool
    @State private var keywordText = ""

    let storeCode: String
    let onCancel: () -> Void
    let onAdd: ([String]) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(flagEmoji(for: storeCode)) \(storeCode.uppercased())")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 18)

            TextField("Keywords separated by commas", text: $keywordText)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .onSubmit(submit)
                .accessibilityLabel("Keywords separated by commas")

            AppCloseButton(
                accessibilityLabel: "Close keyword field",
                help: "Close",
                action: onCancel
            )
        }
        .padding(.horizontal, 11)
        .frame(width: 430, height: 38)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator.opacity(0.8))
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .onAppear { isFieldFocused = true }
        .onExitCommand(perform: onCancel)
    }

    private var parsedKeywords: [String] {
        Array(keywordText.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(100))
    }

    private func submit() {
        guard !parsedKeywords.isEmpty else { return }
        onAdd(parsedKeywords)
    }
}

private struct SuggestionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool
    @State private var selection: Set<String> = []
    @State private var searchText = ""
    @State private var sortOrder = [
        KeyPathComparator(\KeywordWorkspaceRow.suggestionScoreSortValue, order: .reverse),
        KeyPathComparator(\KeywordWorkspaceRow.popularitySortValue, order: .reverse),
    ]
    @State private var metricFilters = KeywordMetricFilters()

    let storeCode: String
    let rows: [KeywordWorkspaceRow]
    let progressText: String?
    let onRefresh: () -> Void
    let onSearchMore: () -> Void
    let onAdd: ([String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AppCloseButton(
                    accessibilityLabel: "Close Suggestions",
                    help: "Close Suggestions",
                    action: dismiss.callAsFunction
                )

                TextField("Filter Suggestions", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)

                MetricFiltersButton(
                    filters: $metricFilters,
                    showsDifficulty: true,
                    showsPosition: false
                )

                if let progressText {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Related Suggestions")
                    .accessibilityLabel("Refresh Related Suggestions")
                }

                Button(action: onSearchMore) {
                    Label("Search More", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(progressText != nil || rows.isEmpty)
                .help("Find another layer of related suggestions")

                Text("\(selection.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button("Add Selected") {
                    let keywords = rows.filter { selection.contains($0.id) }.map(\.keyword)
                    onAdd(keywords)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
            .padding(12)

            Divider()

            ZStack {
                Table(filteredRows, sortOrder: $sortOrder) {
                    TableColumn("Main Keyword", value: \.mainKeyword) { row in
                        Text(row.mainKeyword)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 110, ideal: 140)

                    TableColumn("Suggestion", value: \.keyword)

                    TableColumn("Suggestion Score", value: \.suggestionScoreSortValue) { row in
                        AppleAdsSuggestionScoreCell(value: row.suggestionScore)
                    }
                    .width(112)

                    TableColumn("Popularity", value: \.popularitySortValue) { row in
                        MetricBar(value: row.hasPopularityData ? row.popularity : nil, kind: .popularity)
                    }
                    .width(112)

                    TableColumn("Difficulty", value: \.difficultySortValue) { row in
                        MetricBar(value: row.metrics.difficulty, kind: .difficulty)
                            .help("Estimated from rating volume in the first iTunes Search API results")
                    }
                    .width(112)

                    TableColumn("Select") { row in
                        Toggle("", isOn: selectionBinding(for: row.id))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityLabel("Select \(row.keyword)")
                    }
                    .width(52)
                }
                .alternatingRowBackgrounds(.enabled)

                if filteredRows.isEmpty {
                    ContentUnavailableView {
                        Label(
                            progressText == nil ? "No Related Suggestions" : "Finding Suggestions",
                            systemImage: progressText == nil ? "text.magnifyingglass" : "arrow.trianglehead.2.clockwise.rotate.90"
                        )
                    } description: {
                        Text(progressText ?? "No Apple search hints matched this project's context.")
                    }
                }
            }

            Divider()

            HStack {
                Text("\(filteredRows.count) suggestions for \(flagEmoji(for: storeCode)) \(storeCode.uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Select All") {
                    selection.formUnion(filteredRows.map(\.id))
                }
                .disabled(filteredRows.isEmpty)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
        }
        .frame(width: 980, height: 460)
        .task {
            await Task.yield()
            isSearchFocused = true
        }
        .onExitCommand { dismiss() }
    }

    private var filteredRows: [KeywordWorkspaceRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = rows.filter {
            (query.isEmpty
                || $0.keyword.localizedCaseInsensitiveContains(query)
                || $0.mainKeyword.localizedCaseInsensitiveContains(query))
                && metricFilters.matches($0)
        }
        return sortedWorkspaceRows(filtered, using: sortOrder)
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isSelected in
                if isSelected { selection.insert(id) } else { selection.remove(id) }
            }
        )
    }
}

private func flagEmoji(for countryCode: String) -> String {
    let base: UInt32 = 127_397
    let scalars = countryCode.uppercased().unicodeScalars.compactMap {
        UnicodeScalar(base + $0.value)
    }
    return String(String.UnicodeScalarView(scalars))
}
