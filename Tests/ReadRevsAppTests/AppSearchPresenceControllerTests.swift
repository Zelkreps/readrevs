import ReadRevsCore
import CryptoKit
import Foundation
import Testing
@testable import ReadRevsApp

@Test("Automatic search presence persists hints and leaves popularity unavailable without Apple Ads")
@MainActor
func appSearchPresenceControllerPersistsAndEnrichesCandidates() async throws {
    let app = controllerTestApp()
    let store = try controllerTestStore(app: app)
    let existingProject = try #require(store.ensureAppSearchPresenceProject(for: app))
    let rankingScanner = RecordingSearchPresenceRankingScanner()
    let now = Date(timeIntervalSinceReferenceDate: 5_000)
    store.mergeKeywords(
        [
            KeywordRecord(
                keyword: "stale category term",
                language: "en",
                store: "us",
                genre: "Apple Search Suggestions",
                popularity: 0,
                source: .appleSearchHints,
                isTracked: false,
                updatedAt: now.addingTimeInterval(-100)
            ),
        ],
        into: existingProject.id
    )
    store.mergeRankingData(
        observations: [],
        scan: RankingScan(
            projectID: existingProject.id,
            keyword: "stale category term",
            store: "us",
            checkedAt: now.addingTimeInterval(-100),
            resultCount: 100
        ),
        into: existingProject.id
    )
    let controller = AppSearchPresenceController(
        hintsProvider: ManySearchHintsProvider(),
        rankingScanner: rankingScanner,
        maximumKeywordCount: 20,
        now: { now }
    )

    controller.refresh(app: app, store: store, force: true)
    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let project = try #require(store.appSearchPresenceProject(for: app.adamID))
    let hints = project.keywords.filter { $0.source == .appleSearchHints }
    let rows = store.searchPresenceRows(for: app.adamID, store: "us")
    let request = try #require(rankingScanner.requests.first)

    #expect(hints.count == 14)
    #expect(hints.allSatisfy { $0.updatedAt == now })
    #expect(rows.first { $0.keyword == "quiz suggestion 1" }?.popularity == nil)
    #expect(rows.first { $0.keyword == "quiz suggestion 2" }?.popularity == nil)
    #expect(controller.statusText?.contains("Connect Apple Ads") == true)
    #expect(request.projectID == project.id)
    #expect(request.store == "us")
    #expect(request.keywords.count == 20)
    #expect(request.keywords.first == app.name)
    #expect(Set(request.keywords).count == request.keywords.count)
    #expect(!rows.contains { $0.keyword == "stale category term" })
    #expect(!project.rankingScans.contains { $0.keyword == "stale category term" })
}

@Test("Search more expands search presence from previously discovered terms")
@MainActor
func appSearchPresenceSearchMoreAddsOnlyNewCandidates() async throws {
    let app = controllerTestApp()
    let store = try controllerTestStore(app: app)
    let rankingScanner = RecordingSearchPresenceRankingScanner()
    let controller = AppSearchPresenceController(
        hintsProvider: LayeredSearchHintsProvider(),
        appleAdsCredentialStore: SearchPresenceCredentialStore(credentials: nil),
        rankingScanner: rankingScanner,
        maximumKeywordCount: 8,
        searchMoreBatchSize: 2,
        maximumExpandedKeywordCount: 12,
        now: { Date(timeIntervalSinceReferenceDate: 50_000) }
    )

    controller.refresh(app: app, store: store, force: true)
    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let initialProject = try #require(store.appSearchPresenceProject(for: app.adamID))
    #expect(initialProject.keywords.contains { $0.keyword == "quiz expansion" })
    #expect(initialProject.keywords.contains { $0.keyword == "flashcard practice" })
    #expect(rankingScanner.requests.count == 1)

    controller.searchMore(app: app, store: store)
    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let expandedProject = try #require(store.appSearchPresenceProject(for: app.adamID))
    #expect(expandedProject.keywords.contains { $0.keyword == "quiz expansion" })
    #expect(expandedProject.keywords.contains { $0.keyword == "flashcard practice" })
    #expect(expandedProject.keywords.contains { $0.keyword == "quiz expansion advanced" })
    #expect(expandedProject.keywords.contains { $0.keyword == "flashcard practice timer" })
    #expect(rankingScanner.requests.count == 2)
    #expect(Set(rankingScanner.requests[1].keywords) == [
        "quiz expansion advanced",
        "flashcard practice timer",
    ])

    controller.refresh(app: app, store: store)
    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let reopenedProject = try #require(store.appSearchPresenceProject(for: app.adamID))
    #expect(reopenedProject.keywords.contains { $0.keyword == "quiz expansion advanced" })
    #expect(reopenedProject.keywords.contains { $0.keyword == "flashcard practice timer" })
}

