import Foundation
import Testing
@testable import ReadRevs

@Suite("Review synchronization")
struct ReviewSyncServiceTests {
    @Test("Keeps partial results and reports failed storefronts")
    func syncsWithPartialFailure() async {
        let client = StubReviewClient(
            reviewsByStorefront: [
                .unitedStates: [sampleReview(id: "same", storefront: .unitedStates)],
                .czechia: [sampleReview(id: "unique", storefront: .czechia)],
            ],
            failingStorefronts: [.germany]
        )
        let service = ReviewSyncService(client: client)

        let result = await service.sync(
            appID: 42,
            storefronts: [.unitedStates, .czechia, .germany],
            pagesPerStorefront: 1
        )

        #expect(result.reviews.count == 2)
        #expect(result.completedStorefronts == [.unitedStates, .czechia])
        #expect(result.failures.map(\.storefront) == [.germany])
    }
}

private struct StubReviewClient: AppleReviewClientProtocol {
    let reviewsByStorefront: [Storefront: [AppReview]]
    let failingStorefronts: Set<Storefront>

    func reviews(appID: Int64, storefront: Storefront, page: Int) async throws -> [AppReview] {
        if failingStorefronts.contains(storefront) {
            throw StubError.failed
        }
        return reviewsByStorefront[storefront] ?? []
    }

    func lookup(appID: Int64, storefront: Storefront) async throws -> AppMetadata {
        throw StubError.failed
    }
}

private enum StubError: Error {
    case failed
}

private func sampleReview(id: String, storefront: Storefront) -> AppReview {
    AppReview(
        id: "\(storefront.rawValue)-\(id)",
        sourceID: id,
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
