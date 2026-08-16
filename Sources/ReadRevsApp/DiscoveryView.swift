import ReadRevsCore
import SwiftUI

private struct DiscoverySummaryRow: Identifiable {
    var id: String { "\(store)|\(genre)" }
    let store: String
    let genre: String
    let keywordCount: Int
    let topPopularity: Int
}

private struct PopularityCandidate {
    let project: ResearchProject
    let keyword: String
    let target: StoreTarget
}

private struct DiscoveryRequest: Sendable {
    let target: StoreTarget
    let genre: String
}

private enum DiscoveryOperation {
    case discovery
    case popularityLookup
    case suggestions
}

@MainActor
final class DiscoveryController: ObservableObject {
    private static let searchMoreResultLimit = 50

    @Published var isRunning = false
    @Published var completed = 0
    @Published var total = 0
    @Published var failureCount = 0
    @Published var statusText: String?

    private var task: Task<Void, Never>?
    private let hintsClient: any AppStoreSearchHintsProviding
    private let appleAdsClient: any AppleAdsPlatformProviding
    private let appleAdsCredentialStore: any AppleAdsCredentialStoring
    private var runID = UUID()
    private var operation: DiscoveryOperation?
    private var popularityCandidates = PrioritizedUniqueQueue<PopularityCandidate, String>(
        key: popularityCandidateKey
    )
    private var activePopularityKeys: Set<String> = []
    private var retryRequestedPopularity: [String: PopularityCandidate] = [:]
    private var popularityFoundCount = 0
    private var popularityMissingCount = 0
    private var popularityUsedAppleAds = false
    private var popularityAppleReportRequestCount = 0
    private var popularityAppleReportSuccessCount = 0
    private var popularityAppleReportMatchCount = 0
    private var popularityAppleReportFailures: [String] = []
    private var popularityAppleAppFailure: String?

    init(
        hintsClient: any AppStoreSearchHintsProviding = AppStoreSearchHintsClient(),
        appleAdsClient: any AppleAdsPlatformProviding = AppleAdsPlatformClient.shared,
        appleAdsCredentialStore: any AppleAdsCredentialStoring = KeychainAppleAdsCredentialStore()
    ) {
        self.hintsClient = hintsClient
        self.appleAdsClient = appleAdsClient
        self.appleAdsCredentialStore = appleAdsCredentialStore
    }

    func start(
        project: ResearchProject,
        minimumPopularity: Int,
        storeFilter: String? = nil,
        store: LibraryStore
    ) {
        guard !project.genres.isEmpty else {
            statusText = "Select at least one genre to fetch Apple Ads popularity."
            return
        }
        guard let appleAdsCredentials = try? connectedAppleAdsCredentials() else {
            statusText = "Connect Apple Ads to fetch popularity."
            return
        }
        let targets = project.targets.filter { target in
            guard let storeFilter else { return true }
            return target.store.caseInsensitiveCompare(storeFilter) == .orderedSame
        }
        let requests = targets.flatMap { target in
            project.genres.map { genre in
                DiscoveryRequest(target: target, genre: genre)
            }
        }
        guard !requests.isEmpty else { return }

        let currentRunID = begin(total: requests.count)
        operation = .discovery

        task = Task { [weak self] in
            guard let self else { return }
            defer { finish(runID: currentRunID) }

            for (index, request) in requests.enumerated() {
                guard !Task.isCancelled, runID == currentRunID else { return }
                do {
                    let rows = try await appleAdsClient.fetchSearchTermPopularity(
                        target: request.target,
                        genre: request.genre,
                        credentials: appleAdsCredentials
                    )
                    let checkedAt = Date()
                    let records: [KeywordRecord] = rows.compactMap { row in
                        guard row.popularity >= minimumPopularity else { return nil }
                        return KeywordRecord(
                            keyword: row.searchTerm,
                            language: request.target.language,
                            store: request.target.store,
                            country: row.countryOrRegion,
                            genre: request.genre,
                            popularity: row.popularity,
                            intentTags: ["apple-ads-popularity"],
                            month: row.period,
                            sourceID: String(row.rankInGenre),
                            source: .appleAds,
                            isTracked: false,
                            updatedAt: checkedAt,
                            popularityCheckedAt: checkedAt
                        )
                    }
                    let topic = project.topic
                    let seedKeywords = project.seedKeywords
                    var enriched = await Task.detached(priority: .userInitiated) {
                        KeywordResearchScorer.enrich(
                            records,
                            topic: topic,
                            seedKeywords: seedKeywords
                        )
                    }.value
                    for index in enriched.indices
                    where records[index].intentTags.contains("apple-ads-popularity") {
                        if !enriched[index].intentTags.contains("apple-ads-popularity") {
                            enriched[index].intentTags.append("apple-ads-popularity")
                        }
                    }
                    guard !Task.isCancelled, runID == currentRunID else { return }
                    store.replaceSuggestions(
                        enriched,
                        target: request.target,
                        genre: request.genre,
                        into: project.id
                    )
                } catch is CancellationError {
                    return
                } catch {
                    guard runID == currentRunID else { return }
                    failureCount += 1
                    statusText = error.localizedDescription
                }
                completed = index + 1
            }

            guard runID == currentRunID else { return }
            if failureCount > 0 {
                statusText = "Completed with \(failureCount) failed request\(failureCount == 1 ? "" : "s")."
            } else {
                statusText = "Apple Ads popularity updated."
            }
        }
    }

