import ReadRevsCore
import Foundation

enum SidebarSelection: Hashable {
    case project(UUID)
    case app(Int64)
}

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ObservedKeywordRow: Identifiable {
    let projectName: String
    let observation: RankingObservation

    var id: String { "\(projectName)|\(observation.id)" }
}

struct SearchPresenceRow: Identifiable {
    let projectID: UUID
    let keyword: String
    let language: String
    let store: String
    let source: KeywordSource?
    let suggestionScore: Int?
    let popularity: Int?
    let difficulty: Int?
    let focusAppPosition: Int?
    let resultCount: Int?
    let topApps: [RankingObservation]
    let checkedAt: Date?

    var id: String {
        "\(projectID.uuidString)|\(normalizedSearchPresenceKeyword(keyword))|\(store.lowercased())"
    }
}

struct SearchPresenceSummary {
    let projectID: UUID
    let store: String
    let keywordCount: Int
    let checkedKeywordCount: Int
    let rankedKeywordCount: Int
    let notRankedKeywordCount: Int
    let bestPosition: Int?
    let averagePosition: Double?
    let lastCheckedAt: Date?
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var library: ASOLibrary
    @Published private(set) var isReadOnly = false
    @Published var selection: SidebarSelection?
    @Published var presentedError: PresentedError?

    private let writer: LibraryWriter
    private var saveRevision = 0
    private var saveTask: Task<Void, Never>?

    init(
        persistence: LibraryPersistence,
        importedLibrary: ASOLibrary? = nil,
        legacySavedAppsData: Data? = nil,
        legacySelectedAppID: Int64? = nil,
        migrationDate: Date = Date(),
        migrationWarning: PresentedError? = nil
    ) {
        writer = LibraryWriter(persistence: persistence)
        presentedError = migrationWarning
        let currentLibrary: ASOLibrary
        do {
            currentLibrary = try persistence.load()
        } catch {
            library = ASOLibrary()
            isReadOnly = true
            presentedError = PresentedError(title: "Library Could Not Be Opened", message: error.localizedDescription)
            return
        }

        let currentLibraryWasEmpty = currentLibrary.apps.isEmpty && currentLibrary.projects.isEmpty
        var migratedLibrary = currentLibrary
        if let importedLibrary {
            migratedLibrary = Self.merge(importedLibrary: importedLibrary, into: migratedLibrary)
        }

        if let legacySavedAppsData {
            do {
                let migrated = try LegacyReadRevsLibraryImporter.merge(
                    savedAppsData: legacySavedAppsData,
                    into: migratedLibrary,
                    importedAt: migrationDate
                )
                library = migrated
                if migrated != currentLibrary {
                    try persistence.save(migrated)
                }
            } catch {
                library = migratedLibrary
                presentedError = PresentedError(
                    title: "ReadRevs Data Could Not Be Imported",
                    message: error.localizedDescription
                )
            }
        } else {
            library = migratedLibrary
            if migratedLibrary != currentLibrary {
                do {
                    try persistence.save(migratedLibrary)
                } catch {
                    isReadOnly = true
                    presentedError = PresentedError(
                        title: "ReadRevs Data Could Not Be Imported",
                        message: error.localizedDescription
                    )
                }
            }
        }

        if currentLibraryWasEmpty,
           let legacySelectedAppID,
           library.apps.contains(where: { $0.adamID == legacySelectedAppID }) {
            selection = .app(legacySelectedAppID)
        } else if let project = sidebarProjects.first {
            selection = .project(project.id)
        } else if let app = library.apps.first {
            selection = .app(app.adamID)
        }
    }