@Test("Fresh hints and scans are reused for twenty-four hours")
@MainActor
func appSearchPresenceControllerReusesFreshData() async throws {
    let app = controllerTestApp()
    let store = try controllerTestStore(app: app)
    let now = Date(timeIntervalSinceReferenceDate: 100_000)
    let freshDate = now.addingTimeInterval(-(23 * 60 * 60))
    let project = try #require(store.ensureAppSearchPresenceProject(for: app, now: freshDate))
    let target = try #require(project.targets.first)
    store.replaceRelatedSuggestions(
        [
            KeywordRecord(
                keyword: "quiz suggestion 1",
                language: target.language,
                store: target.store,
                genre: "Apple Search Suggestions",
                popularity: 0,
                source: .appleSearchHints,
                isTracked: false,
                updatedAt: freshDate
            ),
        ],
        target: target,
        into: project.id
    )
    for keyword in [
        app.name,
        "Example Study",
        "Flashcards Quiz",
        "Flashcards",
        "Quiz",
        "quiz suggestion 1",
        app.primaryGenre,
    ] {
        store.mergeRankingData(
            observations: [],
            scan: RankingScan(
                projectID: project.id,
                keyword: keyword,
                store: target.store,
                checkedAt: freshDate,
                resultCount: 100
            ),
            into: project.id
        )
    }

    let hintCounter = SearchHintsCallCounter()
    let rankingScanner = RecordingSearchPresenceRankingScanner()
    let controller = AppSearchPresenceController(
        hintsProvider: CountingSearchHintsProvider(counter: hintCounter),
        rankingScanner: rankingScanner,
        maximumKeywordCount: 20,
        now: { now }
    )

    controller.refresh(app: app, store: store)
    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(await hintCounter.value == 0)
    #expect(rankingScanner.requests.isEmpty)
    #expect(controller.statusText?.hasPrefix("Search presence is up to date.") == true)
    #expect(controller.statusText?.contains("Connect Apple Ads to fetch popularity") == true)
}

@Test("Connected search presence uses app-aware Apple Ads suggestions and popularity")
@MainActor
func appSearchPresenceControllerUsesConnectedAppleAds() async throws {
    let app = controllerTestApp()
    let store = try controllerTestStore(app: app)
    let hints = SearchPresenceHintsRecorder()
    let appleAds = SearchPresenceAppleAdsClient(
        suggestions: [
            AppleAdsKeywordSuggestion(text: "quiz maker", popularity: 86),
            AppleAdsKeywordSuggestion(text: "flashcards app", popularity: 73),
        ]
    )
    let rankingScanner = RecordingSearchPresenceRankingScanner()
    let controller = AppSearchPresenceController(
        hintsProvider: hints,
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SearchPresenceCredentialStore(
            credentials: connectedSearchPresenceCredentials()
        ),
        rankingScanner: rankingScanner,
        now: { Date(timeIntervalSinceReferenceDate: 200_000) }
    )

    controller.refresh(app: app, store: store, force: true)
    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let project = try #require(store.appSearchPresenceProject(for: app.adamID))
    let direct = project.keywords.filter {
        $0.source == .appleAds && $0.intentTags.contains("apple-ads-suggestion")
    }
    #expect(Set(direct.map(\.keyword)) == ["flashcards app", "quiz maker"])
    #expect(Set(direct.map(\.popularity)) == [73, 86])
    #expect(Set(await hints.seeds) == [
        "Example Study: Flashcards & Quiz",
        "Example Study",
        "Flashcards Quiz",
        "Flashcards",
        "Quiz",
    ])
    #expect(await appleAds.promotedObjectIDs.allSatisfy { $0 == 555_000_111 })
    #expect(rankingScanner.requests.first?.keywords.contains("quiz maker") == true)
    #expect(controller.statusText?.contains("Popularity found for 2 of") == true)
}