    func startPopularityLookup(
        project: ResearchProject,
        keywords: [String],
        target: StoreTarget,
        store: LibraryStore
    ) {
        let requested = stableUniqueKeywords(keywords)
        guard !requested.isEmpty else { return }
        let candidates = requested.map {
            PopularityCandidate(project: project, keyword: $0, target: target)
        }
        guard let connectedCredentials = try? connectedAppleAdsCredentials() else {
            statusText = "Connect Apple Ads to fetch popularity."
            return
        }

        if isRunning, operation == .popularityLookup {
            enqueuePopularity(candidates, prioritize: true)
            return
        }

        let currentRunID = begin(total: 0)
        operation = .popularityLookup
        enqueuePopularity(candidates, prioritize: true)

        task = Task { [weak self] in
            guard let self else { return }
            defer { finish(runID: currentRunID) }

            var appleAdsCredentials = connectedCredentials
            if !appleAdsCredentials.hasResearchApp {
                do {
                    appleAdsCredentials = try await AppleAdsResearchAppResolver(
                        client: appleAdsClient,
                        credentialStore: appleAdsCredentialStore
                    ).resolve(
                        credentials: appleAdsCredentials,
                        candidates: store.library.apps,
                        target: target
                    )
                } catch is CancellationError {
                    return
                } catch {
                    popularityAppleAppFailure = error.localizedDescription
                }
            }

            while let batch = dequeuePopularityBatch() {
                guard !Task.isCancelled, runID == currentRunID else { return }
                let requestedKeywords = batch.map(\.keyword)
                let context = batch[0]
                let currentKeys = Set(batch.map(popularityCandidateKey))
                activePopularityKeys = currentKeys
                var didSucceed = false
                var didCompleteLookup = false
                let checkedAt = Date()

                do {
                    let resolution = try await AppleAdsKeywordPopularityResolver(
                        client: appleAdsClient
                    ).resolve(
                        keywords: requestedKeywords,
                        target: context.target,
                        genres: context.project.genres,
                        credentials: appleAdsCredentials,
                        checkedAt: checkedAt
                    )
                    guard !Task.isCancelled, runID == currentRunID else { return }
                    let records = resolution.records
                    popularityFoundCount += records.count
                    popularityMissingCount += resolution.unmatchedKeywords.count
                    popularityUsedAppleAds = popularityUsedAppleAds || !records.isEmpty
                    popularityAppleReportRequestCount += resolution.reportRequestCount
                    popularityAppleReportSuccessCount += resolution.reportSuccessCount
                    popularityAppleReportMatchCount += resolution.reportMatchCount
                    popularityAppleReportFailures.append(contentsOf: resolution.reportFailures)
                    if let appSuggestionFailure = resolution.appSuggestionFailure {
                        popularityAppleAppFailure = appSuggestionFailure
                    }
                    didSucceed = resolution.reportSuccessCount > 0
                        || (resolution.appSuggestionsAttempted
                            && resolution.appSuggestionFailure == nil)

                    guard !Task.isCancelled, runID == currentRunID else { return }
                    let topic = context.project.topic
                    let seedKeywords = context.project.seedKeywords
                    let recordsToEnrich = records
                    let enriched = await Task.detached(priority: .userInitiated) {
                        KeywordResearchScorer.enrich(
                            recordsToEnrich,
                            topic: topic,
                            seedKeywords: seedKeywords
                        )
                    }.value
                    guard !Task.isCancelled, runID == currentRunID else { return }
                    store.mergeKeywords(enriched, into: context.project.id)
                    didCompleteLookup = didSucceed
                } catch is CancellationError {
                    return
                } catch {
                    guard runID == currentRunID else { return }
                    failureCount += 1
                    statusText = "Popularity update failed: \(error.localizedDescription)"
                }

                guard !Task.isCancelled, runID == currentRunID else { return }
                if didCompleteLookup {
                    store.markPopularityChecked(
                        keywords: requestedKeywords,
                        store: context.target.store,
                        projectID: context.project.id,
                        checkedAt: checkedAt
                    )
                }

                completed += batch.count
                activePopularityKeys.removeAll()
                let requestedRetries = currentKeys.compactMap {
                    retryRequestedPopularity.removeValue(forKey: $0)
                }
                if !didSucceed {
                    enqueuePopularity(requestedRetries, prioritize: true)
                }
            }

            guard runID == currentRunID else { return }
            statusText = popularityStatusText
        }
    }