    static func makeDefault() -> LibraryStore {
        let environment = ProcessInfo.processInfo.environment
        if let overridePath = environment["READREVS_LIBRARY_PATH"]
            ?? environment["ASO_RESEARCH_LIBRARY_PATH"],
           !overridePath.isEmpty {
            return LibraryStore(persistence: LibraryPersistence(fileURL: URL(fileURLWithPath: overridePath)))
        }

        let readRevsDefaults = ReadRevsMigration.readRevsDefaults()
        if let asoResearchDefaults = ReadRevsMigration.asoResearchDefaults() {
            ReadRevsMigration.copyPreferences(from: asoResearchDefaults, to: .standard)
        }
        var migrationIssues: [String] = []
        do {
            try ReadRevsMigration.migrateHistory()
        } catch {
            migrationIssues.append("Research history: \(error.localizedDescription)")
        }

        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/ReadRevs/library.json")
        let fileURL = (try? LibraryPersistence.defaultFileURL()) ?? fallback
        let asoResearchLibraryURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/ASO Research/library.json")
        let importedLibrary: ASOLibrary?
        do {
            importedLibrary = try LibraryPersistence(fileURL: asoResearchLibraryURL).load()
        } catch {
            importedLibrary = nil
            migrationIssues.append("Pre-release library: \(error.localizedDescription)")
        }
        let migrationWarning = migrationIssues.isEmpty ? nil : PresentedError(
            title: "Some Previous Data Could Not Be Imported",
            message: migrationIssues.joined(separator: "\n")
        )
        return LibraryStore(
            persistence: LibraryPersistence(fileURL: fileURL),
            importedLibrary: importedLibrary,
            legacySavedAppsData: readRevsDefaults?.data(forKey: ReadRevsMigration.savedAppsKey),
            legacySelectedAppID: (
                readRevsDefaults?.object(forKey: ReadRevsMigration.selectedAppIDKey)
                    as? NSNumber
            )?.int64Value,
            migrationWarning: migrationWarning
        )
    }

    private static func merge(importedLibrary: ASOLibrary, into currentLibrary: ASOLibrary) -> ASOLibrary {
        var merged = currentLibrary
        var projectIDs = Set(merged.projects.map(\.id))
        merged.projects.append(contentsOf: importedLibrary.projects.filter {
            projectIDs.insert($0.id).inserted
        })

        var appIDs = Set(merged.apps.map(\.adamID))
        merged.apps.append(contentsOf: importedLibrary.apps.filter {
            appIDs.insert($0.adamID).inserted
        })

        merged.projects.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        merged.apps.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return merged
    }

    func project(id: UUID) -> ResearchProject? {
        library.projects.first { $0.id == id }
    }

    var sidebarProjects: [ResearchProject] {
        library.projects.filter { $0.kind == .manual }
    }

    func app(adamID: Int64) -> TrackedApp? {
        library.apps.first { $0.adamID == adamID }
    }

    func removeApp(adamID: Int64) {
        guard !isReadOnly,
              let appIndex = library.apps.firstIndex(where: { $0.adamID == adamID })
        else {
            return
        }

        let wasSelected = selection == .app(adamID)
        library.apps.remove(at: appIndex)

        let now = Date()
        for projectIndex in library.projects.indices
        where library.projects[projectIndex].focusAppAdamID == adamID
            && library.projects[projectIndex].kind == .manual {
            library.projects[projectIndex].focusAppAdamID = nil
            library.projects[projectIndex].updatedAt = now
        }

        if wasSelected {
            if !library.apps.isEmpty {
                let nextIndex = min(appIndex, library.apps.count - 1)
                selection = .app(library.apps[nextIndex].adamID)
            } else {
                selection = sidebarProjects.first.map { .project($0.id) }
            }
        }
        persist()
    }

    func removeProject(id: UUID) {
        guard !isReadOnly,
              let projectIndex = library.projects.firstIndex(where: { $0.id == id })
        else {
            return
        }

        let wasSelected = selection == .project(id)
        let sidebarIndex = sidebarProjects.firstIndex { $0.id == id }
        library.projects.remove(at: projectIndex)

        if wasSelected {
            let remainingProjects = sidebarProjects
            if !remainingProjects.isEmpty {
                let nextIndex = min(sidebarIndex ?? 0, remainingProjects.count - 1)
                selection = .project(remainingProjects[nextIndex].id)
            } else {
                selection = library.apps.first.map { .app($0.adamID) }
            }
        }
        persist()
    }

