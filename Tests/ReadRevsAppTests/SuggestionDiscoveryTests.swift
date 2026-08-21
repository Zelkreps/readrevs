import ReadRevsCore
import CryptoKit
import Foundation
import Testing
@testable import ReadRevsApp

@Test("Research presets are not limited by a third-party popularity catalog")
func researchPresetsExposeTheFullConfiguredStorefrontList() {
    #expect(ResearchPresets.target(for: "af") == StoreTarget(language: "fa", store: "af"))
    #expect(ResearchPresets.target(for: "fj") == StoreTarget(language: "en", store: "fj"))
    #expect(ResearchPresets.target(for: "zw") == StoreTarget(language: "en", store: "zw"))
}

@Test("Replacing related suggestions only replaces Apple hints for the selected locale")
@MainActor
func replacingRelatedSuggestionsKeepsOtherSourcesAndStores() throws {
    let project = ResearchProject(
        name: "Habit Tracker",
        topic: "music",
        targets: [
            StoreTarget(language: "cs", store: "cz"),
            StoreTarget(language: "en", store: "us"),
        ],
        genres: [],
        seedKeywords: ["metronom"],
        keywords: [
            suggestionRecord("old cz", language: "cs", store: "cz", source: .appleSearchHints),
            suggestionRecord("old us", language: "en", store: "us", source: .appleSearchHints),
            suggestionRecord("generic popular", language: "cs", store: "cz", source: .legacyPopularity),
        ]
    )
    let store = try suggestionTestStore(project: project)

    store.replaceRelatedSuggestions(
        [suggestionRecord("metronom zdarma", language: "cs", store: "cz", source: .appleSearchHints)],
        target: StoreTarget(language: "cs", store: "cz"),
        into: project.id
    )

    let keywords = try #require(store.project(id: project.id)?.keywords)
    #expect(!keywords.contains { $0.keyword == "old cz" })
    #expect(keywords.contains { $0.keyword == "metronom zdarma" })
    #expect(keywords.contains { $0.keyword == "old us" })
    #expect(keywords.contains { $0.keyword == "generic popular" })
}

@Test("Related suggestion discovery keeps Apple hints available without Apple Ads")
@MainActor
func relatedSuggestionDiscoveryUsesSeedsAndReturnsKeywordsForRanking() async throws {
    let target = StoreTarget(language: "cs", store: "cz")
    let project = ResearchProject(
        name: "Habit Tracker",
        topic: "music",
        targets: [target],
        genres: [],
        seedKeywords: ["metronom"]
    )
    let store = try suggestionTestStore(project: project)
    let controller = DiscoveryController(
        hintsClient: StubSearchHintsProvider(),
        appleAdsCredentialStore: SuggestionCredentialStore(credentials: nil)
    )
    var rankingKeywords: [String] = []

    controller.startSuggestions(
        project: project,
        target: target,
        seeds: ["metronom"],
        store: store,
        onReady: { rankingKeywords = $0 }
    )

    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let keywords = try #require(store.project(id: project.id)?.keywords)
    let related = try #require(keywords.first {
        $0.keyword == "metronom zdarma" && $0.source == .appleSearchHints
    })
    #expect(related.matchedTerms == ["metronom"])
    #expect(!related.hasPopularityMeasurement)
    #expect(!keywords.contains { $0.keyword == "metronom" && $0.source == .appleSearchHints })
    #expect(rankingKeywords == ["metronom zdarma", "guitar metronom"])
    #expect(controller.statusText?.contains("Connect Apple Ads") == true)
}