    func startSuggestions(
        project: ResearchProject,
        target: StoreTarget,
        seeds: [String],
        store: LibraryStore,
        appendsResults: Bool = false,
        onReady: @escaping ([String]) -> Void
    ) {
        let requestedSeeds = stableUniqueKeywords(seeds)
        guard !requestedSeeds.isEmpty else {
            if !appendsResults {
                store.replaceRelatedSuggestions([], target: target, into: project.id)
            }
            statusText = "Add a topic or tracked keyword to find related suggestions."
            onReady([])
            return
        }

        var excludedKeys = Set(requestedSeeds.map(normalizedKeyword))
        excludedKeys.formUnion(project.keywords.lazy.filter {
            $0.isActivelyTracked
                && $0.language.caseInsensitiveCompare(target.language) == .orderedSame
                && $0.store.caseInsensitiveCompare(target.store) == .orderedSame
        }.map { self.normalizedKeyword($0.keyword) })
        if appendsResults {
            excludedKeys.formUnion(project.keywords.lazy.filter {
                ($0.source == .appleSearchHints
                    || $0.intentTags.contains("apple-ads-suggestion"))
                    && $0.language.caseInsensitiveCompare(target.language) == .orderedSame
                    && $0.store.caseInsensitiveCompare(target.store) == .orderedSame
            }.map { self.normalizedKeyword($0.keyword) })
        }

        let currentRunID = begin(total: requestedSeeds.count)
        operation = .suggestions
        let connectedCredentials = try? connectedAppleAdsCredentials()
        let resultLimit = appendsResults ? Self.searchMoreResultLimit : Int.max

        task = Task { [weak self] in
            guard let self else { return }
            defer { finish(runID: currentRunID) }

            var appleAdsFallbackReason: String?
            var appleAdsCredentials = connectedCredentials
            var directSuggestionRecords: [KeywordRecord] = []
            var directSuggestionKeywords: [String] = []
            if let credentials = appleAdsCredentials, !credentials.hasResearchApp {
                do {
                    appleAdsCredentials = try await AppleAdsResearchAppResolver(
                        client: appleAdsClient,
                        credentialStore: appleAdsCredentialStore
                    ).resolve(
                        credentials: credentials,
                        candidates: store.library.apps,
                        target: target
                    )
                } catch is CancellationError {
                    return
                } catch {
                    appleAdsFallbackReason = error.localizedDescription
                }
            }

            if let appleAdsCredentials,
               let researchAppAdamID = appleAdsCredentials.researchAppAdamID
            {
                do {
                    let suggestions = try await appleAdsClient.fetchKeywordSuggestions(
                        terms: requestedSeeds,
                        promotedObjectID: researchAppAdamID,
                        target: target,
                        credentials: appleAdsCredentials
                    )
                    guard !Task.isCancelled, runID == currentRunID else { return }

                    var seen: Set<String> = []
                    let filtered = suggestions.filter { suggestion in
                        let key = normalizedKeyword(suggestion.text)
                        return !excludedKeys.contains(key) && seen.insert(key).inserted
                    }.prefix(resultLimit)
                    if !filtered.isEmpty {
                        let checkedAt = Date()
                        let directRecords = filtered.map { suggestion in
                            KeywordRecord(
                                keyword: suggestion.text,
                                language: target.language,
                                store: target.store,
                                country: target.store.uppercased(),
                                genre: "Apple Ads Suggestions",
                                popularity: suggestion.popularity,
                                intentTags: ["apple-ads-suggestion"],
                                matchedTerms: requestedSeeds,
                                source: .appleAds,
                                isTracked: false,
                                updatedAt: checkedAt,
                                popularityCheckedAt: checkedAt
                            )
                        }
                        var enriched = await Task.detached(priority: .userInitiated) {
                            KeywordResearchScorer.enrich(
                                directRecords,
                                topic: project.topic,
                                seedKeywords: requestedSeeds
                            )
                        }.value
                        for index in enriched.indices {
                            if !enriched[index].intentTags.contains("apple-ads-suggestion") {
                                enriched[index].intentTags.append("apple-ads-suggestion")
                            }
                            if enriched[index].matchedTerms.isEmpty {
                                enriched[index].matchedTerms = requestedSeeds
                            }
                        }
                        let keywords = filtered.map(\.text)
                        if appendsResults {
                            directSuggestionRecords = enriched
                            directSuggestionKeywords = keywords
                            excludedKeys.formUnion(keywords.map(normalizedKeyword))
                        } else {
                            store.replaceRelatedSuggestions(enriched, target: target, into: project.id)
                            completed = requestedSeeds.count
                            onReady(keywords)
                            statusText = "Found \(keywords.count) Apple Ads suggestions with direct popularity."
                            return
                        }
                    } else {
                        appleAdsFallbackReason = "Apple Ads returned no related suggestions."
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if error.localizedDescription.localizedCaseInsensitiveContains(
                        "app not found or access denied"
                    ) {
                        appleAdsFallbackReason = "The selected research app is not available to this Apple Ads account; using the weekly genre report."
                    } else {
                        appleAdsFallbackReason = "Apple Ads suggestions unavailable: \(error.localizedDescription)"
                    }
                }
            }

            var terms: [(term: String, seed: String)] = []
            var seen: Set<String> = []
            let hintLimit = max(resultLimit - directSuggestionKeywords.count, 0)
            for (index, seed) in requestedSeeds.enumerated() {
                if terms.count >= hintLimit { break }
                guard !Task.isCancelled, runID == currentRunID else { return }
                do {
                    let hints = try await hintsClient.fetch(seed: seed, target: target)
                    for hint in hints {
                        let key = normalizedKeyword(hint.term)
                        guard !excludedKeys.contains(key), seen.insert(key).inserted else { continue }
                        terms.append((hint.term, seed))
                        if terms.count >= hintLimit { break }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard runID == currentRunID else { return }
                    failureCount += 1
                }
                completed = index + 1
            }

            guard !Task.isCancelled, runID == currentRunID else { return }
            let hintRecords = terms.map { candidate in
                KeywordRecord(
                    keyword: candidate.term,
                    language: target.language,
                    store: target.store,
                    genre: "Apple Search Suggestions",
                    popularity: 0,
                    relevanceScore: 2.4,
                    opportunityScore: 0,
                    intentTags: ["apple-search-hint"],
                    matchedTerms: [candidate.seed],
                    source: .appleSearchHints,
                    isTracked: false,
                    updatedAt: Date()
                )
            }
            let suggestionRecords = directSuggestionRecords + hintRecords
            if appendsResults {
                store.mergeKeywords(suggestionRecords, into: project.id)
            } else {
                store.replaceRelatedSuggestions(suggestionRecords, target: target, into: project.id)
            }

            let hintKeywords = terms.map(\.term)
            let keywords = stableUniqueKeywords(directSuggestionKeywords + hintKeywords)
            guard !keywords.isEmpty else {
                let fallbackStatus = failureCount > 0
                    ? "Related suggestions could not be loaded."
                    : "No related suggestions found for this context."
                statusText = [appleAdsFallbackReason, fallbackStatus]
                    .compactMap { $0 }
                    .joined(separator: " ")
                return
            }

            guard !hintKeywords.isEmpty else {
                onReady(keywords)
                statusText = appendsResults
                    ? "Found \(keywords.count) more Apple Ads suggestions with direct popularity."
                    : "Found \(keywords.count) Apple Ads suggestions with direct popularity."
                return
            }

            let checkedAt = Date()
            var didCompleteMetricLookup = false
            do {
                var metricRecords: [KeywordRecord] = []
                var remainingKeywords = hintKeywords
                if let appleAdsCredentials {
                    let resolution = try await AppleAdsKeywordPopularityResolver(
                        client: appleAdsClient
                    ).resolve(
                        keywords: hintKeywords,
                        target: target,
                        genres: project.genres,
                        credentials: appleAdsCredentials,
                        checkedAt: checkedAt
                    )
                    metricRecords.append(contentsOf: resolution.records)
                    remainingKeywords = resolution.unmatchedKeywords
                    if appleAdsFallbackReason == nil,
                       let appSuggestionFailure = resolution.appSuggestionFailure
                    {
                        appleAdsFallbackReason = "Apple Ads app suggestions unavailable: \(appSuggestionFailure)"
                    }
                    if appleAdsFallbackReason == nil,
                       resolution.reportRequestCount > 0,
                       resolution.reportSuccessCount == 0,
                       !resolution.reportFailures.isEmpty
                    {
                        appleAdsFallbackReason = "Apple Ads genre reports unavailable: \(resolution.reportFailures[0])"
                    }
                    didCompleteMetricLookup = resolution.reportSuccessCount > 0
                        || (resolution.appSuggestionsAttempted
                            && resolution.appSuggestionFailure == nil)
                } else if appleAdsFallbackReason == nil {
                    appleAdsFallbackReason = "Connect Apple Ads to fetch popularity."
                }
                let missingKeywords = remainingKeywords
                guard !Task.isCancelled, runID == currentRunID else { return }
                let recordsToEnrich = metricRecords.map { record in
                    var updated = record
                    updated.updatedAt = checkedAt
                    updated.popularityCheckedAt = checkedAt
                    return updated
                }
                let enriched = await Task.detached(priority: .userInitiated) {
                    KeywordResearchScorer.enrich(
                        recordsToEnrich,
                        topic: project.topic,
                        seedKeywords: requestedSeeds
                    )
                }.value
                guard !Task.isCancelled, runID == currentRunID else { return }
                store.mergeKeywords(enriched, into: project.id)
                popularityFoundCount = metricRecords.count
                popularityMissingCount = missingKeywords.count
            } catch is CancellationError {
                return
            } catch {
                guard runID == currentRunID else { return }
                failureCount += 1
            }

            if didCompleteMetricLookup {
                store.markPopularityChecked(
                    keywords: hintKeywords,
                    store: target.store,
                    projectID: project.id,
                    checkedAt: checkedAt
                )
            }
            onReady(keywords)

            guard runID == currentRunID else { return }
            let foundLabel = appendsResults
                ? "Found \(keywords.count) more related suggestions"
                : "Found \(keywords.count) related suggestions"
            if failureCount > 0 {
                statusText = "\(foundLabel); some metrics failed."
            } else if popularityMissingCount > 0 {
                statusText = "\(foundLabel); \(popularityMissingCount) without popularity."
            } else {
                statusText = "\(foundLabel)."
            }
            if let appleAdsFallbackReason {
                statusText = "\(appleAdsFallbackReason) \(statusText ?? "")"
            }
        }
    }

    var progressLabel: String {
        switch operation {
        case .suggestions:
            "Finding suggestions \(completed)/\(total)"
        case .discovery:
            "Finding popular keywords \(completed)/\(total)"
        case .popularityLookup:
            "Updating popularity"
        case nil:
            ""
        }
    }

    func cancel() {
        runID = UUID()
        task?.cancel()
        task = nil
        isRunning = false
        operation = nil
        popularityCandidates.removeAll()
        activePopularityKeys.removeAll()
        retryRequestedPopularity.removeAll()
    }

    private func begin(total: Int) -> UUID {
        cancel()
        let identifier = UUID()
        runID = identifier
        isRunning = true
        completed = 0
        self.total = total
        failureCount = 0
        statusText = nil
        popularityFoundCount = 0
        popularityMissingCount = 0
        popularityUsedAppleAds = false
        popularityAppleReportRequestCount = 0
        popularityAppleReportSuccessCount = 0
        popularityAppleReportMatchCount = 0
        popularityAppleReportFailures = []
        popularityAppleAppFailure = nil
        return identifier
    }

    private func finish(runID finishedRunID: UUID) {
        guard runID == finishedRunID else { return }
        isRunning = false
        task = nil
        operation = nil
        popularityCandidates.removeAll()
        activePopularityKeys.removeAll()
        retryRequestedPopularity.removeAll()
    }

    private func enqueuePopularity(_ candidates: [PopularityCandidate], prioritize: Bool) {
        var queueable: [PopularityCandidate] = []
        for candidate in candidates {
            let key = popularityCandidateKey(candidate)
            if activePopularityKeys.contains(key) {
                if prioritize { retryRequestedPopularity[key] = candidate }
            } else {
                queueable.append(candidate)
            }
        }
        total += popularityCandidates.enqueue(queueable, prioritize: prioritize)
    }

    private func dequeuePopularityBatch() -> [PopularityCandidate]? {
        guard let first = popularityCandidates.popFirst() else { return nil }
        var batch = [first]
        while batch.count < 100,
              let next = popularityCandidates.pendingElements.first,
              next.project.id == first.project.id,
              next.target.store.caseInsensitiveCompare(first.target.store) == .orderedSame,
              next.target.language.caseInsensitiveCompare(first.target.language) == .orderedSame
        {
            guard let candidate = popularityCandidates.popFirst() else { break }
            batch.append(candidate)
        }
        return batch
    }

    private var popularityStatusText: String {
        if failureCount > 0 {
            return "Popularity update completed with \(failureCount) failed request\(failureCount == 1 ? "" : "s")."
        }
        let base: String
        if popularityFoundCount == 0, popularityMissingCount > 0 {
            base = "Popularity unavailable for \(popularityMissingCount) keyword\(popularityMissingCount == 1 ? "" : "s")."
        } else if popularityMissingCount > 0 {
            let totalCount = popularityFoundCount + popularityMissingCount
            base = "Popularity updated for \(popularityFoundCount) of \(totalCount) keywords; \(popularityMissingCount) unavailable."
        } else if popularityUsedAppleAds {
            base = "Apple Ads popularity updated."
        } else {
            base = "No Apple Ads popularity was returned."
        }

        var details: [String] = []
        if popularityAppleReportMatchCount > 0, popularityMissingCount > 0 {
            details.append(
                "Apple's weekly genre report matched \(popularityAppleReportMatchCount) keyword\(popularityAppleReportMatchCount == 1 ? "" : "s")."
            )
        }
        if let failure = popularityAppleAppFailure {
            if failure.localizedCaseInsensitiveContains("app not found or access denied") {
                details.append(
                    "The selected research app is not available to this Apple Ads account; the weekly genre report was used."
                )
            } else {
                details.append(
                    "Apple Ads exact lookup failed: \(failure)"
                )
            }
        } else if popularityAppleReportRequestCount > 0,
                  popularityAppleReportSuccessCount == 0,
                  !popularityAppleReportFailures.isEmpty
        {
            details.append(
                "Apple Ads genre reports failed."
            )
        }
        return ([base] + details).joined(separator: " ")
    }

    private func stableUniqueKeywords(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ).lowercased()
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
}

private func popularityCandidateKey(_ candidate: PopularityCandidate) -> String {
    let keyword = candidate.keyword.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: .current
    ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return "\(candidate.project.id.uuidString)|\(candidate.target.store.lowercased())|\(keyword)"
}

struct DiscoveryView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var controller = DiscoveryController()
    @State private var minimumPopularity = 25.0

    let projectID: UUID

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

            Divider()

            if summaries.isEmpty {
                ContentUnavailableView("No Popularity Data", systemImage: "sparkle.magnifyingglass")
            } else {
                Table(summaries) {
                    TableColumn("Store", value: \.store)
                        .width(min: 70, ideal: 90)
                    TableColumn("Genre", value: \.genre)
                    TableColumn("Keywords") { row in
                        Text(row.keywordCount.formatted())
                            .monospacedDigit()
                    }
                    .width(min: 80, ideal: 90)
                    TableColumn("Top Popularity") { row in
                        Text(row.topPopularity.formatted())
                            .monospacedDigit()
                    }
                    .width(min: 100, ideal: 120)
                }
            }
        }
        .onDisappear { controller.cancel() }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Minimum Popularity")
                Slider(value: $minimumPopularity, in: 5...90, step: 5)
                    .frame(width: 180)
                Text(Int(minimumPopularity).formatted())
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)

                Spacer()

                if controller.isRunning {
                    Button("Cancel", systemImage: "xmark.circle") {
                        controller.cancel()
                    }
                } else {
                    Button("Fetch Popularity", systemImage: "arrow.clockwise") {
                        guard let project = store.project(id: projectID) else { return }
                        controller.start(
                            project: project,
                            minimumPopularity: Int(minimumPopularity),
                            store: store
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isReadOnly)
                }
            }

            if controller.isRunning {
                ProgressView(value: Double(controller.completed), total: Double(max(controller.total, 1))) {
                    Text("\(controller.completed) of \(controller.total) requests")
                }
            } else if let statusText = controller.statusText {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(controller.failureCount > 0 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var summaries: [DiscoverySummaryRow] {
        guard let project = store.project(id: projectID) else { return [] }
        return Dictionary(grouping: project.keywords) { "\($0.store)|\($0.genre)" }
            .values
            .compactMap { records in
                guard let first = records.first else { return nil }
                return DiscoverySummaryRow(
                    store: first.store.uppercased(),
                    genre: first.genre,
                    keywordCount: records.count,
                    topPopularity: records.map(\.popularity).max() ?? 0
                )
            }
            .sorted {
                if $0.store != $1.store { return $0.store < $1.store }
                return $0.genre < $1.genre
            }
    }
}