    @discardableResult
    func createProject(
        name: String,
        topic: String,
        targets: [StoreTarget],
        genres: [String],
        seedKeywords: [String]
    ) -> UUID? {
        guard !isReadOnly else { return nil }
        let project = ResearchProject(
            name: name,
            topic: topic,
            targets: targets,
            genres: genres,
            seedKeywords: seedKeywords
        )
        library.projects.append(project)
        library.projects.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selection = .project(project.id)
        persist()
        return project.id
    }

    func addApp(_ result: StoreAppSearchResult, store: String, kind: TrackedAppKind) {
        guard !isReadOnly else { return }
        let record = TrackedApp(
            adamID: result.adamID,
            name: result.name,
            developerName: result.developerName,
            bundleID: result.bundleID,
            primaryStore: store,
            primaryGenre: result.primaryGenre,
            appStoreURL: result.appStoreURL,
            artworkURL: result.artworkURL,
            version: result.version,
            releaseDate: result.releaseDate,
            currentVersionReleaseDate: result.currentVersionReleaseDate,
            averageRating: result.averageRating,
            ratingCount: result.userRatingCount,
            kind: kind
        )

        if let index = library.apps.firstIndex(where: { $0.adamID == result.adamID }) {
            var existing = library.apps[index].updatingMetadata(from: result)
            if kind == .owned { existing.kind = .owned }
            library.apps[index] = existing
        } else {
            library.apps.append(record)
        }
        sortApps()
        selection = .app(result.adamID)
        persist()

        if kind == .owned, let trackedApp = app(adamID: result.adamID) {
            ensureAppSearchPresenceProject(for: trackedApp)
        }
    }

    func appSearchPresenceProject(for focusAppAdamID: Int64) -> ResearchProject? {
        library.projects.first {
            $0.kind == .appSearchPresence && $0.focusAppAdamID == focusAppAdamID
        }
    }

    @discardableResult
    func ensureAppSearchPresenceProject(
        for app: TrackedApp,
        now: Date = Date()
    ) -> ResearchProject? {
        let target = ResearchPresets.target(for: app.primaryStore)
            ?? StoreTarget(language: "en", store: app.primaryStore)
        let name = "\(app.name) Search Presence"
        let topic = app.primaryGenre.trimmingCharacters(in: .whitespacesAndNewlines)
        let genres = topic.isEmpty ? [] : [topic]
        let seeds = appSearchPresenceSeeds(for: app)

        if let index = library.projects.firstIndex(where: {
            $0.kind == .appSearchPresence && $0.focusAppAdamID == app.adamID
        }) {
            guard !isReadOnly else { return library.projects[index] }
            var project = library.projects[index]
            let researchContextChanged = project.targets != [target]
                || project.genres != genres
                || project.seedKeywords != seeds
            let needsUpdate = project.name != name
                || project.topic != topic
                || researchContextChanged
                || project.focusAppAdamID != app.adamID
                || project.kind != .appSearchPresence
            guard needsUpdate else { return project }

            project.name = name
            project.topic = topic
            project.targets = [target]
            project.genres = genres
            project.seedKeywords = seeds
            project.focusAppAdamID = app.adamID
            project.kind = .appSearchPresence
            if researchContextChanged {
                project.keywords = []
                project.rankingObservations = []
                project.rankingScans = []
            }
            project.updatedAt = now
            library.projects[index] = project
            persist()
            return project
        }

        guard !isReadOnly else { return nil }
        let project = ResearchProject(
            name: name,
            topic: topic,
            targets: [target],
            genres: genres,
            seedKeywords: seeds,
            focusAppAdamID: app.adamID,
            kind: .appSearchPresence,
            createdAt: now,
            updatedAt: now
        )
        library.projects.append(project)
        persist()
        return project
    }

