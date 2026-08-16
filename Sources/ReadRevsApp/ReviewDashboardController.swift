import ReadRevsCore
import Foundation

@MainActor
final class ReviewDashboardController: ObservableObject {
    @Published private(set) var metadata: TrackedApp?
    @Published private(set) var reviews: [AppReview] = []
    @Published private(set) var completedStorefronts: [String] = []
    @Published private(set) var failures: [ReviewSyncFailure] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var filters = ReviewFilters()

    private let metadataClient: any AppStoreLookupProviding
    private let syncService: ReviewSyncService
    private let storefronts: [String]
    private var selectedAppID: Int64?
    private var refreshGeneration = 0

    init(
        metadataClient: any AppStoreLookupProviding = ITunesAppStoreClient(),
        reviewClient: any AppReviewFetching = AppStoreReviewClient(),
        storefronts: [String] = AppStoreReviewClient.supportedStorefronts
    ) {
        self.metadataClient = metadataClient
        syncService = ReviewSyncService(client: reviewClient)
        self.storefronts = storefronts
    }

    var collection: ReviewCollection {
        ReviewCollection(reviews: reviews)
    }

    var filteredReviews: [AppReview] {
        collection.filtered(using: filters)
    }

    var isFiltered: Bool {
        !filters.searchText.isEmpty
            || filters.rating != nil
            || filters.storefront != nil
            || filters.version != nil
    }

    var totalStorefrontCount: Int { storefronts.count }

    @discardableResult
    func load(_ app: TrackedApp) async -> StoreAppSearchResult? {
        if selectedAppID != app.adamID {
            refreshGeneration += 1
            selectedAppID = app.adamID
            metadata = app
            reviews = []
            completedStorefronts = []
            failures = []
            filters = ReviewFilters()
            lastUpdated = nil
            errorMessage = nil
        }
        return await refresh()
    }

    @discardableResult
    func refresh() async -> StoreAppSearchResult? {
        guard let app = metadata else { return nil }
        let requestedAppID = app.adamID
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        errorMessage = nil
        failures = []

        async let lookupResult: StoreAppSearchResult? = try? metadataClient.lookup(
            adamID: requestedAppID,
            country: app.primaryStore
        )
        let syncResult = await syncService.sync(
            appID: requestedAppID,
            storefronts: storefronts,
            pagesPerStorefront: 1
        )
        let freshMetadata = await lookupResult

        guard selectedAppID == requestedAppID, refreshGeneration == generation else {
            return nil
        }

        if let freshMetadata {
            metadata = app.updatingMetadata(from: freshMetadata)
        }
        reviews = syncResult.reviews
        completedStorefronts = syncResult.completedStorefronts
        failures = syncResult.failures
        lastUpdated = Date()
        isRefreshing = false

        if reviews.isEmpty, !failures.isEmpty {
            errorMessage = "Reviews could not be loaded from Apple. Check your connection and try again."
        }
        return freshMetadata
    }

    func clearFilters() {
        filters = ReviewFilters()
    }

    func cancel() {
        refreshGeneration += 1
        isRefreshing = false
    }

}
