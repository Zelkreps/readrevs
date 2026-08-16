import Foundation
import Testing
@testable import ReadRevsCore

@Test
func rankingIndexAggregatesAppsAndSupportsReverseKeywordLookup() {
    let projectID = UUID()
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let first = StoreAppSearchResult(
        adamID: 100,
        name: "Atlas One",
        developerName: "Studio",
        bundleID: "com.example.atlas",
        primaryGenre: "Education",
        appStoreURL: URL(string: "https://apps.apple.com/app/id100"),
        position: 1
    )
    let second = StoreAppSearchResult(
        adamID: 200,
        name: "Flags Two",
        developerName: "Studio",
        bundleID: "com.example.flags",
        primaryGenre: "Games",
        appStoreURL: nil,
        position: 3
    )
    let observations = RankingIndex.observations(
        projectID: projectID,
        keyword: "flag quiz",
        store: "us",
        results: [first, second],
        checkedAt: checkedAt
    ) + RankingIndex.observations(
        projectID: projectID,
        keyword: "world atlas",
        store: "us",
        results: [first],
        checkedAt: checkedAt
    )

    let summaries = RankingIndex.summaries(from: observations)
    let atlas = summaries.first { $0.adamID == 100 }

    #expect(atlas?.keywordCount == 2)
    #expect(atlas?.bestPosition == 1)
    #expect(atlas?.keywords == ["flag quiz", "world atlas"])
    #expect(RankingIndex.keywords(for: 200, in: observations).map(\.keyword) == ["flag quiz"])
}

@Test
func rankingIndexReplacesTheWholeScannedKeywordStorePair() {
    let projectID = UUID()
    let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
    let newDate = oldDate.addingTimeInterval(60)
    let oldResults = [
        StoreAppSearchResult(
            adamID: 100,
            name: "Old Result",
            developerName: "Studio",
            bundleID: "com.example.old",
            primaryGenre: "Games",
            appStoreURL: nil,
            position: 1
        ),
    ]
    let existing = RankingIndex.observations(
        projectID: projectID,
        keyword: "flag quiz",
        store: "us",
        results: oldResults,
        checkedAt: oldDate
    )
    let scan = RankingScan(
        projectID: projectID,
        keyword: "flag quiz",
        store: "us",
        checkedAt: newDate,
        resultCount: 0
    )

    let replaced = RankingIndex.replacing(existing: existing, with: [], for: scan)

    #expect(replaced.isEmpty)
}

@Test
func rankingSummariesRemainSeparatedByStore() {
    let projectID = UUID()
    let result = StoreAppSearchResult(
        adamID: 100,
        name: "Atlas",
        developerName: "Studio",
        bundleID: "com.example.atlas",
        primaryGenre: "Education",
        appStoreURL: nil,
        position: 1
    )
    let observations = RankingIndex.observations(
        projectID: projectID,
        keyword: "atlas",
        store: "us",
        results: [result]
    ) + RankingIndex.observations(
        projectID: projectID,
        keyword: "atlas",
        store: "fr",
        results: [result]
    )

    let summaries = RankingIndex.summaries(from: observations)

    #expect(summaries.count == 2)
    #expect(Set(summaries.map(\.store)) == ["us", "fr"])
}

@Test
func keywordSearchMetricsExposeFocusPositionAppsAndDifficultyProxy() {
    let projectID = UUID()
    let results = [
        StoreAppSearchResult(
            adamID: 100,
            name: "Focus App",
            developerName: "Studio",
            bundleID: "com.example.focus",
            primaryGenre: "Education",
            appStoreURL: nil,
            position: 1,
            artworkURL: URL(string: "https://example.com/focus.png"),
            userRatingCount: 50_000
        ),
        StoreAppSearchResult(
            adamID: 200,
            name: "Competitor",
            developerName: "Studio",
            bundleID: "com.example.competitor",
            primaryGenre: "Games",
            appStoreURL: nil,
            position: 2,
            artworkURL: nil,
            userRatingCount: 10_000
        ),
    ]
    let observations = RankingIndex.observations(
        projectID: projectID,
        keyword: "flag quiz",
        store: "us",
        results: results
    )

    let metrics = RankingIndex.searchMetrics(
        keyword: "flag quiz",
        store: "us",
        focusAppAdamID: 100,
        observations: observations
    )

    #expect(metrics.focusAppPosition == 1)
    #expect(metrics.topApps.map(\.adamID) == [100, 200])
    #expect(metrics.difficulty != nil)
    #expect((metrics.difficulty ?? 0) > 0)
}

@Test
func keywordSearchMetricsKeepAllRankingAppsForCountAndPopover() {
    let projectID = UUID()
    let results = (1...12).map { position in
        StoreAppSearchResult(
            adamID: Int64(position),
            name: "App \(position)",
            developerName: "Studio",
            bundleID: "com.example.\(position)",
            primaryGenre: "Games",
            appStoreURL: nil,
            position: position
        )
    }
    let observations = RankingIndex.observations(
        projectID: projectID,
        keyword: "quiz",
        store: "us",
        results: results
    )

    let metrics = RankingIndex.searchMetrics(
        keyword: "quiz",
        store: "us",
        focusAppAdamID: nil,
        observations: observations
    )

    #expect(metrics.topApps.count == 12)
    #expect(metrics.topApps.map(\.position) == Array(1...12))
}