    func updateAppMetadata(_ result: StoreAppSearchResult) {
        guard !isReadOnly,
              let index = library.apps.firstIndex(where: { $0.adamID == result.adamID })
        else {
            return
        }

        let updatedApp = library.apps[index].updatingMetadata(from: result)
        library.apps[index] = updatedApp
        sortApps()
        persist(debounced: true)

        if updatedApp.kind == .owned {
            ensureAppSearchPresenceProject(for: updatedApp)
        }
    }

    func addCompetitor(_ summary: AppRankingSummary, store: String) {
        addApp(
            StoreAppSearchResult(
                adamID: summary.adamID,
                name: summary.name,
                developerName: summary.developerName,
                bundleID: summary.bundleID,
                primaryGenre: summary.primaryGenre,
                appStoreURL: summary.appStoreURL,
                position: summary.bestPosition,
                artworkURL: summary.artworkURL
            ),
            store: store,
            kind: .competitor
        )
    }

    func mergeKeywords(_ records: [KeywordRecord], into projectID: UUID) {
        guard !isReadOnly,
              let index = library.projects.firstIndex(where: { $0.id == projectID })
        else {
            return
        }
        library.projects[index].keywords = KeywordRecord.merge(
            existing: library.projects[index].keywords,
            incoming: records
        )
        library.projects[index].updatedAt = Date()
        persist(debounced: true)
    }

    func replaceSuggestions(
        _ records: [KeywordRecord],
        target: StoreTarget,
        genre: String,
        into projectID: UUID
    ) {
        guard !isReadOnly,
              let index = library.projects.firstIndex(where: { $0.id == projectID })
        else {
            return
        }

        let storeCode = target.store.lowercased()
        let language = target.language.lowercased()
        let normalizedGenre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        let retained = library.projects[index].keywords.filter { record in
            let isReplaceableDiscoveryRecord = record.source == .legacyPopularity
                || record.intentTags.contains("apple-ads-popularity")
            guard isReplaceableDiscoveryRecord,
                  !record.isActivelyTracked,
                  record.store == storeCode,
                  record.language == language
            else {
                return true
            }
            return record.genre.caseInsensitiveCompare(normalizedGenre) != .orderedSame
        }

        library.projects[index].keywords = KeywordRecord.merge(existing: retained, incoming: records)
        library.projects[index].updatedAt = Date()
        persist(debounced: true)
    }

    func replaceRelatedSuggestions(
        _ records: [KeywordRecord],
        target: StoreTarget,
        into projectID: UUID
    ) {
        guard !isReadOnly,
              let index = library.projects.firstIndex(where: { $0.id == projectID })
        else {
            return
        }

        let retained = library.projects[index].keywords.filter { record in
            let isRelatedSuggestion = record.source == .appleSearchHints
                || record.isAppleAdsSuggestion
            return !isRelatedSuggestion
                || record.store != target.store
                || record.language != target.language
        }
        library.projects[index].keywords = KeywordRecord.merge(existing: retained, incoming: records)
        library.projects[index].updatedAt = Date()
        persist(debounced: true)
    }

    func retainSearchPresenceCandidates(
        _ keywords: [String],
        target: StoreTarget,
        in projectID: UUID
    ) {
        guard !isReadOnly,
              let index = library.projects.firstIndex(where: { $0.id == projectID }),
              library.projects[index].kind == .appSearchPresence
        else {
            return
        }

        let retainedKeys = Set(keywords.map(normalizedSearchPresenceKeyword))
        var project = library.projects[index]
        let originalCounts = (
            project.keywords.count,
            project.rankingScans.count,
            project.rankingObservations.count
        )
        project.keywords.removeAll { record in
            record.store.caseInsensitiveCompare(target.store) == .orderedSame
                && record.language.caseInsensitiveCompare(target.language) == .orderedSame
                && !retainedKeys.contains(normalizedSearchPresenceKeyword(record.keyword))
        }
        project.rankingScans.removeAll { scan in
            scan.store.caseInsensitiveCompare(target.store) == .orderedSame
                && !retainedKeys.contains(normalizedSearchPresenceKeyword(scan.keyword))
        }
        project.rankingObservations.removeAll { observation in
            observation.store.caseInsensitiveCompare(target.store) == .orderedSame
                && !retainedKeys.contains(normalizedSearchPresenceKeyword(observation.keyword))
        }
        guard originalCounts != (
            project.keywords.count,
            project.rankingScans.count,
            project.rankingObservations.count
        ) else {
            return
        }
        project.updatedAt = Date()
        library.projects[index] = project
        persist(debounced: true)
    }

