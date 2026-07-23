import Foundation
import Testing
@testable import ReadRevs

@Suite("Dashboard selection")
struct ReviewDashboardModelTests {
    @Test("A newer app selection wins over an in-flight refresh")
    @MainActor
    func latestSelectionWins() async throws {
        let model = ReviewDashboardModel(client: SwitchingReviewClient())
        let firstApp = dashboardMetadata(id: 1, name: "Slow App")
        let secondApp = dashboardMetadata(id: 2, name: "Fast App")

        let firstLoad = Task { await model.load(firstApp) }
        try await Task.sleep(for: .milliseconds(10))
        await model.load(secondApp)
        await firstLoad.value

        #expect(model.metadata?.appID == 2)
        #expect(!model.reviews.isEmpty)
        #expect(model.reviews.allSatisfy { $0.appID == 2 })
        #expect(Set(model.reviews.map(\.storefront)).count == Storefront.allCases.count)
        #expect(model.isRefreshing == false)
    }
}

private struct SwitchingReviewClient: AppleReviewClientProtocol {
    func reviews(appID: Int64, storefront: Storefront, page: Int) async throws -> [AppReview] {
        try await Task.sleep(for: appID == 1 ? .milliseconds(80) : .milliseconds(2))
        return [
            AppReview(
                id: "\(storefront.rawValue)-\(appID)",
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

    func lookup(appID: Int64, storefront: Storefront) async throws -> AppMetadata {
        try await Task.sleep(for: appID == 1 ? .milliseconds(80) : .milliseconds(2))
        return dashboardMetadata(id: appID, name: "App \(appID)", storefront: storefront)
    }

    func searchApps(term: String, storefront: Storefront, limit: Int) async throws -> [AppMetadata] {
        []
    }
}

private func dashboardMetadata(
    id: Int64,
    name: String,
    storefront: Storefront = .unitedStates
) -> AppMetadata {
    AppMetadata(
        appID: id,
        name: name,
        sellerName: "Studio",
        version: "1.0",
        primaryGenre: "Utilities",
        primaryStorefront: storefront
    )
}