@Test("Search more appends unique related suggestions")
@MainActor
func relatedSuggestionSearchMorePreservesExistingResults() async throws {
    let target = StoreTarget(language: "cs", store: "cz")
    let project = ResearchProject(
        name: "Habit Tracker",
        topic: "music",
        targets: [target],
        genres: [],
        seedKeywords: ["metronom"],
        keywords: [
            suggestionRecord(
                "metronom zdarma",
                language: "cs",
                store: "cz",
                source: .appleSearchHints
            ),
        ]
    )
    let store = try suggestionTestStore(project: project)
    let controller = DiscoveryController(
        hintsClient: FixedSearchHintsProvider(terms: [
            "metronom zdarma",
            "tempo trainer",
        ]),
        appleAdsCredentialStore: SuggestionCredentialStore(credentials: nil)
    )
    var rankingKeywords: [String] = []

    controller.startSuggestions(
        project: project,
        target: target,
        seeds: ["metronom zdarma"],
        store: store,
        appendsResults: true,
        onReady: { rankingKeywords = $0 }
    )

    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let keywords = try #require(store.project(id: project.id)?.keywords)
    #expect(keywords.filter { $0.keyword == "metronom zdarma" }.count == 1)
    #expect(keywords.contains { $0.keyword == "tempo trainer" })
    #expect(rankingKeywords == ["tempo trainer"])
}

@Test("Connected Apple Ads keeps suggestion scores separate from report popularity")
@MainActor
func relatedSuggestionDiscoverySeparatesSuggestionScoreAndPopularity() async throws {
    let target = StoreTarget(language: "en", store: "us")
    let project = ResearchProject(
        name: "Example App",
        topic: "geography quiz",
        targets: [target],
        genres: ["Education"],
        seedKeywords: ["flags"],
        focusAppAdamID: 1_234_567_890
    )
    let store = try suggestionTestStore(project: project)
    let hints = RecordingSearchHintsProvider()
    let appleAds = SuggestionAppleAdsClient(
        suggestions: [
            AppleAdsKeywordSuggestion(text: "world flags", popularity: 84),
            AppleAdsKeywordSuggestion(text: "geography quiz", popularity: 76),
        ],
        reports: [
            AppleAdsSearchTermPopularity(
                period: "2026-08-09",
                countryOrRegion: "US",
                genre: "EDUCATION",
                searchTerm: "world flags",
                rankInGenre: 7,
                popularityInGenre: 70,
                popularity: 61,
                popularityTier: 4
            ),
            AppleAdsSearchTermPopularity(
                period: "2026-08-09",
                countryOrRegion: "US",
                genre: "EDUCATION",
                searchTerm: "geography quiz",
                rankInGenre: 11,
                popularityInGenre: 64,
                popularity: 58,
                popularityTier: 3
            ),
        ]
    )
    let controller = DiscoveryController(
        hintsClient: hints,
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SuggestionCredentialStore(
            credentials: connectedSuggestionCredentials()
        )
    )
    var rankingKeywords: [String] = []

    controller.startSuggestions(
        project: project,
        target: target,
        seeds: ["flags"],
        store: store,
        onReady: { rankingKeywords = $0 }
    )

    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let keywords = try #require(store.project(id: project.id)?.keywords)
    let worldFlagsSuggestion = try #require(keywords.first {
        $0.keyword == "world flags" && $0.isAppleAdsSuggestion
    })
    let worldFlagsPopularity = try #require(keywords.first {
        $0.keyword == "world flags" && $0.hasPopularityMeasurement
    })
    #expect(worldFlagsSuggestion.popularity == 0)
    #expect(worldFlagsSuggestion.suggestionScore == 84)
    #expect(!worldFlagsSuggestion.hasPopularityMeasurement)
    #expect(worldFlagsSuggestion.matchedTerms == ["flags"])
    #expect(worldFlagsPopularity.popularity == 61)
    #expect(worldFlagsPopularity.suggestionScore == nil)
    #expect(rankingKeywords == ["world flags", "geography quiz"])
    #expect(await appleAds.suggestionRequests == [
        SuggestionAppleAdsClient.SuggestionRequest(
            terms: ["flags"],
            promotedObjectID: 555_000_111,
            store: "us"
        ),
    ])
    #expect(await appleAds.reportRequests == ["us|Education"])
    #expect(await hints.seeds.isEmpty)
    #expect(controller.statusText == "Found 2 related suggestions.")
}

