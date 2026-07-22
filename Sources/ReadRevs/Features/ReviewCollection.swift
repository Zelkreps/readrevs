import Foundation

enum ReviewSortOrder: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case newest
    case oldest
    case highestRating
    case lowestRating

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .highestRating: "Highest rating"
        case .lowestRating: "Lowest rating"
        }
    }
}

struct ReviewFilters: Codable, Hashable, Sendable {
    var searchText: String
    var rating: Int?
    var storefront: Storefront?
    var version: String?
    var sortOrder: ReviewSortOrder

    init(
        searchText: String = "",
        rating: Int? = nil,
        storefront: Storefront? = nil,
        version: String? = nil,
        sortOrder: ReviewSortOrder = .newest
    ) {
        self.searchText = searchText
        self.rating = rating
        self.storefront = storefront
        self.version = version
        self.sortOrder = sortOrder
    }
}

struct ReviewCollection: Codable, Hashable, Sendable {
    let reviews: [AppReview]

    init(reviews: [AppReview]) {
        self.reviews = reviews
    }

    var averageRating: Double? {
        guard !reviews.isEmpty else { return nil }
        let total = reviews.reduce(0) { $0 + $1.rating }
        return Double(total) / Double(reviews.count)
    }

    var storefrontCount: Int {
        Set(reviews.map(\.storefront)).count
    }

    var versions: [String] {
        var seen: Set<String> = []
        return reviews
            .sorted(by: Self.newestFirst)
            .compactMap(\.version)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func count(for rating: Int) -> Int {
        reviews.count { $0.rating == rating }
    }

    func filtered(using filters: ReviewFilters) -> [AppReview] {
        let query = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return reviews
            .filter { review in
                if
                    !query.isEmpty,
                    !Self.matchesSearch(review, query: query)
                {
                    return false
                }
                if let rating = filters.rating, review.rating != rating {
                    return false
                }
                if let storefront = filters.storefront, review.storefront != storefront {
                    return false
                }
                if let version = filters.version, review.version != version {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                switch filters.sortOrder {
                case .newest:
                    Self.newestFirst(lhs, rhs)
                case .oldest:
                    Self.oldestFirst(lhs, rhs)
                case .highestRating:
                    lhs.rating == rhs.rating
                        ? Self.newestFirst(lhs, rhs)
                        : lhs.rating > rhs.rating
                case .lowestRating:
                    lhs.rating == rhs.rating
                        ? Self.newestFirst(lhs, rhs)
                        : lhs.rating < rhs.rating
                }
            }
    }

    private static func matchesSearch(_ review: AppReview, query: String) -> Bool {
        [review.title, review.body, review.reviewerName, review.version ?? ""]
            .contains { value in
                value.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
    }

    private static func newestFirst(_ lhs: AppReview, _ rhs: AppReview) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id < rhs.id
    }

    private static func oldestFirst(_ lhs: AppReview, _ rhs: AppReview) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.id < rhs.id
    }
}
