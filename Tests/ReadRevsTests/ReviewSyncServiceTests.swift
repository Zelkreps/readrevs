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

    @Test("Bounds storefront requests while preserving input order")
    func boundsConcurrencyAndPreservesOrder() async {
        let probe = ConcurrencyProbe()
        let client = ProbedReviewClient(probe: probe)
        let service = ReviewSyncService(client: client, maximumConcurrentStorefronts: 3)
        let storefronts = Array(Storefront.allCases.prefix(12))

        let result = await service.sync(
            appID: 42,
            storefronts: storefronts,
            pagesPerStorefront: 1
        )

        #expect(await probe.maximumObserved == 3)
        #expect(result.completedStorefronts == storefronts)
        #expect(result.reviews.map(\.storefront) == storefronts)
    }

    @Test("Uses eight concurrent storefronts by default")
    func usesDefaultConcurrencyLimit() async {
        let probe = ConcurrencyProbe()
        let service = ReviewSyncService(client: ProbedReviewClient(probe: probe))

        _ = await service.sync(
            appID: 42,
            storefronts: Array(Storefront.allCases.prefix(12)),
            pagesPerStorefront: 1
        )

        #expect(await probe.maximumObserved == 8)
    }

    @Test("Cancellation stops scheduling additional storefront requests")
    func cancellationStopsNewRequests() async throws {
        let client = CancellableReviewClient()
        let service = ReviewSyncService(client: client, maximumConcurrentStorefronts: 2)

        let syncTask = Task {
            await service.sync(
                appID: 42,
                storefronts: Storefront.allCases,
                pagesPerStorefront: 1
            )
        }

        for _ in 0 ..< 100 {
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

    func searchApps(term: String, storefront: Storefront, limit: Int) async throws -> [AppMetadata] {
        throw StubError.failed
    }
}

private actor ConcurrencyProbe {
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

private struct ProbedReviewClient: AppleReviewClientProtocol {
    let probe: ConcurrencyProbe

    func reviews(appID: Int64, storefront: Storefront, page: Int) async throws -> [AppReview] {
        await probe.start()
        try await Task.sleep(for: .milliseconds(15))
        await probe.finish()
        return [sampleReview(id: storefront.rawValue, storefront: storefront)]
    }

    func lookup(appID: Int64, storefront: Storefront) async throws -> AppMetadata {
        throw StubError.failed
    }

    func searchApps(term: String, storefront: Storefront, limit: Int) async throws -> [AppMetadata] {
        throw StubError.failed
    }
}

private actor CancellableReviewClient: AppleReviewClientProtocol {
    private(set) var requestCount = 0

    func reviews(appID: Int64, storefront: Storefront, page: Int) async throws -> [AppReview] {
        requestCount += 1
        try await Task.sleep(for: .seconds(10))
        return []
    }

    nonisolated func lookup(appID: Int64, storefront: Storefront) async throws -> AppMetadata {
        throw StubError.failed
    }

    nonisolated func searchApps(
        term: String,
        storefront: Storefront,
        limit: Int
    ) async throws -> [AppMetadata] {
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