@Test("Suggestion fallback enriches hints from the Apple genre report after app access is denied")
@MainActor
func relatedSuggestionFallbackUsesAppleGenreReport() async throws {
    let target = StoreTarget(language: "en", store: "us")
    let project = ResearchProject(
        name: "Tower Research",
        topic: "idle tower defense",
        targets: [target],
        genres: ["Games"],
        seedKeywords: ["idle"],
        focusAppAdamID: 555_000_333
    )
    let store = try suggestionTestStore(project: project)
    let appleAds = SuggestionAppleAdsClient(
        reports: [
            AppleAdsSearchTermPopularity(
                period: "2026-08-02",
                countryOrRegion: "US",
                genre: "GAMES",
                searchTerm: "idle games",
                rankInGenre: 203,
                popularityInGenre: 71,
                popularity: 61,
                popularityTier: 4
            ),
        ],
        suggestionError: .httpStatus(
            400,
            "App not found or access denied for adamId: 555000333"
        )
    )
    let controller = DiscoveryController(
        hintsClient: FixedSearchHintsProvider(terms: [
            "idle games",
            "tower defense",
            "long tail term",
        ]),
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SuggestionCredentialStore(
            credentials: connectedSuggestionCredentials()
        )
    )
    var suggestions: [String] = []

    controller.startSuggestions(
        project: project,
        target: target,
        seeds: ["idle"],
        store: store,
        onReady: { suggestions = $0 }
    )

    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let records = try #require(store.project(id: project.id)?.keywords)
    let appleMetric = try #require(
        records.first { $0.keyword == "idle games" && $0.source == .appleAds }
    )
    let unmatchedHint = try #require(
        records.first { $0.keyword == "tower defense" && $0.source == .appleSearchHints }
    )
    #expect(appleMetric.popularity == 61)
    #expect(!unmatchedHint.hasPopularityMeasurement)
    #expect(suggestions == ["idle games", "tower defense", "long tail term"])
    #expect(await appleAds.reportRequests == ["us|Games"])
    #expect(await appleAds.suggestionRequests.map(\.terms) == [["idle"]])
    #expect(controller.statusText?.contains("2 without popularity") == true)
    #expect(controller.statusText?.contains("selected research app") == true)
}

@Test("An empty Apple Ads suggestion result leaves missing report rows unavailable")
@MainActor
func emptyInitialAppleSuggestionsUseHintsWithoutSuggestionFallback() async throws {
    let target = StoreTarget(language: "en", store: "us")
    let project = ResearchProject(
        name: "Example App",
        topic: "geography quiz",
        targets: [target],
        genres: ["Education"],
        seedKeywords: ["flags"],
        focusAppAdamID: 1_234_567_890
    )
    let store = try suggestionTestStore(project: project)
    let appleAds = SuggestionAppleAdsClient(
        suggestionResponses: [[]]
    )
    let controller = DiscoveryController(
        hintsClient: FixedSearchHintsProvider(terms: ["world flags"]),
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SuggestionCredentialStore(
            credentials: connectedSuggestionCredentials()
        )
    )

    controller.startSuggestions(
        project: project,
        target: target,
        seeds: ["flags"],
        store: store,
        onReady: { _ in }
    )

    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let records = try #require(store.project(id: project.id)?.keywords)
    let hint = try #require(records.first {
        $0.keyword == "world flags" && $0.source == .appleSearchHints
    })
    #expect(!hint.hasPopularityMeasurement)
    #expect(hint.suggestionScore == nil)
    #expect(await appleAds.suggestionRequests.map(\.terms) == [["flags"]])
    #expect(await appleAds.reportRequests == ["us|Education"])
}

@Test("Connected Apple Ads discovery stores official weekly popularity")
@MainActor
func popularityDiscoveryPrefersConnectedAppleAdsReport() async throws {
    let target = StoreTarget(language: "en", store: "us")
    let project = ResearchProject(
        name: "Example App",
        topic: "geography quiz",
        targets: [target],
        genres: ["Education"],
        seedKeywords: ["flags"]
    )
    let store = try suggestionTestStore(project: project)
    let appleAds = SuggestionAppleAdsClient(
        reports: [
            AppleAdsSearchTermPopularity(
                period: "2026-08-09",
                countryOrRegion: "US",
                genre: "EDUCATION",
                searchTerm: "world flags",
                rankInGenre: 7,
                popularityInGenre: 90,
                popularity: 81,
                popularityTier: 5
            ),
        ]
    )
    let controller = DiscoveryController(
        hintsClient: RecordingSearchHintsProvider(),
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SuggestionCredentialStore(
            credentials: connectedSuggestionCredentials()
        )
    )

    controller.start(project: project, minimumPopularity: 25, store: store)

    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let record = try #require(store.project(id: project.id)?.keywords.first)
    #expect(record.keyword == "world flags")
    #expect(record.popularity == 81)
    #expect(record.source == .appleAds)
    #expect(record.month == "2026-08-09")
    #expect(await appleAds.reportRequests == ["us|Education"])
    #expect(controller.statusText == "Apple Ads popularity updated.")
}