@Test("Connected search presence supplements Apple Ads with localized search hints")
@MainActor
func appSearchPresenceControllerCombinesSuggestionSources() async throws {
    let app = controllerTestApp()
    let store = try controllerTestStore(app: app)
    let hints = SupplementalSearchHintsRecorder()
    let appleAds = SearchPresenceAppleAdsClient(
        suggestions: [
            AppleAdsKeywordSuggestion(text: "quiz maker", popularity: 86),
        ]
    )
    let rankingScanner = RecordingSearchPresenceRankingScanner()
    let controller = AppSearchPresenceController(
        hintsProvider: hints,
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SearchPresenceCredentialStore(
            credentials: connectedSearchPresenceCredentials()
        ),
        rankingScanner: rankingScanner,
        maximumKeywordCount: 12,
        now: { Date(timeIntervalSinceReferenceDate: 250_000) }
    )

    controller.refresh(app: app, store: store, force: true)
    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let project = try #require(store.appSearchPresenceProject(for: app.adamID))
    let localizedHints = project.keywords.filter { $0.source == .appleSearchHints }
    let requestedSeeds = await hints.seeds
    let request = try #require(rankingScanner.requests.first)

    #expect(localizedHints.count == 5)
    #expect(project.keywords.contains {
        $0.keyword == "quiz maker" && $0.source == .appleAds
    })
    #expect(Set(requestedSeeds) == [
        "Example Study: Flashcards & Quiz",
        "Example Study",
        "Flashcards Quiz",
        "Flashcards",
        "Quiz",
    ])
    #expect(!requestedSeeds.contains("Education"))
    #expect(request.keywords.count == 12)
}

@Test("Apple Ads suggestions survive a complete localized-hint failure")
@MainActor
func appSearchPresenceControllerKeepsAppleAdsWhenHintsFail() async throws {
    let app = controllerTestApp()
    let store = try controllerTestStore(app: app)
    let appleAds = SearchPresenceAppleAdsClient(
        suggestions: [
            AppleAdsKeywordSuggestion(text: "quiz maker", popularity: 86),
        ]
    )
    let rankingScanner = RecordingSearchPresenceRankingScanner()
    let controller = AppSearchPresenceController(
        hintsProvider: ThrowingSupplementalSearchHintsProvider(),
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SearchPresenceCredentialStore(
            credentials: connectedSearchPresenceCredentials()
        ),
        rankingScanner: rankingScanner,
        maximumKeywordCount: 12,
        now: { Date(timeIntervalSinceReferenceDate: 275_000) }
    )

    controller.refresh(app: app, store: store, force: true)
    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let project = try #require(store.appSearchPresenceProject(for: app.adamID))
    #expect(project.keywords.contains {
        $0.keyword == "quiz maker" && $0.source == .appleAds
    })
    #expect(rankingScanner.requests.first?.keywords.contains("quiz maker") == true)
}

@Test("Search presence keeps Apple genre popularity when research-app suggestions are denied")
@MainActor
func appSearchPresenceControllerFallsBackToAppleGenreReport() async throws {
    let app = controllerTestApp()
    let store = try controllerTestStore(app: app)
    let appleAds = SearchPresenceAppleAdsClient(
        reports: [
            AppleAdsSearchTermPopularity(
                period: "2026-08-02",
                countryOrRegion: "US",
                genre: "EDUCATION",
                searchTerm: "quiz suggestion 1",
                rankInGenre: 200,
                popularityInGenre: 70,
                popularity: 64,
                popularityTier: 4
            ),
        ],
        suggestionError: .httpStatus(
            400,
            "App not found or access denied for adamId: 42"
        )
    )
    let rankingScanner = RecordingSearchPresenceRankingScanner()
    let controller = AppSearchPresenceController(
        hintsProvider: ManySearchHintsProvider(),
        appleAdsClient: appleAds,
        appleAdsCredentialStore: SearchPresenceCredentialStore(
            credentials: connectedSearchPresenceCredentials()
        ),
        rankingScanner: rankingScanner,
        now: { Date(timeIntervalSinceReferenceDate: 300_000) }
    )

    controller.refresh(app: app, store: store, force: true)
    while controller.isRunning {
        try await Task.sleep(for: .milliseconds(10))
    }

    let project = try #require(store.appSearchPresenceProject(for: app.adamID))
    let appleMetric = try #require(project.keywords.first {
        $0.keyword == "quiz suggestion 1" && $0.source == .appleAds
    })
    #expect(appleMetric.popularity == 64)
    #expect(await appleAds.promotedObjectIDs.allSatisfy { $0 == 555_000_111 })
    #expect(await appleAds.reportRequests == ["us|Education"])
    #expect(controller.statusText?.contains("selected research app") == true)
    #expect(controller.statusText?.contains("Apple Ads was unavailable") == false)
}

@MainActor
private final class RecordingSearchPresenceRankingScanner: AppSearchPresenceRankingScanning {
    struct Request {
        let projectID: UUID
        let keywords: [String]
        let store: String
    }