    func addKeywords(_ words: [String], store storeCode: String, to projectID: UUID) {
        guard !isReadOnly,
              let projectIndex = library.projects.firstIndex(where: { $0.id == projectID })
        else {
            return
        }

        let uniqueWords = Dictionary(grouping: words) { normalizedKeyword($0) }
            .compactMap { key, values in key.isEmpty ? nil : values.first }
        guard !uniqueWords.isEmpty else { return }

        let normalizedStore = storeCode.lowercased()
        let now = Date()
        var missing: [String] = []
        for word in uniqueWords {
            let normalizedWord = normalizedKeyword(word)
            var found = false
            for keywordIndex in library.projects[projectIndex].keywords.indices {
                let record = library.projects[projectIndex].keywords[keywordIndex]
                guard record.store == normalizedStore,
                      normalizedKeyword(record.keyword) == normalizedWord
                else {
                    continue
                }
                library.projects[projectIndex].keywords[keywordIndex].isTracked = true
                library.projects[projectIndex].keywords[keywordIndex].updatedAt = now
                found = true
            }
            if !found { missing.append(word) }
        }

        if !missing.isEmpty {
            let project = library.projects[projectIndex]
            let language = project.targets.first(where: { $0.store == normalizedStore })?.language
                ?? ResearchPresets.target(for: normalizedStore)?.language
                ?? "en"
            let genre = project.genres.first ?? "All"
            let records = missing.map {
                KeywordRecord(
                    keyword: $0,
                    language: language,
                    store: normalizedStore,
                    genre: genre,
                    popularity: 0,
                    source: .manual,
                    isTracked: true,
                    updatedAt: now
                )
            }
            let enriched = KeywordResearchScorer.enrich(
                records,
                topic: project.topic,
                seedKeywords: project.seedKeywords
            )
            library.projects[projectIndex].keywords = KeywordRecord.merge(
                existing: library.projects[projectIndex].keywords,
                incoming: enriched
            )
        }

        library.projects[projectIndex].updatedAt = now
        persist()
    }

    func markPopularityChecked(
        keywords: [String],
        store storeCode: String,
        projectID: UUID,
        checkedAt: Date = Date()
    ) {
        guard !isReadOnly,
              let projectIndex = library.projects.firstIndex(where: { $0.id == projectID })
        else {
            return
        }

        let normalizedWords = Set(keywords.map(normalizedKeyword).filter { !$0.isEmpty })
        let normalizedStore = storeCode.lowercased()
        guard !normalizedWords.isEmpty else { return }

        var didChange = false
        for keywordIndex in library.projects[projectIndex].keywords.indices {
            var record = library.projects[projectIndex].keywords[keywordIndex]
            guard record.store == normalizedStore,
                  normalizedWords.contains(normalizedKeyword(record.keyword))
            else {
                continue
            }
            if record.isAppleAdsSuggestion, record.suggestionScore == nil {
                record.suggestionScore = record.popularity
                record.popularity = 0
            }
            record.popularityCheckedAt = checkedAt
            library.projects[projectIndex].keywords[keywordIndex] = record
            didChange = true
        }
        guard didChange else { return }
        library.projects[projectIndex].updatedAt = checkedAt
        persist(debounced: true)
    }