@Test("Empty Apple Ads popularity reports remain empty without a third-party fallback")
@MainActor
func emptyAppleAdsPopularityReportRemainsEmpty() async throws {
    let target = StoreTarget(language: "en", store: "us")
    let project = ResearchProject(
        name: "Example App",
        topic: "geography quiz",
        targets: [target],
        genres: ["Education"],
        seedKeywords: ["flags"]
    )
    let store = try suggestionTestStore(project: project)
    let appleAds = SuggestionAppleAdsClient()
    let controller = DiscoveryController(
        hintsClient: RecordingSearchHintsProvider(),
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SuggestionCredentialStore(
            credentials: connectedSuggestionCredentials()
        )
    )

    controller.start(project: project, minimumPopularity: 25, store: store)

    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(store.project(id: project.id)?.keywords.isEmpty == true)
    #expect(await appleAds.reportRequests == ["us|Education"])
    #expect(controller.statusText == "Apple Ads popularity updated.")
}

@Test("Manual popularity lookup leaves a term unavailable when the report has no row")
@MainActor
func manualPopularityLookupDoesNotUseMatchingSuggestionScore() async throws {
    let target = StoreTarget(language: "en", store: "us")
    let project = ResearchProject(
        name: "Example App",
        topic: "geography",
        targets: [target],
        genres: ["Education"],
        seedKeywords: ["flags"],
        focusAppAdamID: 1_234_567_890,
        keywords: [trackedKeyword("flags", target: target)]
    )
    let store = try suggestionTestStore(project: project)
    let appleAds = SuggestionAppleAdsClient(
        suggestions: [AppleAdsKeywordSuggestion(text: "flags", popularity: 79)]
    )
    let controller = DiscoveryController(
        hintsClient: RecordingSearchHintsProvider(),
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SuggestionCredentialStore(
            credentials: connectedSuggestionCredentials()
        )
    )

    controller.startPopularityLookup(
        project: project,
        keywords: ["flags"],
        target: target,
        store: store
    )

    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let record = try #require(store.project(id: project.id)?.keywords.first {
        $0.keyword == "flags"
    })
    #expect(record.keyword == "flags")
    #expect(!record.hasPopularityMeasurement)
    #expect(await appleAds.reportRequests == ["us|Education"])
    #expect(await appleAds.suggestionRequests.isEmpty)
    #expect(controller.statusText == "Popularity unavailable for 1 keyword.")
}

@Test("Popularity lookup requires a genre instead of reinterpreting a suggestion score")
@MainActor
func popularityLookupWithoutGenreExplainsTheMissingDimension() async throws {
    let target = StoreTarget(language: "en", store: "us")
    let project = ResearchProject(
        name: "Example App",
        topic: "geography",
        targets: [target],
        genres: [],
        seedKeywords: ["flags"],
        keywords: [trackedKeyword("flags", target: target)]
    )
    let store = try suggestionTestStore(project: project)
    let appleAds = SuggestionAppleAdsClient(
        suggestions: [AppleAdsKeywordSuggestion(text: "flags", popularity: 79)]
    )
    let controller = DiscoveryController(
        hintsClient: RecordingSearchHintsProvider(),
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SuggestionCredentialStore(
            credentials: connectedSuggestionCredentials()
        )
    )

    controller.startPopularityLookup(
        project: project,
        keywords: ["flags"],
        target: target,
        store: store
    )

    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(controller.statusText == "Select at least one genre to fetch storefront popularity.")
    #expect(await appleAds.reportRequests.isEmpty)
    #expect(await appleAds.suggestionRequests.isEmpty)
}

