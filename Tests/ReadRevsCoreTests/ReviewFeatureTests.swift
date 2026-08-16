import Foundation
import Testing
@testable import ReadRevsCore

@Suite("App review research")
struct ReviewFeatureTests {
    private let reviews = [
        AppReview(
            id: "us-1",
            sourceID: "1",
            appID: 42,
            storefront: "us",
            rating: 1,
            title: "Crashes on launch",
            body: "The latest update will not open.",
            reviewerName: "Alex",
            version: "2.0",
            updatedAt: Date(timeIntervalSince1970: 300)
        ),
        AppReview(
            id: "cz-2",
            sourceID: "2",
            appID: 42,
            storefront: "cz",
            rating: 5,
            title: "Skvela aktualizace",
            body: "Everything is faster now.",
            reviewerName: "Eva",
            version: "2.0",
            updatedAt: Date(timeIntervalSince1970: 200)
        ),
        AppReview(
            id: "de-3",
            sourceID: "3",
            appID: 42,
            storefront: "de",
            rating: 3,
            title: "Good, but slow",
            body: "Search needs work.",
            reviewerName: "Sam",
            version: "1.9",
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
    ]

    @Test("Calculates classic ReadRevs metrics")
    func calculatesMetrics() {
        let collection = ReviewCollection(reviews: reviews)

        #expect(collection.count(for: 1) == 1)
        #expect(collection.count(for: 2) == 0)
        #expect(collection.count(for: 3) == 1)
        #expect(collection.count(for: 5) == 1)
        #expect(collection.averageRating == 3)
        #expect(collection.storefrontCount == 3)
        #expect(collection.versions == ["2.0", "1.9"])
    }

    @Test("Combines full-text, rating, country, version, and sort filters")
    func filtersReviews() {
        let collection = ReviewCollection(reviews: reviews)
        let filters = ReviewFilters(
            searchText: "update",
            rating: 1,
            storefront: "us",
            version: "2.0",
            sortOrder: .newest
        )

        #expect(collection.filtered(using: filters).map(\.id) == ["us-1"])
        #expect(
            collection.filtered(using: ReviewFilters(sortOrder: .lowestRating)).map(\.rating)
                == [1, 3, 5]
        )
    }

    @Test("Parses Apple's recent written review feed")
    func parsesReviewFeed() throws {
        let payload = """
        {
          "feed": {
            "entry": [
              {
                "id": {"label": "123"},
                "author": {"name": {"label": "Reviewer"}},
                "updated": {"label": "2026-08-10T09:30:00-07:00"},
                "im:rating": {"label": "4"},
                "im:version": {"label": "2.5"},
                "title": {"label": "Useful"},
                "content": {"label": "Works well."}
              }
            ]
          }
        }
        """

        let parsed = try AppStoreReviewResponseParser.parse(
            Data(payload.utf8),
            appID: 42,
            storefront: "us"
        )

        #expect(parsed.count == 1)
        #expect(parsed[0].id == "us-123")
        #expect(parsed[0].rating == 4)
        #expect(parsed[0].version == "2.5")
        #expect(parsed[0].reviewerName == "Reviewer")
    }

    @Test("Keeps the broad ReadRevs storefront catalog")
    func keepsBroadStorefrontCatalog() {
        let storefronts = AppStoreReviewClient.supportedStorefronts

        #expect(storefronts.count == 175)
        #expect(Set(storefronts).count == storefronts.count)
        #expect(Set(["us", "gb", "cz", "de", "fr", "es", "kr"]).isSubset(of: Set(storefronts)))
    }

