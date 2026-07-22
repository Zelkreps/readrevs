import Foundation

struct ReviewSyncFailure: Codable, Hashable, Sendable {
    let storefront: Storefront
    let message: String
}

struct ReviewSyncResult: Codable, Hashable, Sendable {
    let reviews: [AppReview]
    let completedStorefronts: [Storefront]
    let failures: [ReviewSyncFailure]
}

struct ReviewSyncService: Sendable {
    private let client: any AppleReviewClientProtocol

    init(client: any AppleReviewClientProtocol) {
        self.client = client
    }

    func sync(
        appID: Int64,
        storefronts: [Storefront],
        pagesPerStorefront: Int = 10
    ) async -> ReviewSyncResult {
        let pagesToFetch = min(max(pagesPerStorefront, 1), 10)
        let uniqueStorefronts = storefronts.reduce(into: [Storefront]()) { result, storefront in
            if !result.contains(storefront) {
                result.append(storefront)
            }
        }

        let outcomes = await withTaskGroup(
            of: IndexedSyncOutcome.self,
            returning: [IndexedSyncOutcome].self
        ) { group in
            for (index, storefront) in uniqueStorefronts.enumerated() {
                group.addTask { [client] in
                    var reviews: [AppReview] = []

                    do {
                        for page in 1 ... pagesToFetch {
                            let pageReviews = try await client.reviews(
                                appID: appID,
                                storefront: storefront,
                                page: page
                            )
                            reviews.append(contentsOf: pageReviews)
                            if pageReviews.isEmpty {
                                break
                            }
                        }
                        return IndexedSyncOutcome(
                            index: index,
                            storefront: storefront,
                            reviews: reviews,
                            failureMessage: nil
                        )
                    } catch {
                        return IndexedSyncOutcome(
                            index: index,
                            storefront: storefront,
                            reviews: reviews,
                            failureMessage: Self.message(for: error)
                        )
                    }
                }
            }

            var values: [IndexedSyncOutcome] = []
            for await value in group {
                values.append(value)
            }
            return values.sorted { $0.index < $1.index }
        }

        var seenReviewIDs: Set<String> = []
        var reviews: [AppReview] = []
        var completedStorefronts: [Storefront] = []
        var failures: [ReviewSyncFailure] = []

        for outcome in outcomes {
            reviews.append(
                contentsOf: outcome.reviews.filter { seenReviewIDs.insert($0.id).inserted }
            )
            if let message = outcome.failureMessage {
                failures.append(
                    ReviewSyncFailure(storefront: outcome.storefront, message: message)
                )
            } else {
                completedStorefronts.append(outcome.storefront)
            }
        }

        return ReviewSyncResult(
            reviews: reviews,
            completedStorefronts: completedStorefronts,
            failures: failures
        )
    }

    private static func message(for error: any Swift.Error) -> String {
        if
            let localizedError = error as? any LocalizedError,
            let description = localizedError.errorDescription
        {
            return description
        }
        return String(describing: error)
    }
}

private struct IndexedSyncOutcome: Sendable {
    let index: Int
    let storefront: Storefront
    let reviews: [AppReview]
    let failureMessage: String?
}