@Test("Manual popularity lookup keeps genre report data and leaves unmatched terms unavailable")
@MainActor
func manualPopularityLookupUsesGenreReportBeforeFallback() async throws {
    let target = StoreTarget(language: "en", store: "us")
    let project = ResearchProject(
        name: "Tower Research",
        topic: "idle tower defense",
        targets: [target],
        genres: ["Games"],
        seedKeywords: ["idle"],
        focusAppAdamID: 555_000_333,
        keywords: [
            trackedKeyword("idle", target: target),
            trackedKeyword("tower", target: target),
            trackedKeyword("long tail term", target: target),
        ]
    )
    let store = try suggestionTestStore(project: project)
    let appleAds = SuggestionAppleAdsClient(
        reports: [
            AppleAdsSearchTermPopularity(
                period: "2026-08-02",
                countryOrRegion: "US",
                genre: "GAMES",
                searchTerm: "idle",
                rankInGenre: 120,
                popularityInGenre: 70,
                popularity: 61,
                popularityTier: 3
            ),
        ],
        suggestionError: .httpStatus(
            400,
            "App not found or access denied for adamId: 555000333"
        )
    )
    let controller = DiscoveryController(
        hintsClient: RecordingSearchHintsProvider(),
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SuggestionCredentialStore(
            credentials: connectedSuggestionCredentials()
        )
    )

    controller.startPopularityLookup(
        project: project,
        keywords: ["idle", "tower", "long tail term"],
        target: target,
        store: store
    )

    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let records = try #require(store.project(id: project.id)?.keywords)
    let idle = try #require(records.first { $0.keyword == "idle" && $0.source == .appleAds })
    let tower = try #require(records.first { $0.keyword == "tower" && $0.source == .manual })
    #expect(idle.popularity == 61)
    #expect(idle.intentTags.contains("apple-ads-popularity"))
    #expect(!idle.intentTags.contains("apple-ads-exact"))
    #expect(!tower.hasPopularityMeasurement)
    #expect(await appleAds.reportRequests == ["us|Games"])
    #expect(await appleAds.suggestionRequests.isEmpty)
    #expect(controller.statusText?.contains("1 of 3 keywords") == true)
    #expect(controller.statusText?.contains("selected research app") == false)
    #expect(controller.statusText?.contains("Apple Ads was unavailable") == false)
}

@Test("Popularity lookup without Apple Ads leaves the keyword unchecked")
@MainActor
func failedPopularityLookupDoesNotMarkKeywordChecked() async throws {
    let target = StoreTarget(language: "en", store: "us")
    let project = ResearchProject(
        name: "Example App",
        topic: "geography",
        targets: [target],
        genres: ["Education"],
        seedKeywords: ["flags"],
        keywords: [trackedKeyword("world flags", target: target)]
    )
    let store = try suggestionTestStore(project: project)
    let controller = DiscoveryController(
        hintsClient: RecordingSearchHintsProvider(),
        appleAdsClient: SuggestionAppleAdsClient(),
        appleAdsCredentialStore: SuggestionCredentialStore(credentials: nil)
    )

    controller.startPopularityLookup(
        project: project,
        keywords: ["world flags"],
        target: target,
        store: store
    )

    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let record = try #require(
        store.project(id: project.id)?.keywords.first { $0.keyword == "world flags" }
    )
    #expect(record.popularityCheckedAt == nil)
    #expect(controller.statusText == "Connect Apple Ads to fetch popularity.")
}

@MainActor
private func suggestionTestStore(project: ResearchProject) throws -> LibraryStore {
    let fileURL = URL(fileURLWithPath: "/private/tmp/aso-suggestion-tests-\(UUID().uuidString)/library.json")
    let persistence = LibraryPersistence(fileURL: fileURL)
    try persistence.save(ASOLibrary(projects: [project]))
    return LibraryStore(persistence: persistence)
}

private func suggestionRecord(
    _ keyword: String,
    language: String,
    store: String,
    source: KeywordSource
) -> KeywordRecord {
    KeywordRecord(
        keyword: keyword,
        language: language,
        store: store,
        genre: "Suggestions",
        popularity: 0,
        source: source,
        isTracked: false
    )
}

