import Foundation

enum AppleResponseDecoder {
    enum Error: Swift.Error, Equatable, LocalizedError, Sendable {
        case appNotFound
        case notSoftware
        case invalidLookupResponse

        var errorDescription: String? {
            switch self {
            case .appNotFound:
                "No app was found for that identifier in the selected App Store."
            case .notSoftware:
                "That identifier does not belong to an App Store app."
            case .invalidLookupResponse:
                "Apple returned incomplete app information."
            }
        }
    }

    static func reviews(
        from data: Data,
        appID: Int64,
        storefront: Storefront
    ) throws -> [AppReview] {
        let response = try JSONDecoder().decode(ReviewFeedResponse.self, from: data)

        return response.feed.entries.compactMap { entry in
            guard
                let sourceID = normalized(entry.id?.label),
                Int64(sourceID) != nil,
                let ratingText = normalized(entry.rating?.label),
                let rating = Int(ratingText),
                (1 ... 5).contains(rating),
                let updatedText = normalized(entry.updated?.label),
                let updatedAt = date(from: updatedText),
                let title = normalized(entry.title?.label),
                let body = normalized(entry.content?.label)
            else {
                return nil
            }

            return AppReview(
                id: "\(storefront.rawValue)-\(sourceID)",
                sourceID: sourceID,
                appID: appID,
                storefront: storefront,
                rating: rating,
                title: title,
                body: body,
                reviewerName: normalized(entry.author?.name?.label) ?? "Unknown reviewer",
                version: normalized(entry.version?.label),
                updatedAt: updatedAt
            )
        }
    }

    static func app(
        from data: Data,
        storefront: Storefront
    ) throws -> AppMetadata {
        let response = try JSONDecoder().decode(LookupResponse.self, from: data)
        guard response.resultCount != 0 else {
            throw Error.appNotFound
        }
        guard let result = response.results.compactMap(\.value).first else {
            if response.resultCount == 0 {
                throw Error.appNotFound
            }
            throw Error.invalidLookupResponse
        }
        guard isSoftware(result) else {
            throw Error.notSoftware
        }
        guard let app = appMetadata(from: result, storefront: storefront) else {
            throw Error.invalidLookupResponse
        }

        return app
    }

    static func apps(
        from data: Data,
        storefront: Storefront
    ) throws -> [AppMetadata] {
        let response = try JSONDecoder().decode(LookupResponse.self, from: data)
        return response.results
            .compactMap(\.value)
            .compactMap { appMetadata(from: $0, storefront: storefront) }
    }

    private static func appMetadata(
        from result: LookupResult,
        storefront: Storefront
    ) -> AppMetadata? {
        guard
            isSoftware(result),
            let appID = result.trackID,
            appID > 0,
            let name = normalized(result.trackName)
        else {
            return nil
        }

        return AppMetadata(
            appID: appID,
            name: name,
            sellerName: normalized(result.sellerName) ?? "",
            artworkURL: result.artworkURL.flatMap(URL.init(string:)),
            version: normalized(result.version) ?? "",
            primaryGenre: normalized(result.primaryGenreName) ?? "",
            releaseDate: result.releaseDate.flatMap(date(from:)),
            currentVersionReleaseDate: result.currentVersionReleaseDate.flatMap(date(from:)),
            averageRating: result.averageUserRating,
            ratingCount: result.userRatingCount,
            appStoreURL: result.trackViewURL.flatMap(URL.init(string:)),
            primaryStorefront: storefront
        )
    }

    private static func isSoftware(_ result: LookupResult) -> Bool {
        normalized(result.wrapperType)?.lowercased() == "software"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct ReviewFeedResponse: Decodable {
    let feed: ReviewFeed
}

private struct ReviewFeed: Decodable {
    let entries: [ReviewFeedEntry]

    private enum CodingKeys: String, CodingKey {
        case entry
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let values = try? container.decode([LossyDecodable<ReviewFeedEntry>].self, forKey: .entry) {
            entries = values.compactMap(\.value)
        } else if let value = try? container.decode(LossyDecodable<ReviewFeedEntry>.self, forKey: .entry) {
            entries = value.value.map { [$0] } ?? []
        } else {
            entries = []
        }
    }
}

private struct ReviewFeedEntry: Decodable {
    let id: LabelValue?
    let author: ReviewAuthor?
    let updated: LabelValue?
    let rating: LabelValue?
    let version: LabelValue?
    let title: LabelValue?
    let content: LabelValue?

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
    let name: LabelValue?
}

private struct LabelValue: Decodable {
    let label: String
}

private struct LookupResponse: Decodable {
    let resultCount: Int?
    let results: [LossyDecodable<LookupResult>]

    private enum CodingKeys: String, CodingKey {
        case resultCount
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultCount = try container.decodeIfPresent(Int.self, forKey: .resultCount)
        results = try container.decodeIfPresent(
            [LossyDecodable<LookupResult>].self,
            forKey: .results
        ) ?? []
    }
}

private struct LookupResult: Decodable {
    let wrapperType: String?
    let kind: String?
    let trackID: Int64?
    let trackName: String?
    let sellerName: String?
    let artworkURL: String?
    let version: String?
    let primaryGenreName: String?
    let releaseDate: String?
    let currentVersionReleaseDate: String?
    let averageUserRating: Double?
    let userRatingCount: Int?
    let trackViewURL: String?

    private enum CodingKeys: String, CodingKey {
        case wrapperType
        case kind
        case trackID = "trackId"
        case trackName
        case sellerName
        case artworkURL = "artworkUrl100"
        case version
        case primaryGenreName
        case releaseDate
        case currentVersionReleaseDate
        case averageUserRating
        case userRatingCount
        case trackViewURL = "trackViewUrl"
    }
}
