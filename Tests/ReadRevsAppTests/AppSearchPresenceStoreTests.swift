import ReadRevsCore
import Foundation
import Testing
@testable import ReadRevsApp

@Test("Internal search presence projects stay out of the sidebar")
@MainActor
func internalSearchPresenceProjectsAreHiddenFromSidebar() throws {
    let app = searchPresenceTestApp()
    let manual = searchPresenceTestProject(name: "Manual", kind: .manual)
    let internalProject = searchPresenceTestProject(
        name: "Internal",
        kind: .appSearchPresence,
        focusAppAdamID: app.adamID
    )
    let store = try searchPresenceTestStore(
        library: ASOLibrary(projects: [internalProject, manual], apps: [app])
    )

    #expect(store.sidebarProjects.map(\.id) == [manual.id])
    #expect(store.selection == .project(manual.id))
}

@Test("An internal search presence project is ensured idempotently per app")
@MainActor
func ensuringSearchPresenceProjectIsIdempotent() throws {
    let app = searchPresenceTestApp()
    let store = try searchPresenceTestStore(library: ASOLibrary(apps: [app]))
    let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)

    let first = try #require(store.ensureAppSearchPresenceProject(for: app, now: createdAt))
    let second = try #require(store.ensureAppSearchPresenceProject(for: app, now: createdAt.addingTimeInterval(60)))

    #expect(first.id == second.id)
    #expect(store.library.projects.count == 1)
    #expect(second.kind == .appSearchPresence)
    #expect(second.focusAppAdamID == app.adamID)
    #expect(second.targets == [StoreTarget(language: "en", store: "us")])
    #expect(
        second.seedKeywords == [
            app.name,
            "Example Study",
            "Flashcards Quiz",
            "Flashcards",
            "Quiz",
            app.primaryGenre,
        ]
    )
    #expect(second.createdAt == createdAt)
}

@Test("Adding an owned app creates a hidden search presence context without selecting it")
@MainActor
func addingOwnedAppEnsuresHiddenSearchPresenceProject() throws {
    let store = try searchPresenceTestStore(library: ASOLibrary())
    let app = searchPresenceTestApp()

    store.addApp(
        StoreAppSearchResult(
            adamID: app.adamID,
            name: app.name,
            developerName: app.developerName,
            bundleID: app.bundleID,
            primaryGenre: app.primaryGenre,
            appStoreURL: nil,
            position: 1
        ),
        store: app.primaryStore,
        kind: .owned
    )

    #expect(store.appSearchPresenceProject(for: app.adamID)?.kind == .appSearchPresence)
    #expect(store.sidebarProjects.isEmpty)
    #expect(store.selection == .app(app.adamID))
}

@Test("Owned app metadata refresh updates its existing search presence context")
@MainActor
func appMetadataRefreshUpdatesSearchPresenceSeedsWithoutDuplicatingProject() throws {
    let app = searchPresenceTestApp()
    let store = try searchPresenceTestStore(library: ASOLibrary(apps: [app]))
    let original = try #require(store.ensureAppSearchPresenceProject(for: app))
    let checkedAt = Date(timeIntervalSinceReferenceDate: 1_500)
    store.mergeKeywords([searchPresenceKeyword("education app")], into: original.id)
    store.mergeRankingData(
        observations: RankingIndex.observations(
            projectID: original.id,
            keyword: "education app",
            store: "us",
            results: [
                StoreAppSearchResult(
                    adamID: app.adamID,
                    name: app.name,
                    developerName: app.developerName,
                    bundleID: app.bundleID,
                    primaryGenre: app.primaryGenre,
                    appStoreURL: nil,
                    position: 1
                ),
            ],
            checkedAt: checkedAt
        ),
        scan: RankingScan(
            projectID: original.id,
            keyword: "education app",
            store: "us",
            checkedAt: checkedAt,
            resultCount: 1
        ),
        into: original.id
    )

    store.updateAppMetadata(
        StoreAppSearchResult(
            adamID: app.adamID,
            name: "Example Flashcards Pro",
            developerName: app.developerName,
            bundleID: app.bundleID,
            primaryGenre: "Productivity",
            appStoreURL: nil,
            position: 1
        )
    )

    let updated = try #require(store.appSearchPresenceProject(for: app.adamID))
    #expect(updated.id == original.id)
    #expect(updated.name == "Example Flashcards Pro Search Presence")
    #expect(updated.genres == ["Productivity"])
    #expect(updated.seedKeywords.contains("Example Flashcards Pro"))
    #expect(updated.keywords.isEmpty)
    #expect(updated.rankingObservations.isEmpty)
    #expect(updated.rankingScans.isEmpty)
    #expect(store.library.projects.count == 1)
}

@Test("Removing a manual project falls back to an app instead of an internal project")
@MainActor
func removingManualProjectNeverSelectsInternalSearchPresenceProject() throws {
    let app = searchPresenceTestApp()
    let manual = searchPresenceTestProject(name: "Manual", kind: .manual)
    let internalProject = searchPresenceTestProject(
        name: "Internal",
        kind: .appSearchPresence,
        focusAppAdamID: app.adamID
    )
    let store = try searchPresenceTestStore(
        library: ASOLibrary(projects: [internalProject, manual], apps: [app])
    )
    store.selection = .project(manual.id)

    store.removeProject(id: manual.id)

    #expect(store.selection == .app(app.adamID))
    #expect(store.selection != .project(internalProject.id))
}