private func trackedKeyword(_ keyword: String, target: StoreTarget) -> KeywordRecord {
    KeywordRecord(
        keyword: keyword,
        language: target.language,
        store: target.store,
        genre: "Tracked",
        popularity: 0,
        source: .manual,
        isTracked: true
    )
}

private struct StubSearchHintsProvider: AppStoreSearchHintsProviding {
    func fetch(seed: String, target: StoreTarget) async throws -> [AppStoreSearchHint] {
        [
            AppStoreSearchHint(term: "metronom"),
            AppStoreSearchHint(term: "metronom zdarma"),
            AppStoreSearchHint(term: "guitar metronom"),
        ]
    }
}

private struct FixedSearchHintsProvider: AppStoreSearchHintsProviding {
    let terms: [String]

    func fetch(seed: String, target: StoreTarget) async throws -> [AppStoreSearchHint] {
        terms.map(AppStoreSearchHint.init(term:))
    }
}

private actor RecordingSearchHintsProvider: AppStoreSearchHintsProviding {
    private(set) var seeds: [String] = []

    func fetch(seed: String, target: StoreTarget) async throws -> [AppStoreSearchHint] {
        seeds.append(seed)
        return []
    }
}

private final class SuggestionCredentialStore: AppleAdsCredentialStoring, @unchecked Sendable {
    private var credentials: AppleAdsCredentials?

    init(credentials: AppleAdsCredentials?) {
        self.credentials = credentials
    }

    func load() throws -> AppleAdsCredentials? { credentials }
    func save(_ credentials: AppleAdsCredentials) throws { self.credentials = credentials }
    func delete() throws { credentials = nil }
}

private actor SuggestionAppleAdsClient: AppleAdsPlatformProviding {
    struct SuggestionRequest: Equatable, Sendable {
        let terms: [String]
        let promotedObjectID: Int64
        let store: String
    }

    private let suggestions: [AppleAdsKeywordSuggestion]
    private let suggestionResponses: [[AppleAdsKeywordSuggestion]]?
    private let reports: [AppleAdsSearchTermPopularity]
    private let suggestionError: AppleAdsPlatformError?
    private(set) var suggestionRequests: [SuggestionRequest] = []
    private(set) var reportRequests: [String] = []

    init(
        suggestions: [AppleAdsKeywordSuggestion] = [],
        suggestionResponses: [[AppleAdsKeywordSuggestion]]? = nil,
        reports: [AppleAdsSearchTermPopularity] = [],
        suggestionError: AppleAdsPlatformError? = nil
    ) {
        self.suggestions = suggestions
        self.suggestionResponses = suggestionResponses
        self.reports = reports
        self.suggestionError = suggestionError
    }

    func fetchAccounts(credentials: AppleAdsCredentials) async throws -> [AppleAdsAccountAccess] {
        []
    }

    func fetchKeywordSuggestions(
        terms: [String],
        promotedObjectID: Int64,
        target: StoreTarget,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsKeywordSuggestion] {
        let responseIndex = suggestionRequests.count
        suggestionRequests.append(
            SuggestionRequest(
                terms: terms,
                promotedObjectID: promotedObjectID,
                store: target.store
            )
        )
        if let suggestionError {
            throw suggestionError
        }
        if let suggestionResponses, responseIndex < suggestionResponses.count {
            return suggestionResponses[responseIndex]
        }
        return suggestions
    }

    func fetchSearchTermPopularity(
        target: StoreTarget,
        genre: String,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsSearchTermPopularity] {
        reportRequests.append("\(target.store)|\(genre)")
        return reports
    }
}

private func connectedSuggestionCredentials() -> AppleAdsCredentials {
    let privateKey = try! P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 4, count: 32))
    return AppleAdsCredentials(
        clientID: "SEARCHADS.client",
        teamID: "SEARCHADS.team",
        keyID: "key-id",
        privateKeyRawRepresentation: privateKey.rawRepresentation,
        adAccountID: 42,
        adAccountName: "Example Ads",
        researchAppAdamID: 555_000_111,
        researchAppName: "Example Flashcards"
    )
}
