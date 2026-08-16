import ReadRevsCore
import Foundation
import SwiftUI

@MainActor
protocol AppSearchPresenceRankingScanning: AnyObject {
    var isRunning: Bool { get }
    var completed: Int { get }
    var total: Int { get }
    var failureCount: Int { get }
    var statusText: String? { get }

    func start(
        project: ResearchProject,
        keywords: [String],
        storeCode: String,
        store: LibraryStore,
        prioritize: Bool
    )
    func cancel()
}

extension RankingScanController: AppSearchPresenceRankingScanning {}

@MainActor
final class AppSearchPresenceController: ObservableObject {
    static let defaultMaximumKeywordCount = 50
    static let defaultSearchMoreBatchSize = 50
    static let defaultMaximumExpandedKeywordCount = 200
    static let defaultFreshnessTTL: TimeInterval = 24 * 60 * 60

    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var failureCount = 0
    @Published private(set) var statusText: String?

    private let hintsProvider: any AppStoreSearchHintsProviding
    private let appleAdsClient: any AppleAdsPlatformProviding
    private let appleAdsCredentialStore: any AppleAdsCredentialStoring
    private let rankingScanner: any AppSearchPresenceRankingScanning
    private let maximumKeywordCount: Int
    private let searchMoreBatchSize: Int
    private let maximumExpandedKeywordCount: Int
    private let freshnessTTL: TimeInterval
    private let now: () -> Date
    private var task: Task<Void, Never>?
    private var runID = UUID()
    private var appleAdsSuggestionFailure: String?
    private var popularityStatusDetail: String?
    private var usedExpansionSeedsByScope: [String: Set<String>] = [:]

    init(
        hintsProvider: any AppStoreSearchHintsProviding = AppStoreSearchHintsClient(),
        appleAdsClient: any AppleAdsPlatformProviding = AppleAdsPlatformClient.shared,
        appleAdsCredentialStore: any AppleAdsCredentialStoring = KeychainAppleAdsCredentialStore(),
        rankingScanner: any AppSearchPresenceRankingScanning = RankingScanController(),
        maximumKeywordCount: Int = AppSearchPresenceController.defaultMaximumKeywordCount,
        searchMoreBatchSize: Int = AppSearchPresenceController.defaultSearchMoreBatchSize,
        maximumExpandedKeywordCount: Int = AppSearchPresenceController.defaultMaximumExpandedKeywordCount,
        freshnessTTL: TimeInterval = AppSearchPresenceController.defaultFreshnessTTL,
        now: @escaping () -> Date = Date.init
    ) {
        self.hintsProvider = hintsProvider
        self.appleAdsClient = appleAdsClient
        self.appleAdsCredentialStore = appleAdsCredentialStore
        self.rankingScanner = rankingScanner
        let initialLimit = min(max(maximumKeywordCount, 1), 100)
        self.maximumKeywordCount = initialLimit
        self.searchMoreBatchSize = min(max(searchMoreBatchSize, 1), 100)
        self.maximumExpandedKeywordCount = min(
            max(maximumExpandedKeywordCount, initialLimit),
            500
        )
        self.freshnessTTL = max(freshnessTTL, 0)
        self.now = now
    }

    func refresh(app: TrackedApp, store: LibraryStore, force: Bool = false) {
        cancel()
        guard app.kind == .owned else {
            statusText = "Automatic search presence is available for owned apps."
            return
        }
        guard let project = store.ensureAppSearchPresenceProject(for: app),
              let target = project.targets.first
        else {
            statusText = store.isReadOnly
                ? "Search presence cannot be updated while the library is read-only."
                : "Search presence could not be prepared."
            return
        }

        if force {
            usedExpansionSeedsByScope[expansionScopeKey(project: project, target: target)] = []
        }

        let currentRunID = UUID()
        runID = currentRunID
        isRunning = true
        completed = 0
        total = 0
        failureCount = 0
        appleAdsSuggestionFailure = nil
        popularityStatusDetail = nil
        statusText = "Finding relevant search terms..."

        task = Task { [weak self] in
            guard let self else { return }
            await run(
                project: project,
                target: target,
                store: store,
                force: force,
                runID: currentRunID
            )
        }
    }