    func setFocusApp(_ adamID: Int64?, for projectID: UUID) {
        guard !isReadOnly,
              let projectIndex = library.projects.firstIndex(where: { $0.id == projectID })
        else {
            return
        }
        library.projects[projectIndex].focusAppAdamID = adamID
        library.projects[projectIndex].updatedAt = Date()
        persist()
    }

    func toggleFavorite(keyword: String, store storeCode: String, projectID: UUID) {
        guard !isReadOnly,
              let projectIndex = library.projects.firstIndex(where: { $0.id == projectID })
        else {
            return
        }
        let normalizedWord = normalizedKeyword(keyword)
        let normalizedStore = storeCode.lowercased()
        let matchingIndices = library.projects[projectIndex].keywords.indices.filter { index in
            let record = library.projects[projectIndex].keywords[index]
            return record.store == normalizedStore && normalizedKeyword(record.keyword) == normalizedWord
        }
        guard !matchingIndices.isEmpty else { return }
        let newValue = !matchingIndices.contains { library.projects[projectIndex].keywords[$0].isFavorite }
        for index in matchingIndices {
            library.projects[projectIndex].keywords[index].isFavorite = newValue
        }
        library.projects[projectIndex].updatedAt = Date()
        persist()
    }

    func setNote(_ note: String, keyword: String, store storeCode: String, projectID: UUID) {
        guard !isReadOnly,
              let projectIndex = library.projects.firstIndex(where: { $0.id == projectID })
        else {
            return
        }
        let normalizedWord = normalizedKeyword(keyword)
        let normalizedStore = storeCode.lowercased()
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingIndices = library.projects[projectIndex].keywords.indices.filter { index in
            let record = library.projects[projectIndex].keywords[index]
            return record.store == normalizedStore && normalizedKeyword(record.keyword) == normalizedWord
        }
        guard !matchingIndices.isEmpty else { return }
        for index in matchingIndices {
            library.projects[projectIndex].keywords[index].note = cleanedNote.isEmpty ? nil : cleanedNote
        }
        library.projects[projectIndex].updatedAt = Date()
        persist(debounced: true)
    }

    func stopTracking(keyword: String, store storeCode: String, projectID: UUID) {
        guard !isReadOnly,
              let projectIndex = library.projects.firstIndex(where: { $0.id == projectID })
        else {
            return
        }
        let normalizedWord = normalizedKeyword(keyword)
        let normalizedStore = storeCode.lowercased()
        let matchingIndices = library.projects[projectIndex].keywords.indices.filter { index in
            let record = library.projects[projectIndex].keywords[index]
            return record.store == normalizedStore && normalizedKeyword(record.keyword) == normalizedWord
        }
        guard !matchingIndices.isEmpty else { return }
        for index in matchingIndices {
            library.projects[projectIndex].keywords[index].isTracked = false
        }
        library.projects[projectIndex].updatedAt = Date()
        persist()
    }

    func importKeywords(_ data: Data, into projectID: UUID) async {
        guard !isReadOnly else { return }
        do {
            let records = try await Task.detached(priority: .userInitiated) {
                try KeywordCSVImporter().parse(data)
            }.value
            mergeKeywords(records, into: projectID)
        } catch {
            showError(title: "CSV Could Not Be Imported", error: error)
        }
    }

    func toggleFavorite(keywordID: String, projectID: UUID) {
        guard !isReadOnly,
              let projectIndex = library.projects.firstIndex(where: { $0.id == projectID }),
              let keywordIndex = library.projects[projectIndex].keywords.firstIndex(where: { $0.id == keywordID })
        else {
            return
        }
        library.projects[projectIndex].keywords[keywordIndex].isFavorite.toggle()
        library.projects[projectIndex].updatedAt = Date()
        persist()
    }