    @Test("Rejects countries outside the canonical review catalog")
    func rejectsUnsupportedStorefront() {
        #expect(throws: AppStoreReviewClient.ClientError.invalidStorefront) {
            try AppStoreReviewClient.reviewFeedURL(appID: 42, storefront: "zz", page: 1)
        }
    }

    @Test("Metadata refresh preserves tracked-app ownership state")
    func metadataMergePreservesASOState() {
        let addedAt = Date(timeIntervalSince1970: 123)
        let app = TrackedApp(
            adamID: 42,
            name: "Old Name",
            developerName: "Studio",
            bundleID: "old.bundle",
            primaryStore: "cz",
            kind: .competitor,
            addedAt: addedAt
        )
        let result = StoreAppSearchResult(
            adamID: 42,
            name: "Fresh Name",
            developerName: "Fresh Studio",
            bundleID: "fresh.bundle",
            primaryGenre: "Games",
            appStoreURL: nil,
            position: 1,
            userRatingCount: 1_234,
            averageRating: 4.8,
            version: "3.0"
        )

        let refreshed = app.updatingMetadata(from: result)

        #expect(refreshed.name == "Fresh Name")
        #expect(refreshed.kind == .competitor)
        #expect(refreshed.primaryStore == "cz")
        #expect(refreshed.addedAt == addedAt)
        #expect(refreshed.averageRating == 4.8)
        #expect(refreshed.ratingCount == 1_234)

        let partial = StoreAppSearchResult(
            adamID: 42,
            name: "Fresh Name",
            developerName: "Fresh Studio",
            bundleID: "fresh.bundle",
            primaryGenre: "Games",
            appStoreURL: nil,
            position: 1
        )
        let mergedPartial = refreshed.updatingMetadata(from: partial)
        #expect(mergedPartial.averageRating == 4.8)
        #expect(mergedPartial.ratingCount == 1_234)
        #expect(mergedPartial.version == "3.0")
    }

    @Test("Keeps partial storefront results and reports failures")
    func syncsWithPartialFailure() async {
        let client = StubReviewClient(
            reviewsByStorefront: [
                "us": [reviews[0]],
                "cz": [reviews[1]],
            ],
            failingStorefronts: ["de"]
        )
        let service = ReviewSyncService(client: client, maximumConcurrentStorefronts: 2)

        let result = await service.sync(
            appID: 42,
            storefronts: ["us", "cz", "de"],
            pagesPerStorefront: 1
        )

        #expect(result.reviews.count == 2)
        #expect(result.completedStorefronts == ["us", "cz"])
        #expect(result.failures.map(\.storefront) == ["de"])
    }

    @Test("Bounds storefront concurrency and preserves catalog order")
    func boundsConcurrencyAndPreservesOrder() async {
        let probe = ReviewConcurrencyProbe()
        let client = ProbedReviewClient(probe: probe)
        let service = ReviewSyncService(client: client, maximumConcurrentStorefronts: 3)
        let storefronts = Array(AppStoreReviewClient.supportedStorefronts.prefix(12))

        let result = await service.sync(
            appID: 42,
            storefronts: storefronts,
            pagesPerStorefront: 1
        )

        #expect(await probe.maximumObserved == 3)
        #expect(result.completedStorefronts == storefronts)
        #expect(result.reviews.map(\.storefront) == storefronts)
    }

    @Test("Cancellation stops scheduling additional storefronts")
    func cancellationStopsNewRequests() async throws {
        let client = CancellableReviewClient()
        let service = ReviewSyncService(client: client, maximumConcurrentStorefronts: 2)
        let syncTask = Task {
            await service.sync(
                appID: 42,
                storefronts: Array(AppStoreReviewClient.supportedStorefronts.prefix(12)),
                pagesPerStorefront: 1
            )
        }

        for _ in 0..<100 {
            if await client.requestCount >= 2 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(await client.requestCount == 2)

        syncTask.cancel()
        let result = await syncTask.value

        #expect(await client.requestCount == 2)
        #expect(result.failures.isEmpty)
    }
}

private struct StubReviewClient: AppReviewFetching {
    let reviewsByStorefront: [String: [AppReview]]
    let failingStorefronts: Set<String>

    func reviews(appID: Int64, storefront: String, page: Int) async throws -> [AppReview] {
        if failingStorefronts.contains(storefront) {
            throw StubError.failed
        }
        return reviewsByStorefront[storefront] ?? []
    }
}

private enum StubError: Error {
    case failed
}

private actor ReviewConcurrencyProbe {
    private var active = 0
    private(set) var maximumObserved = 0

    func start() {
        active += 1
        maximumObserved = max(maximumObserved, active)
    }

    func finish() {
        active -= 1
    }
}

private struct ProbedReviewClient: AppReviewFetching {
    let probe: ReviewConcurrencyProbe

    func reviews(appID: Int64, storefront: String, page: Int) async throws -> [AppReview] {
        await probe.start()
        try await Task.sleep(for: .milliseconds(15))
        await probe.finish()
        return [testReview(storefront: storefront)]
    }
}

private actor CancellableReviewClient: AppReviewFetching {
    private(set) var requestCount = 0

    func reviews(appID: Int64, storefront: String, page: Int) async throws -> [AppReview] {
        requestCount += 1
        try await Task.sleep(for: .seconds(10))
        return []
    }
}

private func testReview(storefront: String) -> AppReview {
    AppReview(
        id: "\(storefront)-1",
        sourceID: "1",
        appID: 42,
        storefront: storefront,
        rating: 5,
        title: "Title",
        body: "Body",
        reviewerName: "Reviewer",
        version: "1.0",
        updatedAt: Date(timeIntervalSince1970: 1)
    )
}
