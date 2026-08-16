import Foundation

public enum ReviewSortOrder: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case newest
    case oldest
    case highestRating
    case lowestRating

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .highestRating: "Highest Rating"
        case .lowestRating: "Lowest Rating"
        }
    }
}

public struct AppReview: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var sourceID: String
    public var appID: Int64
    public var storefront: String
    public var rating: Int
    public var title: String
    public var body: String
    public var reviewerName: String
    public var version: String?
    public var updatedAt: Date

    public init(
        id: String,
        sourceID: String,
        appID: Int64,
        storefront: String,
        rating: Int,
        title: String,
        body: String,
        reviewerName: String,
        version: String?,
        updatedAt: Date
    ) {
        self.id = id
        self.sourceID = sourceID
        self.appID = appID
        self.storefront = storefront.lowercased()
        self.rating = rating
        self.title = title
        self.body = body
        self.reviewerName = reviewerName
        self.version = version
        self.updatedAt = updatedAt
    }
}

public struct ReviewFilters: Codable, Hashable, Sendable {
    public var searchText: String
    public var rating: Int?
    public var storefront: String?
    public var version: String?
    public var sortOrder: ReviewSortOrder

    public init(
        searchText: String = "",
        rating: Int? = nil,
        storefront: String? = nil,
        version: String? = nil,
        sortOrder: ReviewSortOrder = .newest
    ) {
        self.searchText = searchText
        self.rating = rating
        self.storefront = storefront?.lowercased()
        self.version = version
        self.sortOrder = sortOrder
    }
}

public struct ReviewCollection: Codable, Hashable, Sendable {
    public var reviews: [AppReview]

    public init(reviews: [AppReview]) {
        self.reviews = reviews
    }

    public var averageRating: Double? {
        guard !reviews.isEmpty else { return nil }
        return Double(reviews.reduce(0) { $0 + $1.rating }) / Double(reviews.count)
    }

    public var storefrontCount: Int {
        Set(reviews.map(\.storefront)).count
    }

    public var versions: [String] {
        var seen: Set<String> = []
        return reviews
            .sorted(by: Self.newestFirst)
            .compactMap(\.version)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public func count(for rating: Int) -> Int {
        reviews.count { $0.rating == rating }
    }

    public func filtered(using filters: ReviewFilters) -> [AppReview] {
        let query = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return reviews
            .filter { review in
                if !query.isEmpty, !Self.matches(review, query: query) { return false }
                if let rating = filters.rating, review.rating != rating { return false }
                if let storefront = filters.storefront, review.storefront != storefront.lowercased() { return false }
                if let version = filters.version, review.version != version { return false }
                return true
            }
            .sorted { lhs, rhs in
                switch filters.sortOrder {
                case .newest:
                    Self.newestFirst(lhs, rhs)
                case .oldest:
                    Self.oldestFirst(lhs, rhs)
                case .highestRating:
                    lhs.rating == rhs.rating ? Self.newestFirst(lhs, rhs) : lhs.rating > rhs.rating
                case .lowestRating:
                    lhs.rating == rhs.rating ? Self.newestFirst(lhs, rhs) : lhs.rating < rhs.rating
                }
            }
    }

    private static func matches(_ review: AppReview, query: String) -> Bool {
        [review.title, review.body, review.reviewerName, review.version ?? ""]
            .contains {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
    }

    private static func newestFirst(_ lhs: AppReview, _ rhs: AppReview) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt > rhs.updatedAt
    }

    private static func oldestFirst(_ lhs: AppReview, _ rhs: AppReview) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt < rhs.updatedAt
    }
}

public struct ReviewSyncFailure: Codable, Hashable, Sendable {
    public var storefront: String
    public var message: String

    public init(storefront: String, message: String) {
        self.storefront = storefront.lowercased()
        self.message = message
    }
}

public struct ReviewSyncResult: Codable, Hashable, Sendable {
    public var reviews: [AppReview]
    public var completedStorefronts: [String]
    public var failures: [ReviewSyncFailure]

    public init(
        reviews: [AppReview],
        completedStorefronts: [String],
        failures: [ReviewSyncFailure]
    ) {
        self.reviews = reviews
        self.completedStorefronts = completedStorefronts
        self.failures = failures
    }
}