    func mergeRankingData(
        observations: [RankingObservation],
        scan: RankingScan,
        into projectID: UUID
    ) {
        guard !isReadOnly,
              let index = library.projects.firstIndex(where: { $0.id == projectID })
        else {
            return
        }
        if let currentScan = library.projects[index].rankingScans.first(where: { $0.id == scan.id }),
           currentScan.checkedAt > scan.checkedAt {
            return
        }
        library.projects[index].rankingObservations = RankingIndex.replacing(
            existing: library.projects[index].rankingObservations,
            with: observations,
            for: scan
        )
        library.projects[index].rankingScans = RankingIndex.mergeScans(
            existing: library.projects[index].rankingScans,
            incoming: [scan]
        )
        library.projects[index].updatedAt = Date()
        persist(debounced: true)
    }

    func observedKeywords(for adamID: Int64) -> [ObservedKeywordRow] {
        library.projects.flatMap { project in
            RankingIndex.keywords(for: adamID, in: project.rankingObservations).map {
                ObservedKeywordRow(projectName: project.name, observation: $0)
            }
        }.sorted {
            if $0.observation.position != $1.observation.position {
                return $0.observation.position < $1.observation.position
            }
            return $0.observation.keyword.localizedCaseInsensitiveCompare($1.observation.keyword) == .orderedAscending
        }
    }

