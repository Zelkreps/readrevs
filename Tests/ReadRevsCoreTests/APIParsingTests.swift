import Foundation
import Testing
@testable import ReadRevsCore

@Test
func appStoreParserPreservesResultOrderAsObservedPosition() throws {
    let payload = """
    {
      "resultCount": 2,
      "results": [
        {"trackId": 100, "trackName": "First App", "artistName": "A", "bundleId": "a.first", "primaryGenreName": "Education", "trackViewUrl": "https://apps.apple.com/app/id100", "artworkUrl100": "https://example.com/icon.png", "version": "4.2", "releaseDate": "2020-01-02T12:00:00Z", "currentVersionReleaseDate": "2026-08-10T09:30:00Z", "averageUserRating": 4.7, "userRatingCount": 12000},
        {"trackId": 200, "trackName": "Second App", "artistName": "B", "bundleId": "b.second", "primaryGenreName": "Games", "trackViewUrl": "https://apps.apple.com/app/id200"}
      ]
    }
    """

    let results = try AppStoreSearchResponseParser.parse(Data(payload.utf8))

    #expect(results.map(\.adamID) == [100, 200])
    #expect(results.map(\.position) == [1, 2])
    #expect(results[1].name == "Second App")
    #expect(results[0].artworkURL == URL(string: "https://example.com/icon.png"))
    #expect(results[0].userRatingCount == 12_000)
    #expect(results[0].averageRating == 4.7)
    #expect(results[0].version == "4.2")
    #expect(results[0].releaseDate != nil)
    #expect(results[0].currentVersionReleaseDate != nil)
}

@Test
func appStoreIdentifierAcceptsNumericIDsAndAppStoreURLs() {
    #expect(AppStoreIdentifier.parse("123456789") == 123_456_789)
    #expect(AppStoreIdentifier.parse("https://apps.apple.com/cz/app/example-app/id987654321?l=cs") == 987_654_321)
    #expect(AppStoreIdentifier.parse("not an app") == nil)
}

@Test
func requestRateLimiterSerializesConcurrentWaiters() async throws {
    let minimumInterval = 0.03
    let limiter = RequestRateLimiter(minimumInterval: minimumInterval)
    let dates = try await withThrowingTaskGroup(of: Date.self) { group in
        for _ in 0..<3 {
            group.addTask {
                try await limiter.waitForTurn()
                return Date()
            }
        }

        var values: [Date] = []
        for try await value in group {
            values.append(value)
        }
        return values.sorted()
    }

    #expect(dates.count == 3)
    #expect(dates[1].timeIntervalSince(dates[0]) >= minimumInterval * 0.75)
    #expect(dates[2].timeIntervalSince(dates[1]) >= minimumInterval * 0.75)
}