public protocol AppReviewFetching: Sendable {
    func reviews(appID: Int64, storefront: String, page: Int) async throws -> [AppReview]
}

public struct AppStoreReviewClient: AppReviewFetching, Sendable {
    public static let supportedStorefronts = [
        "ae", "af", "ag", "ai", "al", "am", "ao", "ar", "at", "au", "az",
        "ba", "bb", "be", "bf", "bg", "bh", "bj", "bm", "bn", "bo", "br",
        "bs", "bt", "bw", "by", "bz", "ca", "cd", "cg", "ch", "ci", "cl",
        "cm", "cn", "co", "cr", "cv", "cy", "cz", "de", "dk", "dm", "do",
        "dz", "ec", "ee", "eg", "es", "fi", "fj", "fm", "fr", "ga", "gb",
        "gd", "ge", "gh", "gm", "gr", "gt", "gw", "gy", "hk", "hn", "hr",
        "hu", "id", "ie", "il", "in", "iq", "is", "it", "jm", "jo", "jp",
        "ke", "kg", "kh", "kn", "kr", "kw", "ky", "kz", "la", "lb", "lc",
        "lk", "lr", "lt", "lu", "lv", "ly", "ma", "md", "me", "mg", "mk",
        "ml", "mm", "mn", "mo", "mr", "ms", "mt", "mu", "mv", "mw", "mx",
        "my", "mz", "na", "ne", "ng", "ni", "nl", "no", "np", "nr", "nz",
        "om", "pa", "pe", "pg", "ph", "pk", "pl", "pt", "pw", "py", "qa",
        "ro", "rs", "ru", "rw", "sa", "sb", "sc", "se", "sg", "si", "sk",
        "sl", "sn", "sr", "st", "sv", "sz", "tc", "td", "th", "tj", "tm",
        "tn", "to", "tr", "tt", "tw", "tz", "ua", "ug", "us", "uy", "uz",
        "vc", "ve", "vg", "vn", "vu", "xk", "ye", "za", "zm", "zw",
    ]
    private static let supportedStorefrontSet = Set(supportedStorefronts)

    public enum ClientError: Error, Equatable, LocalizedError, Sendable {
        case invalidAppID
        case invalidStorefront
        case invalidPage
        case invalidResponse
        case requestFailed(statusCode: Int)

        public var errorDescription: String? {
            switch self {
            case .invalidAppID: "The App Store identifier must be a positive number."
            case .invalidStorefront: "The App Store country code is invalid."
            case .invalidPage: "Apple review feeds support pages 1 through 10."
            case .invalidResponse: "Apple returned an invalid review response."
            case let .requestFailed(statusCode): "Apple returned HTTP status \(statusCode)."
            }
        }
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func reviews(appID: Int64, storefront: String, page: Int) async throws -> [AppReview] {
        let url = try Self.reviewFeedURL(appID: appID, storefront: storefront, page: page)
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw ClientError.requestFailed(statusCode: response.statusCode)
        }
        return try AppStoreReviewResponseParser.parse(data, appID: appID, storefront: storefront)
    }

    public static func reviewFeedURL(appID: Int64, storefront: String, page: Int) throws -> URL {
        guard appID > 0 else { throw ClientError.invalidAppID }
        guard (1...10).contains(page) else { throw ClientError.invalidPage }
        let code = storefront.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard supportedStorefrontSet.contains(code) else {
            throw ClientError.invalidStorefront
        }
        guard let url = URL(
            string: "https://itunes.apple.com/\(code)/rss/customerreviews/page=\(page)/id=\(appID)/sortby=mostrecent/json"
        ) else {
            throw ClientError.invalidStorefront
        }
        return url
    }
}

