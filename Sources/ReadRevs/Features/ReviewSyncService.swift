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
    private let maximumConcurrentStorefronts: Int

    init(
        client: any AppleReviewClientProtocol,
        maximumConcurrentStorefronts: Int = 8
    ) {
        self.client = client
        self.maximumConcurrentStorefronts = max(maximumConcurrentStorefronts, 1)
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
            of: IndexedSyncOutcome?.self,
            returning: [IndexedSyncOutcome].self
        ) { group in
            let concurrentCount = min(maximumConcurrentStorefronts, uniqueStorefronts.count)
            var nextIndex = 0

            func addTask(at index: Int) {
                let storefront = uniqueStorefronts[index]
                group.addTask { [client] in
                    await Self.syncOutcome(
                        client: client,
                        appID: appID,
                        storefront: storefront,
                        pagesToFetch: pagesToFetch,
                        index: index
                    )
                }
            }

            while nextIndex < concurrentCount {
                addTask(at: nextIndex)
                nextIndex += 1
            }

            var values: [IndexedSyncOutcome] = []
            while let value = await group.next() {
                if let value {
                    values.append(value)
                }

                if Task.isCancelled {
                    group.cancelAll()
                } else if nextIndex < uniqueStorefronts.count {
                    addTask(at: nextIndex)
                    nextIndex += 1
                }
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

    private static func syncOutcome(
        client: any AppleReviewClientProtocol,
        appID: Int64,
        storefront: Storefront,
        pagesToFetch: Int,
        index: Int
    ) async -> IndexedSyncOutcome? {
        var reviews: [AppReview] = []

        do {
            for page in 1 ... pagesToFetch {
                try Task.checkCancellation()
                let pageReviews = try await client.reviews(
                    appID: appID,
                    storefront: storefront,
                    page: page
                )
                try Task.checkCancellation()
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
        } catch is CancellationError {
            return nil
        } catch {
            if Task.isCancelled {
                return nil
            }
            return IndexedSyncOutcome(
                index: index,
                storefront: storefront,
                reviews: reviews,
                failureMessage: message(for: error)
            )
        }
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