    func searchMore(app: TrackedApp, store: LibraryStore) {
        cancel()
        guard app.kind == .owned else {
            statusText = "Automatic search presence is available for owned apps."
            return
        }
        guard !store.isReadOnly,
              let project = store.ensureAppSearchPresenceProject(for: app),
              let target = project.targets.first
        else {
            statusText = "More search terms cannot be added while the library is read-only."
            return
        }

        let currentRunID = UUID()
        runID = currentRunID
        isRunning = true
        completed = 0
        total = 0
        failureCount = 0
        appleAdsSuggestionFailure = nil
        popularityStatusDetail = nil
        statusText = "Finding more relevant search terms..."

        task = Task { [weak self] in
            guard let self else { return }
            await runSearchMore(
                project: project,
                target: target,
                store: store,
                runID: currentRunID
            )
        }
    }

    func cancel() {
        runID = UUID()
        task?.cancel()
        task = nil
        rankingScanner.cancel()
        isRunning = false
    }

    private func run(
        project: ResearchProject,
        target: StoreTarget,
        store: LibraryStore,
        force: Bool,
        runID currentRunID: UUID
    ) async {
        defer { finish(runID: currentRunID) }
        let refreshDate = now()
        let cutoff = refreshDate.addingTimeInterval(-freshnessTTL)
        let appleAdsCredentials = await researchAppleAdsCredentials(
            store: store,
            target: target
        )

        let existingHints = suggestionRecords(in: project, target: target)
        var hints = existingHints
        if force || !hasFreshHints(existingHints, cutoff: cutoff) {
            let seedCount = min(
                stableUniqueKeywords(project.seedKeywords).count,
                maximumKeywordCount
            )
            let seeds = suggestionSeeds(for: project)
            let maximumSuggestionCount = maximumKeywordCount - seedCount
            var appleRecords: [KeywordRecord] = []
            if let credentials = appleAdsCredentials,
               let researchAppAdamID = credentials.researchAppAdamID
            {
                do {
                    appleRecords = try await fetchAppleAdsSuggestions(
                        seeds: seeds,
                        promotedObjectID: researchAppAdamID,
                        target: target,
                        credentials: credentials,
                        checkedAt: refreshDate,
                        maximumCount: maximumSuggestionCount,
                        runID: currentRunID
                    )
                } catch is CancellationError {
                    return
                } catch {
                    appleAdsSuggestionFailure = error.localizedDescription
                }
            }

            let hintResult = await fetchHints(
                seeds: seeds,
                target: target,
                checkedAt: refreshDate,
                maximumCount: maximumSuggestionCount,
                runID: currentRunID
            )
            let records = mergeSuggestionRecords(
                preferred: appleRecords,
                supplemental: hintResult.records,
                maximumCount: maximumSuggestionCount
            )
            guard isCurrent(currentRunID) else { return }
            failureCount += hintResult.failureCount
            if force, hintResult.failureCount == 0 {
                hints = records
            } else if !records.isEmpty {
                hints = mergeHintRecords(existing: existingHints, incoming: records)
            }
            if !appleRecords.isEmpty
                || hintResult.failureCount < max(seeds.count, 1)
            {
                store.replaceRelatedSuggestions(hints, target: target, into: project.id)
            }
        }

        guard isCurrent(currentRunID),
              let persistedProject = store.project(id: project.id)
        else {
            return
        }

        let persistedHints = suggestionRecords(in: persistedProject, target: target)
        let candidates = rankingCandidates(
            project: persistedProject,
            hints: persistedHints,
            maximumCount: force ? maximumKeywordCount : maximumExpandedKeywordCount
        )
        store.retainSearchPresenceCandidates(candidates, target: target, in: persistedProject.id)
        guard let candidateProject = store.project(id: project.id) else { return }
        await enrichPopularity(
            candidates: candidates,
            project: candidateProject,
            target: target,
            store: store,
            force: force,
            cutoff: cutoff,
            checkedAt: refreshDate,
            appleAdsCredentials: appleAdsCredentials,
            runID: currentRunID
        )

        guard isCurrent(currentRunID),
              let rankingProject = store.project(id: project.id)
        else {
            return
        }
        let keywordsToScan = force
            ? candidates
            : staleRankingCandidates(candidates, project: rankingProject, target: target, cutoff: cutoff)

        guard !keywordsToScan.isEmpty else {
            let summary = failureCount == 0
                ? "Search presence is up to date."
                : "Search presence is current; some keyword metrics could not be refreshed."
            statusText = [summary, popularityStatusDetail]
                .compactMap { $0 }
                .joined(separator: " ")
            return
        }

        statusText = "Checking app positions..."
        guard await scanRankings(
            project: rankingProject,
            keywords: keywordsToScan,
            target: target,
            store: store,
            runID: currentRunID
        ) else {
            return
        }
        failureCount += rankingScanner.failureCount
        let summary: String
        if failureCount > 0 {
            summary = "Search presence updated with \(failureCount) failed request\(failureCount == 1 ? "" : "s")."
        } else {
            summary = "Search presence updated."
        }
        statusText = [summary, popularityStatusDetail]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func runSearchMore(
        project: ResearchProject,
        target: StoreTarget,
        store: LibraryStore,
        runID currentRunID: UUID
    ) async {
        defer { finish(runID: currentRunID) }
        guard let persistedProject = store.project(id: project.id) else { return }

        let existingHints = suggestionRecords(in: persistedProject, target: target)
        let existingCandidates = rankingCandidates(
            project: persistedProject,
            hints: existingHints,
            maximumCount: maximumExpandedKeywordCount
        )
        let remainingCapacity = maximumExpandedKeywordCount - existingCandidates.count
        guard remainingCapacity > 0 else {
            statusText = "Search presence has reached the \(maximumExpandedKeywordCount)-term limit."
            return
        }

        let scope = expansionScopeKey(project: persistedProject, target: target)
        let seeds = expansionSeeds(
            app: project.focusAppAdamID,
            project: persistedProject,
            target: target,
            hints: existingHints,
            store: store,
            excluding: usedExpansionSeedsByScope[scope] ?? []
        )
        guard !seeds.isEmpty else {
            statusText = "No additional suggestion layer is available. Refresh to start over."
            return
        }

        let checkedAt = now()
        let batchLimit = min(searchMoreBatchSize, remainingCapacity)
        let excludedKeys = Set(existingCandidates.map(normalizedKeyword))
        let appleAdsCredentials = await researchAppleAdsCredentials(
            store: store,
            target: target
        )
        var appleRecords: [KeywordRecord] = []
        if let credentials = appleAdsCredentials,
           let researchAppAdamID = credentials.researchAppAdamID
        {
            do {
                appleRecords = try await fetchAppleAdsSuggestions(
                    seeds: seeds,
                    promotedObjectID: researchAppAdamID,
                    target: target,
                    credentials: credentials,
                    checkedAt: checkedAt,
                    maximumCount: batchLimit,
                    excluding: excludedKeys,
                    runID: currentRunID
                )
            } catch is CancellationError {
                return
            } catch {
                appleAdsSuggestionFailure = error.localizedDescription
            }
        }

        let hintResult = await fetchHints(
            seeds: seeds,
            target: target,
            checkedAt: checkedAt,
            maximumCount: batchLimit,
            excluding: excludedKeys,
            runID: currentRunID
        )
        guard isCurrent(currentRunID) else { return }
        failureCount += hintResult.failureCount
        let records = mergeSuggestionRecords(
            preferred: appleRecords,
            supplemental: hintResult.records,
            maximumCount: batchLimit
        )

        let completedAtLeastOneSource = !appleRecords.isEmpty
            || hintResult.failureCount < seeds.count
        if completedAtLeastOneSource {
            usedExpansionSeedsByScope[scope, default: []].formUnion(
                seeds.map(normalizedKeyword)
            )
        }
        guard !records.isEmpty else {
            statusText = failureCount > 0 && !completedAtLeastOneSource
                ? "More search terms could not be loaded. Try again."
                : "No new search terms were found in this suggestion layer."
            return
        }

        store.mergeKeywords(records, into: persistedProject.id)
        let newKeywords = stableUniqueKeywords(records.map(\.keyword))
        guard let metricProject = store.project(id: persistedProject.id) else { return }
        await enrichPopularity(
            candidates: newKeywords,
            project: metricProject,
            target: target,
            store: store,
            force: true,
            cutoff: checkedAt,
            checkedAt: checkedAt,
            appleAdsCredentials: appleAdsCredentials,
            runID: currentRunID
        )

        guard isCurrent(currentRunID),
              let rankingProject = store.project(id: persistedProject.id)
        else {
            return
        }
        statusText = "Checking positions for \(newKeywords.count) new terms..."
        guard await scanRankings(
            project: rankingProject,
            keywords: newKeywords,
            target: target,
            store: store,
            runID: currentRunID
        ) else {
            return
        }
        failureCount += rankingScanner.failureCount

        let summary = failureCount == 0
            ? "Added \(newKeywords.count) more search terms."
            : "Added \(newKeywords.count) more search terms with \(failureCount) failed request\(failureCount == 1 ? "" : "s")."
        statusText = [summary, popularityStatusDetail]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func fetchHints(
        seeds: [String],
        target: StoreTarget,
        checkedAt: Date,
        maximumCount: Int,
        excluding: Set<String> = [],
        runID currentRunID: UUID
    ) async -> (records: [KeywordRecord], failureCount: Int) {
        let uniqueSeeds = stableUniqueKeywords(seeds)
        guard !uniqueSeeds.isEmpty, maximumCount > 0 else { return ([], 0) }
        total = uniqueSeeds.count
        completed = 0

        var fetchedGroups: [(seed: String, hints: [AppStoreSearchHint])] = []
        var failures = 0
        for (index, seed) in uniqueSeeds.enumerated() {
            guard isCurrent(currentRunID) else { return ([], failures) }
            do {
                let fetched = try await hintsProvider.fetch(seed: seed, target: target)
                fetchedGroups.append((seed, fetched))
            } catch is CancellationError {
                return ([], failures)
            } catch {
                failures += 1
            }
            completed = index + 1
        }

        var candidates: [(term: String, seed: String)] = []
        var seen = excluding
        var offset = 0
        while candidates.count < maximumCount,
              fetchedGroups.contains(where: { offset < $0.hints.count })
        {
            for group in fetchedGroups where offset < group.hints.count {
                let term = group.hints[offset].term
                let key = normalizedKeyword(term)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                candidates.append((term, group.seed))
                if candidates.count == maximumCount { break }
            }
            offset += 1
        }

        return (
            candidates.enumerated().map { offset, candidate in
                KeywordRecord(
                    keyword: candidate.term,
                    language: target.language,
                    store: target.store,
                    genre: "Apple Search Suggestions",
                    popularity: 0,
                    relevanceScore: 4 - (Double(offset) / Double(max(candidates.count, 1))),
                    intentTags: ["apple-search-hint"],
                    matchedTerms: [candidate.seed],
                    source: .appleSearchHints,
                    isTracked: false,
                    updatedAt: checkedAt
                )
            },
            failures
        )
    }

    private func fetchAppleAdsSuggestions(
        seeds: [String],
        promotedObjectID: Int64,
        target: StoreTarget,
        credentials: AppleAdsCredentials,
        checkedAt: Date,
        maximumCount: Int,
        excluding: Set<String> = [],
        runID currentRunID: UUID
    ) async throws -> [KeywordRecord] {
        let uniqueSeeds = stableUniqueKeywords(seeds)
        guard !uniqueSeeds.isEmpty, maximumCount > 0 else { return [] }
        total = 1
        completed = 0

        let suggestions = try await appleAdsClient.fetchKeywordSuggestions(
            terms: uniqueSeeds,
            promotedObjectID: promotedObjectID,
            target: target,
            credentials: credentials
        )
        guard isCurrent(currentRunID) else { throw CancellationError() }
        completed = 1

        var seen = excluding
        let uniqueSuggestions = suggestions.filter {
            seen.insert(normalizedKeyword($0.text)).inserted
        }.prefix(maximumCount)
        return uniqueSuggestions.enumerated().map { offset, suggestion in
            KeywordRecord(
                keyword: suggestion.text,
                language: target.language,
                store: target.store,
                country: target.store.uppercased(),
                genre: "Apple Ads Suggestions",
                popularity: suggestion.popularity,
                relevanceScore: 4 - (Double(offset) / Double(max(uniqueSuggestions.count, 1))),
                intentTags: ["apple-ads-suggestion"],
                matchedTerms: uniqueSeeds,
                source: .appleAds,
                isTracked: false,
                updatedAt: checkedAt,
                popularityCheckedAt: checkedAt
            )
        }
    }

    private func enrichPopularity(
        candidates: [String],
        project: ResearchProject,
        target: StoreTarget,
        store: LibraryStore,
        force: Bool,
        cutoff: Date,
        checkedAt: Date,
        appleAdsCredentials: AppleAdsCredentials?,
        runID currentRunID: UUID
    ) async {
        let candidateKeys = Set(candidates.map(normalizedKeyword))
        let skipKeys = Set(project.keywords.compactMap { record -> String? in
            guard record.store.caseInsensitiveCompare(target.store) == .orderedSame,
                  let popularityCheckedAt = record.popularityCheckedAt,
                  popularityCheckedAt >= (force ? checkedAt : cutoff)
            else {
                return nil
            }
            let key = normalizedKeyword(record.keyword)
            return candidateKeys.contains(key) ? key : nil
        })
        let keywords = candidates.filter { !skipKeys.contains(normalizedKeyword($0)) }
        guard !keywords.isEmpty else { return }

        guard let credentials = appleAdsCredentials else {
            popularityStatusDetail = "Connect Apple Ads to fetch popularity."
            return
        }

        statusText = "Checking keyword popularity..."
        do {
            let resolution = try await AppleAdsKeywordPopularityResolver(
                client: appleAdsClient
            ).resolve(
                keywords: keywords,
                target: target,
                genres: project.genres,
                credentials: credentials,
                checkedAt: checkedAt
            )
            let metricRecords = resolution.records
            let missingKeywords = resolution.unmatchedKeywords
            if let exactLookupFailure = resolution.appSuggestionFailure {
                appleAdsSuggestionFailure = exactLookupFailure
            }
            guard isCurrent(currentRunID) else { return }
            let records = metricRecords.map { record in
                var updated = record
                updated.isTracked = false
                updated.updatedAt = checkedAt
                updated.popularityCheckedAt = checkedAt
                return updated
            }
            store.mergeKeywords(records, into: project.id)
            store.markPopularityChecked(
                keywords: keywords,
                store: target.store,
                projectID: project.id,
                checkedAt: checkedAt
            )
            let matchedKeys = Set(metricRecords.map { normalizedKeyword($0.keyword) })
            let foundCount = skipKeys.union(matchedKeys).count
            let totalCount = foundCount + missingKeywords.count
            var details: [String] = []
            if !missingKeywords.isEmpty {
                details.append(
                    "Popularity found for \(foundCount) of \(totalCount) terms; \(missingKeywords.count) \(missingKeywords.count == 1 ? "has" : "have") no exact Apple Ads value."
                )
            } else if resolution.reportMatchCount > 0 {
                details.append(
                    "Apple's weekly genre report matched \(resolution.reportMatchCount) term\(resolution.reportMatchCount == 1 ? "" : "s")."
                )
            }
            if let appleAdsSuggestionFailure {
                if appleAdsSuggestionFailure.localizedCaseInsensitiveContains(
                    "app not found or access denied"
                ) {
                    details.append(
                        "The selected research app is not available to this Apple Ads account; the weekly genre report was used."
                    )
                } else {
                    details.append(
                        "Apple Ads exact lookup failed: \(appleAdsSuggestionFailure)"
                    )
                }
            } else if !resolution.reportFailures.isEmpty, resolution.reportSuccessCount == 0 {
                details.append(
                    "Apple Ads genre reports failed."
                )
            }
            popularityStatusDetail = details.isEmpty
                ? nil
                : details.joined(separator: " ")
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(currentRunID) else { return }
            failureCount += 1
        }
    }

    private func rankingCandidates(
        project: ResearchProject,
        hints: [KeywordRecord],
        maximumCount: Int? = nil
    ) -> [String] {
        let genreKeys = Set(project.genres.map(normalizedKeyword))
        let specificSeeds = project.seedKeywords.filter { !genreKeys.contains(normalizedKeyword($0)) }
        let genreSeeds = project.seedKeywords.filter { genreKeys.contains(normalizedKeyword($0)) }
        let orderedHints = hints.sorted {
            if $0.relevanceScore != $1.relevanceScore {
                return $0.relevanceScore > $1.relevanceScore
            }
            return $0.keyword.localizedCaseInsensitiveCompare($1.keyword) == .orderedAscending
        }
        let specificHints = orderedHints.filter { record in
            !record.matchedTerms.contains { genreKeys.contains(normalizedKeyword($0)) }
        }
        let genreHints = orderedHints.filter { record in
            record.matchedTerms.contains { genreKeys.contains(normalizedKeyword($0)) }
        }
        let limit = maximumCount ?? maximumKeywordCount
        return Array(
            stableUniqueKeywords(
                specificSeeds
                    + specificHints.map(\.keyword)
                    + genreHints.map(\.keyword)
                    + genreSeeds
            )
                .prefix(limit)
        )
    }

    private func expansionSeeds(
        app: Int64?,
        project: ResearchProject,
        target: StoreTarget,
        hints: [KeywordRecord],
        store: LibraryStore,
        excluding usedKeys: Set<String>
    ) -> [String] {
        let rowsByKey: [String: SearchPresenceRow]
        if let app {
            rowsByKey = Dictionary(
                uniqueKeysWithValues: store.searchPresenceRows(
                    for: app,
                    store: target.store
                ).map { (normalizedKeyword($0.keyword), $0) }
            )
        } else {
            rowsByKey = [:]
        }

        let ordered = hints.sorted { lhs, rhs in
            let lhsPosition = rowsByKey[normalizedKeyword(lhs.keyword)]?.focusAppPosition
            let rhsPosition = rowsByKey[normalizedKeyword(rhs.keyword)]?.focusAppPosition
            switch (lhsPosition, rhsPosition) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.relevanceScore != rhs.relevanceScore {
                    return lhs.relevanceScore > rhs.relevanceScore
                }
                if lhs.popularity != rhs.popularity {
                    return lhs.popularity > rhs.popularity
                }
                return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
            }
        }
        return Array(
            stableUniqueKeywords(ordered.map(\.keyword)).filter {
                !usedKeys.contains(normalizedKeyword($0))
            }.prefix(8)
        )
    }

    private func scanRankings(
        project: ResearchProject,
        keywords: [String],
        target: StoreTarget,
        store: LibraryStore,
        runID currentRunID: UUID
    ) async -> Bool {
        rankingScanner.start(
            project: project,
            keywords: keywords,
            storeCode: target.store,
            store: store,
            prioritize: false
        )
        repeat {
            guard isCurrent(currentRunID) else { return false }
            completed = rankingScanner.completed
            total = rankingScanner.total
            if rankingScanner.isRunning {
                try? await Task.sleep(for: .milliseconds(50))
            }
        } while rankingScanner.isRunning

        guard isCurrent(currentRunID) else { return false }
        completed = rankingScanner.completed
        total = rankingScanner.total
        return true
    }

    private func staleRankingCandidates(
        _ candidates: [String],
        project: ResearchProject,
        target: StoreTarget,
        cutoff: Date
    ) -> [String] {
        let freshKeys = Set(project.rankingScans.lazy.filter {
            $0.store.caseInsensitiveCompare(target.store) == .orderedSame
                && $0.checkedAt >= cutoff
        }.map { self.normalizedKeyword($0.keyword) })
        return candidates.filter { !freshKeys.contains(self.normalizedKeyword($0)) }
    }

    private func suggestionRecords(
        in project: ResearchProject,
        target: StoreTarget
    ) -> [KeywordRecord] {
        project.keywords.filter {
            ($0.source == .appleSearchHints
                || $0.intentTags.contains("apple-ads-suggestion"))
                && $0.language.caseInsensitiveCompare(target.language) == .orderedSame
                && $0.store.caseInsensitiveCompare(target.store) == .orderedSame
        }
    }

    private func hasFreshHints(_ hints: [KeywordRecord], cutoff: Date) -> Bool {
        guard !hints.isEmpty else { return false }
        return hints.compactMap(\.updatedAt).max() ?? .distantPast >= cutoff
    }

    private func mergeHintRecords(
        existing: [KeywordRecord],
        incoming: [KeywordRecord]
    ) -> [KeywordRecord] {
        var byKey = Dictionary(uniqueKeysWithValues: existing.map { (normalizedKeyword($0.keyword), $0) })
        for record in incoming {
            byKey[normalizedKeyword(record.keyword)] = record
        }
        return byKey.values.sorted {
            $0.keyword.localizedCaseInsensitiveCompare($1.keyword) == .orderedAscending
        }
    }

    private func suggestionSeeds(for project: ResearchProject) -> [String] {
        let genreKeys = Set(project.genres.map(normalizedKeyword))
        let specificSeeds = stableUniqueKeywords(project.seedKeywords).filter {
            !genreKeys.contains(normalizedKeyword($0))
        }
        let seeds = specificSeeds.isEmpty
            ? stableUniqueKeywords(project.seedKeywords)
            : specificSeeds
        return Array(seeds.prefix(8))
    }

    private func mergeSuggestionRecords(
        preferred: [KeywordRecord],
        supplemental: [KeywordRecord],
        maximumCount: Int
    ) -> [KeywordRecord] {
        guard maximumCount > 0 else { return [] }
        var seen: Set<String> = []
        return (preferred + supplemental).filter {
            seen.insert(normalizedKeyword($0.keyword)).inserted
        }.prefix(maximumCount).map { $0 }
    }

    private func expansionScopeKey(
        project: ResearchProject,
        target: StoreTarget
    ) -> String {
        "\(project.id.uuidString)|\(target.language.lowercased())|\(target.store.lowercased())"
    }

    private func finish(runID finishedRunID: UUID) {
        guard runID == finishedRunID else { return }
        isRunning = false
        task = nil
    }

    private func isCurrent(_ candidateRunID: UUID) -> Bool {
        !Task.isCancelled && runID == candidateRunID
    }

    private func stableUniqueKeywords(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = normalizedKeyword(trimmed)
            guard !trimmed.isEmpty, seen.insert(normalized).inserted else { return nil }
            return trimmed
        }
    }

    private func normalizedKeyword(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func connectedAppleAdsCredentials() throws -> AppleAdsCredentials? {
        guard let credentials = try appleAdsCredentialStore.load(), credentials.isConnected else {
            return nil
        }
        return credentials
    }

    private func researchAppleAdsCredentials(
        store: LibraryStore,
        target: StoreTarget
    ) async -> AppleAdsCredentials? {
        guard let credentials = try? connectedAppleAdsCredentials() else { return nil }
        guard !credentials.hasResearchApp else { return credentials }

        do {
            return try await AppleAdsResearchAppResolver(
                client: appleAdsClient,
                credentialStore: appleAdsCredentialStore
            ).resolve(
                credentials: credentials,
                candidates: store.library.apps,
                target: target
            )
        } catch is CancellationError {
            return nil
        } catch {
            appleAdsSuggestionFailure = error.localizedDescription
            return credentials
        }
    }
}