public enum AppStoreReviewResponseParser {
    public static func parse(_ data: Data, appID: Int64, storefront: String) throws -> [AppReview] {
        let response = try JSONDecoder().decode(ReviewFeedResponse.self, from: data)
        let code = storefront.lowercased()
        return response.feed.entries.compactMap { entry in
            guard
                let sourceID = normalized(entry.id?.label),
                Int64(sourceID) != nil,
                let ratingText = normalized(entry.rating?.label),
                let rating = Int(ratingText),
                (1...5).contains(rating),
                let updatedText = normalized(entry.updated?.label),
                let updatedAt = parseDate(updatedText),
                let title = normalized(entry.title?.label),
                let body = normalized(entry.content?.label)
            else {
                return nil
            }
            return AppReview(
                id: "\(code)-\(sourceID)",
                sourceID: sourceID,
                appID: appID,
                storefront: code,
                rating: rating,
                title: title,
                body: body,
                reviewerName: normalized(entry.author?.name?.label) ?? "Unknown reviewer",
                version: normalized(entry.version?.label),
                updatedAt: updatedAt
            )
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public struct ReviewSyncService: Sendable {
    private let client: any AppReviewFetching
    private let maximumConcurrentStorefronts: Int

    public init(client: any AppReviewFetching, maximumConcurrentStorefronts: Int = 8) {
        self.client = client
        self.maximumConcurrentStorefronts = max(maximumConcurrentStorefronts, 1)
    }

    public func sync(
        appID: Int64,
        storefronts: [String],
        pagesPerStorefront: Int = 1
    ) async -> ReviewSyncResult {
        let pagesToFetch = min(max(pagesPerStorefront, 1), 10)
        var seenStorefronts: Set<String> = []
        let uniqueStorefronts = storefronts.compactMap { value -> String? in
            let code = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return code.isEmpty || !seenStorefronts.insert(code).inserted ? nil : code
        }

        let outcomes = await withTaskGroup(
            of: IndexedReviewSyncOutcome?.self,
            returning: [IndexedReviewSyncOutcome].self
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

            var values: [IndexedReviewSyncOutcome] = []
            while let value = await group.next() {
                if let value { values.append(value) }
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
        var completedStorefronts: [String] = []
        var failures: [ReviewSyncFailure] = []
        for outcome in outcomes {
            reviews.append(contentsOf: outcome.reviews.filter { seenReviewIDs.insert($0.id).inserted })
            if let failureMessage = outcome.failureMessage {
                failures.append(ReviewSyncFailure(storefront: outcome.storefront, message: failureMessage))
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
        client: any AppReviewFetching,
        appID: Int64,
        storefront: String,
        pagesToFetch: Int,
        index: Int
    ) async -> IndexedReviewSyncOutcome? {
        var reviews: [AppReview] = []
        do {
            for page in 1...pagesToFetch {
                try Task.checkCancellation()
                let pageReviews = try await client.reviews(appID: appID, storefront: storefront, page: page)
                try Task.checkCancellation()
                reviews.append(contentsOf: pageReviews)
                if pageReviews.isEmpty { break }
            }
            return IndexedReviewSyncOutcome(
                index: index,
                storefront: storefront,
                reviews: reviews,
                failureMessage: nil
            )
        } catch is CancellationError {
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }
            let message = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
            return IndexedReviewSyncOutcome(
                index: index,
                storefront: storefront,
                reviews: reviews,
                failureMessage: message
            )
        }
    }
}

private struct IndexedReviewSyncOutcome: Sendable {
    var index: Int
    var storefront: String
    var reviews: [AppReview]
    var failureMessage: String?
}

private struct ReviewFeedResponse: Decodable {
    var feed: ReviewFeed
}

private struct ReviewFeed: Decodable {
    var entries: [ReviewFeedEntry]

    private enum CodingKeys: String, CodingKey {
        case entry
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let values = try? container.decode([LossyReviewEntry].self, forKey: .entry) {
            entries = values.compactMap(\.value)
        } else if let value = try? container.decode(LossyReviewEntry.self, forKey: .entry) {
            entries = value.value.map { [$0] } ?? []
        } else {
            entries = []
        }
    }
}

private struct LossyReviewEntry: Decodable {
    var value: ReviewFeedEntry?

    init(from decoder: Decoder) throws {
        value = try? ReviewFeedEntry(from: decoder)
    }
}

private struct ReviewFeedEntry: Decodable {
    var id: ReviewLabel?
    var author: ReviewAuthor?
    var updated: ReviewLabel?
    var rating: ReviewLabel?
    var version: ReviewLabel?
    var title: ReviewLabel?
    var content: ReviewLabel?

    private enum CodingKeys: String, CodingKey {
        case id
        case author
        case updated
        case rating = "im:rating"
        case version = "im:version"
        case title
        case content
    }
}

private struct ReviewAuthor: Decodable {
    var name: ReviewLabel?
}

private struct ReviewLabel: Decodable {
    var label: String
}
