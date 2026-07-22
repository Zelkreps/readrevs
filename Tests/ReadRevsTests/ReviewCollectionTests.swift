import Foundation
import Testing
@testable import ReadRevs

@Suite("Review collection")
struct ReviewCollectionTests {
    private let reviews = [
        AppReview(
            id: "us-1",
            sourceID: "1",
            appID: 42,
            storefront: .unitedStates,
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
            storefront: .czechia,
            rating: 5,
            title: "Skvělá aktualizace",
            body: "Everything is faster now.",
            reviewerName: "Eva",
            version: "2.0",
            updatedAt: Date(timeIntervalSince1970: 200)
        ),
        AppReview(
            id: "de-3",
            sourceID: "3",
            appID: 42,
            storefront: .germany,
            rating: 3,
            title: "Good, but slow",
            body: "Search needs work.",
            reviewerName: "Sam",
            version: "1.9",
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
    ]

    @Test("Combines full-text, rating, country, and version filters")
    func filtersReviews() {
        let collection = ReviewCollection(reviews: reviews)
        let filters = ReviewFilters(
            searchText: "update",
            rating: 1,
            storefront: .unitedStates,
            version: "2.0",
            sortOrder: .newest
        )

        #expect(collection.filtered(using: filters).map(\.id) == ["us-1"])
    }

    @Test("Calculates synced-review metrics")
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

    @Test("Sorts by lowest rating and then newest")
    func sortsByLowestRating() {
        let collection = ReviewCollection(reviews: reviews)
        let filters = ReviewFilters(sortOrder: .lowestRating)

        #expect(collection.filtered(using: filters).map(\.rating) == [1, 3, 5])
    }
}
