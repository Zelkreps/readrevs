import Foundation
import Observation

@MainActor
@Observable
final class ReviewDashboardModel {
    private(set) var metadata: AppMetadata?
    private(set) var reviews: [AppReview] = []
    private(set) var completedStorefronts: [Storefront] = []
    private(set) var failures: [ReviewSyncFailure] = []
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    var filters = ReviewFilters()

    @ObservationIgnored private let client: any AppleReviewClientProtocol
    @ObservationIgnored private let syncService: ReviewSyncService
    @ObservationIgnored private var selectedAppID: Int64?
    @ObservationIgnored private var refreshGeneration = 0

    init(client: any AppleReviewClientProtocol = AppleReviewClient()) {
        self.client = client
        syncService = ReviewSyncService(client: client)
    }

    var collection: ReviewCollection {
        ReviewCollection(reviews: reviews)
    }

    var filteredReviews: [AppReview] {
        collection.filtered(using: filters)
    }

    var isFiltered: Bool {
        !filters.searchText.isEmpty || filters.rating != nil || filters.storefront != nil || filters.version != nil
    }

    func load(_ app: AppMetadata) async {
        if selectedAppID != app.appID {
            selectedAppID = app.appID
            metadata = app
            reviews = []
            completedStorefronts = []
            failures = []
            filters = ReviewFilters()
        }
        await refresh()
    }

    func refresh() async {
        guard let app = metadata else { return }
        let requestedAppID = app.appID
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        errorMessage = nil
        failures = []
        defer {
            if refreshGeneration == generation {
                isRefreshing = false
            }
        }

        async let lookupResult: AppMetadata? = try? client.lookup(
            appID: requestedAppID,
            storefront: app.primaryStorefront
        )
        let syncResult = await syncService.sync(
            appID: requestedAppID,
            storefronts: Storefront.allCases,
            pagesPerStorefront: 1
        )

        guard
            selectedAppID == requestedAppID,
            refreshGeneration == generation
        else {
            return
        }

        if let freshMetadata = await lookupResult {
            metadata = freshMetadata
        }
        reviews = syncResult.reviews
        completedStorefronts = syncResult.completedStorefronts
        failures = syncResult.failures
        lastUpdated = Date()

        if reviews.isEmpty, !failures.isEmpty {
            errorMessage = "Reviews could not be loaded from Apple. Check your connection and try again."
        }
    }

    func clearFilters() {
        filters = ReviewFilters()
    }

    func clear() {
        refreshGeneration += 1
        selectedAppID = nil
        metadata = nil
        reviews = []
        completedStorefronts = []
        failures = []
        lastUpdated = nil
        errorMessage = nil
        isRefreshing = false
        filters = ReviewFilters()
    }
}