@Test("Removing the last app never selects its retained internal project")
@MainActor
func removingLastAppNeverSelectsInternalSearchPresenceProject() throws {
    let app = searchPresenceTestApp()
    let internalProject = searchPresenceTestProject(
        name: "Internal",
        kind: .appSearchPresence,
        focusAppAdamID: app.adamID
    )
    let store = try searchPresenceTestStore(
        library: ASOLibrary(projects: [internalProject], apps: [app])
    )

    #expect(store.selection == .app(app.adamID))
    store.selection = .app(app.adamID)

    store.removeApp(adamID: app.adamID)

    #expect(store.selection == nil)
    #expect(store.selection != .project(internalProject.id))
}

@Test("Search presence rows include scanned terms where the app did not rank")
@MainActor
func searchPresenceRowsIncludeNotRankedTerms() throws {
    let app = searchPresenceTestApp()
    let projectID = UUID()
    let checkedAt = Date(timeIntervalSinceReferenceDate: 2_000)
    let observations = RankingIndex.observations(
        projectID: projectID,
        keyword: "flashcards",
        store: "us",
        results: [
            StoreAppSearchResult(
                adamID: app.adamID,
                name: app.name,
                developerName: app.developerName,
                bundleID: app.bundleID,
                primaryGenre: app.primaryGenre,
                appStoreURL: nil,
                position: 3,
                userRatingCount: 500
            ),
            StoreAppSearchResult(
                adamID: 99,
                name: "Competitor",
                developerName: "Studio",
                bundleID: "com.example.competitor",
                primaryGenre: "Education",
                appStoreURL: nil,
                position: 1,
                userRatingCount: 1_000
            ),
        ],
        checkedAt: checkedAt
    )
    let project = ResearchProject(
        id: projectID,
        name: "Example Flashcards Search Presence",
        topic: app.primaryGenre,
        targets: [StoreTarget(language: "en", store: "us")],
        genres: [app.primaryGenre],
        seedKeywords: [app.name, app.primaryGenre],
        focusAppAdamID: app.adamID,
        kind: .appSearchPresence,
        keywords: [
            searchPresenceKeyword("flashcards"),
            searchPresenceKeyword("study cards"),
            KeywordRecord(
                keyword: "flashcards",
                language: "en",
                store: "us",
                genre: "Education",
                popularity: 62,
                source: .appleAds,
                isTracked: false
            ),
        ],
        rankingObservations: observations,
        rankingScans: [
            RankingScan(projectID: projectID, keyword: "flashcards", store: "us", checkedAt: checkedAt, resultCount: 100),
            RankingScan(projectID: projectID, keyword: "study cards", store: "us", checkedAt: checkedAt, resultCount: 100),
            RankingScan(projectID: projectID, keyword: "quiz maker", store: "us", checkedAt: checkedAt, resultCount: 75),
        ]
    )
    let store = try searchPresenceTestStore(
        library: ASOLibrary(projects: [project], apps: [app])
    )

    let rows = store.searchPresenceRows(for: app.adamID, store: "us")
    let summary = try #require(store.searchPresenceSummary(for: app.adamID, store: "us"))

    #expect(rows.map(\.keyword) == ["flashcards", "quiz maker", "study cards"])
    #expect(rows.first { $0.keyword == "flashcards" }?.popularity == 62)
    #expect(rows.first { $0.keyword == "study cards" }?.popularity == nil)
    #expect(rows.first { $0.keyword == "flashcards" }?.difficulty != nil)
    #expect(rows.first { $0.keyword == "flashcards" }?.focusAppPosition == 3)
    #expect(rows.first { $0.keyword == "study cards" }?.focusAppPosition == nil)
    #expect(rows.first { $0.keyword == "quiz maker" }?.focusAppPosition == nil)
    #expect(rows.first { $0.keyword == "flashcards" }?.resultCount == 100)
    #expect(rows.first { $0.keyword == "flashcards" }?.topApps.count == 2)
    #expect(rows.allSatisfy { $0.checkedAt == checkedAt })
    #expect(summary.keywordCount == 3)
    #expect(summary.rankedKeywordCount == 1)
    #expect(summary.notRankedKeywordCount == 2)
    #expect(summary.bestPosition == 3)
    #expect(summary.lastCheckedAt == checkedAt)
}

@MainActor
private func searchPresenceTestStore(library: ASOLibrary) throws -> LibraryStore {
    let fileURL = URL(fileURLWithPath: "/private/tmp/aso-search-presence-tests-\(UUID().uuidString)/library.json")
    let persistence = LibraryPersistence(fileURL: fileURL)
    try persistence.save(library)
    return LibraryStore(persistence: persistence)
}

private func searchPresenceTestApp() -> TrackedApp {
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

private func searchPresenceTestProject(
    name: String,
    kind: ResearchProjectKind,
    focusAppAdamID: Int64? = nil
) -> ResearchProject {
    ResearchProject(
        name: name,
        topic: "",
        targets: [StoreTarget(language: "en", store: "us")],
        genres: [],
        seedKeywords: [],
        focusAppAdamID: focusAppAdamID,
        kind: kind
    )
}

private func searchPresenceKeyword(_ keyword: String) -> KeywordRecord {
    KeywordRecord(
        keyword: keyword,
        language: "en",
        store: "us",
        genre: "Search Presence",
        popularity: 0,
        source: .appleSearchHints,
        isTracked: false
    )
}