    private(set) var requests: [Request] = []
    var isRunning = false
    var completed = 0
    var total = 0
    var failureCount = 0
    var statusText: String?

    func start(
        project: ResearchProject,
        keywords: [String],
        storeCode: String,
        store: LibraryStore,
        prioritize: Bool
    ) {
        requests.append(Request(projectID: project.id, keywords: keywords, store: storeCode))
        total = keywords.count
        completed = keywords.count
    }

    func cancel() {
        isRunning = false
    }
}

private struct ManySearchHintsProvider: AppStoreSearchHintsProviding {
    func fetch(seed: String, target: StoreTarget) async throws -> [AppStoreSearchHint] {
        (1...25).map { AppStoreSearchHint(term: "quiz suggestion \($0)") }
    }
}

private struct LayeredSearchHintsProvider: AppStoreSearchHintsProviding {
    func fetch(seed: String, target: StoreTarget) async throws -> [AppStoreSearchHint] {
        switch seed {
        case "quiz expansion":
            [AppStoreSearchHint(term: "quiz expansion advanced")]
        case "flashcard practice":
            [AppStoreSearchHint(term: "flashcard practice timer")]
        default:
            [
                AppStoreSearchHint(term: "quiz expansion"),
                AppStoreSearchHint(term: "flashcard practice"),
            ]
        }
    }
}

private actor SearchHintsCallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct CountingSearchHintsProvider: AppStoreSearchHintsProviding {
    let counter: SearchHintsCallCounter

    func fetch(seed: String, target: StoreTarget) async throws -> [AppStoreSearchHint] {
        await counter.increment()
        return []
    }
}

private actor SearchPresenceHintsRecorder: AppStoreSearchHintsProviding {
    private(set) var seeds: [String] = []

    func fetch(seed: String, target: StoreTarget) async throws -> [AppStoreSearchHint] {
        seeds.append(seed)
        return []
    }
}

private actor SupplementalSearchHintsRecorder: AppStoreSearchHintsProviding {
    private(set) var seeds: [String] = []

    func fetch(seed: String, target: StoreTarget) async throws -> [AppStoreSearchHint] {
        seeds.append(seed)
        return [AppStoreSearchHint(term: "\(seed) suggestion")]
    }
}

private struct ThrowingSupplementalSearchHintsProvider: AppStoreSearchHintsProviding {
    func fetch(seed: String, target: StoreTarget) async throws -> [AppStoreSearchHint] {
        throw ServiceError.invalidResponse
    }
}

private final class SearchPresenceCredentialStore: AppleAdsCredentialStoring, @unchecked Sendable {
    private var credentials: AppleAdsCredentials?

    init(credentials: AppleAdsCredentials?) {
        self.credentials = credentials
    }

    func load() throws -> AppleAdsCredentials? { credentials }
    func save(_ credentials: AppleAdsCredentials) throws { self.credentials = credentials }
    func delete() throws { credentials = nil }
}

private actor SearchPresenceAppleAdsClient: AppleAdsPlatformProviding {
    private let suggestions: [AppleAdsKeywordSuggestion]
    private let reports: [AppleAdsSearchTermPopularity]
    private let suggestionError: AppleAdsPlatformError?
    private(set) var promotedObjectIDs: [Int64] = []
    private(set) var reportRequests: [String] = []

    init(
        suggestions: [AppleAdsKeywordSuggestion] = [],
        reports: [AppleAdsSearchTermPopularity] = [],
        suggestionError: AppleAdsPlatformError? = nil
    ) {
        self.suggestions = suggestions
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
        promotedObjectIDs.append(promotedObjectID)
        if let suggestionError {
            throw suggestionError
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

private func connectedSearchPresenceCredentials() -> AppleAdsCredentials {
    let privateKey = try! P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 5, count: 32))
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

@MainActor
private func controllerTestStore(app: TrackedApp) throws -> LibraryStore {
    let fileURL = URL(fileURLWithPath: "/private/tmp/aso-search-presence-controller-\(UUID().uuidString)/library.json")
    let persistence = LibraryPersistence(fileURL: fileURL)
    try persistence.save(ASOLibrary(apps: [app]))
    return LibraryStore(persistence: persistence)
}

private func controllerTestApp() -> TrackedApp {
    TrackedApp(
        adamID: 42,
        name: "Example Study: Flashcards & Quiz",
        developerName: "Example Developer",
        bundleID: "com.example.exampleApp",
        primaryStore: "us",
        primaryGenre: "Education",
        kind: .owned
    )
}
