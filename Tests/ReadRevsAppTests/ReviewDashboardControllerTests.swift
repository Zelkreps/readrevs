import ReadRevsCore
import Foundation
import Testing
@testable import ReadRevsApp

@Test("A newer app selection wins over an in-flight review refresh")
@MainActor
func latestReviewSelectionWins() async throws {
    let controller = ReviewDashboardController(
        metadataClient: SwitchingLookupClient(),
        reviewClient: SwitchingReviewClient(),
        storefronts: ["us", "cz"]
    )
    let firstApp = trackedApp(id: 1, name: "Slow App")
    let secondApp = trackedApp(id: 2, name: "Fast App")

    let firstLoad = Task { @MainActor in
        await controller.load(firstApp)
    }
    try await Task.sleep(for: .milliseconds(10))
    _ = await controller.load(secondApp)
    _ = await firstLoad.value

    #expect(controller.metadata?.adamID == 2)
    #expect(!controller.reviews.isEmpty)
    #expect(controller.reviews.allSatisfy { $0.appID == 2 })
    #expect(controller.isRefreshing == false)
}

private struct SwitchingLookupClient: AppStoreLookupProviding {
    func lookup(adamID: Int64, country: String) async throws -> StoreAppSearchResult? {
        try await Task.sleep(for: adamID == 1 ? .milliseconds(80) : .milliseconds(2))
        return StoreAppSearchResult(
            adamID: adamID,
            name: "App \(adamID)",
            developerName: "Studio",
            bundleID: "com.example.\(adamID)",
            primaryGenre: "Utilities",
            appStoreURL: nil,
            position: 1
        )
    }
}

private struct SwitchingReviewClient: AppReviewFetching {
    func reviews(appID: Int64, storefront: String, page: Int) async throws -> [AppReview] {
        try await Task.sleep(for: appID == 1 ? .milliseconds(80) : .milliseconds(2))
        return [
            AppReview(
                id: "\(storefront)-\(appID)",
                sourceID: "\(appID)",
                appID: appID,
                storefront: storefront,
                rating: 5,
                title: "Review for \(appID)",
                body: "Body",
                reviewerName: "Reviewer",
                version: "1.0",
                updatedAt: Date(timeIntervalSince1970: TimeInterval(appID))
            ),
        ]
    }
}

private func trackedApp(id: Int64, name: String) -> TrackedApp {
    TrackedApp(
        adamID: id,
        name: name,
        developerName: "Studio",
        bundleID: "com.example.\(id)",
        primaryStore: "us",
        primaryGenre: "Utilities",
        kind: .owned
    )
}