    func searchPresenceRows(
        for adamID: Int64,
        store storeCode: String? = nil
    ) -> [SearchPresenceRow] {
        guard let project = appSearchPresenceProject(for: adamID) else { return [] }
        let normalizedStore = (storeCode ?? project.targets.first?.store ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedStore.isEmpty else { return [] }

        let records = project.keywords.filter {
            $0.store.caseInsensitiveCompare(normalizedStore) == .orderedSame
        }
        let scans = project.rankingScans.filter {
            $0.store.caseInsensitiveCompare(normalizedStore) == .orderedSame
        }
        let observations = project.rankingObservations.filter {
            $0.store.caseInsensitiveCompare(normalizedStore) == .orderedSame
        }

        var displayTermByKey: [String: String] = [:]
        var recordsByKey: [String: [KeywordRecord]] = [:]
        var latestScanByKey: [String: RankingScan] = [:]

        for record in records {
            let key = normalizedKeyword(record.keyword)
            guard !key.isEmpty else { continue }
            displayTermByKey[key] = displayTermByKey[key] ?? record.keyword
            recordsByKey[key, default: []].append(record)
        }
        for scan in scans {
            let key = normalizedKeyword(scan.keyword)
            guard !key.isEmpty else { continue }
            displayTermByKey[key] = displayTermByKey[key] ?? scan.keyword
            if latestScanByKey[key]?.checkedAt ?? .distantPast < scan.checkedAt {
                latestScanByKey[key] = scan
            }
        }
        for observation in observations {
            let key = normalizedKeyword(observation.keyword)
            guard !key.isEmpty else { continue }
            displayTermByKey[key] = displayTermByKey[key] ?? observation.keyword
        }

        let fallbackLanguage = project.targets.first {
            $0.store.caseInsensitiveCompare(normalizedStore) == .orderedSame
        }?.language ?? "en"

        return displayTermByKey.map { key, keyword in
            let matchingRecords = recordsByKey[key] ?? []
            let measuredRecord = matchingRecords
                .filter(\.hasPopularityMeasurement)
                .max { lhs, rhs in
                    let lhsDate = lhs.popularityCheckedAt ?? lhs.updatedAt ?? .distantPast
                    let rhsDate = rhs.popularityCheckedAt ?? rhs.updatedAt ?? .distantPast
                    return lhsDate < rhsDate
                }
            let representative = matchingRecords.first { $0.source == .appleSearchHints }
                ?? measuredRecord
                ?? matchingRecords.first
            let suggestionScore = matchingRecords.compactMap(\.effectiveSuggestionScore).max()
            let metrics = RankingIndex.searchMetrics(
                keyword: keyword,
                store: normalizedStore,
                focusAppAdamID: adamID,
                observations: observations
            )
            let scan = latestScanByKey[key]

            return SearchPresenceRow(
                projectID: project.id,
                keyword: keyword,
                language: representative?.language ?? fallbackLanguage,
                store: normalizedStore,
                source: representative?.source,
                suggestionScore: suggestionScore,
                popularity: measuredRecord?.popularity,
                difficulty: metrics.difficulty,
                focusAppPosition: metrics.focusAppPosition,
                resultCount: scan?.resultCount,
                topApps: metrics.topApps,
                checkedAt: scan?.checkedAt
            )
        }.sorted {
            $0.keyword.localizedCaseInsensitiveCompare($1.keyword) == .orderedAscending
        }
    }

    func searchPresenceSummary(
        for adamID: Int64,
        store storeCode: String? = nil
    ) -> SearchPresenceSummary? {
        guard let project = appSearchPresenceProject(for: adamID) else { return nil }
        let normalizedStore = (storeCode ?? project.targets.first?.store ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedStore.isEmpty else { return nil }

        let rows = searchPresenceRows(for: adamID, store: normalizedStore)
        let checkedRows = rows.filter { $0.checkedAt != nil }
        let positions = checkedRows.compactMap(\.focusAppPosition)
        return SearchPresenceSummary(
            projectID: project.id,
            store: normalizedStore,
            keywordCount: rows.count,
            checkedKeywordCount: checkedRows.count,
            rankedKeywordCount: positions.count,
            notRankedKeywordCount: checkedRows.filter { $0.focusAppPosition == nil }.count,
            bestPosition: positions.min(),
            averagePosition: positions.isEmpty
                ? nil
                : Double(positions.reduce(0, +)) / Double(positions.count),
            lastCheckedAt: rows.compactMap(\.checkedAt).max()
        )
    }

    func showError(title: String, error: Error) {
        presentedError = PresentedError(title: title, message: error.localizedDescription)
    }

    private func persist(debounced: Bool = false) {
        guard !isReadOnly else { return }
        saveTask?.cancel()
        saveRevision += 1
        let revision = saveRevision
        let snapshot = library
        let writer = writer

        saveTask = Task { [weak self, writer] in
            do {
                if debounced {
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                try Task.checkCancellation()
                try await writer.save(snapshot, revision: revision)
            } catch is CancellationError {
                return
            } catch {
                self?.showError(title: "Changes Could Not Be Saved", error: error)
            }
        }
    }

    private func sortApps() {
        library.apps.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .owned }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func normalizedKeyword(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func appSearchPresenceSeeds(for app: TrackedApp) -> [String] {
        let titleDelimiters = CharacterSet(charactersIn: ":-|")
            .union(CharacterSet(charactersIn: "\u{2013}\u{2014}"))
        let titleSegments = app.name.components(separatedBy: titleDelimiters)
        let shortName = titleSegments.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let descriptor = titleSegments.dropFirst().joined(separator: " ")
        let ignoredWords: Set<String> = ["and", "app", "for", "the", "with"]
        let descriptorWords = descriptor
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count >= 2 && !ignoredWords.contains(word.lowercased())
            }
        let descriptorPhrase = descriptorWords.joined(separator: " ")
        let candidates = [app.name, shortName, descriptorPhrase]
            + descriptorWords
            + [app.primaryGenre]
        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = normalizedKeyword(trimmed)
            guard !trimmed.isEmpty, seen.insert(normalized).inserted else { return nil }
            return trimmed
        }
    }
}

private actor LibraryWriter {
    private let persistence: LibraryPersistence
    private var highestSeenRevision = 0

    init(persistence: LibraryPersistence) {
        self.persistence = persistence
    }

    func save(_ library: ASOLibrary, revision: Int) throws {
        guard revision > highestSeenRevision else { return }
        try persistence.save(library)
        highestSeenRevision = revision
    }
}

private func normalizedSearchPresenceKeyword(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}
