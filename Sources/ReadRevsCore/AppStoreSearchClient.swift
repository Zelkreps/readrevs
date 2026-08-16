import Foundation

public protocol AppStoreSearching: Sendable {
    func search(term: String, country: String, limit: Int) async throws -> [StoreAppSearchResult]
}

public protocol AppStoreLookupProviding: Sendable {
    func lookup(adamID: Int64, country: String) async throws -> StoreAppSearchResult?
}

public struct ITunesAppStoreClient: AppStoreSearching, AppStoreLookupProviding {
    private static let requestLimiter = RequestRateLimiter(minimumInterval: 3.1)

    public var baseURL: URL
    public var lookupBaseURL: URL

    public init(
        baseURL: URL = URL(string: "https://itunes.apple.com/search")!,
        lookupBaseURL: URL = URL(string: "https://itunes.apple.com/lookup")!
    ) {
        self.baseURL = baseURL
        self.lookupBaseURL = lookupBaseURL
    }

    public func search(term: String, country: String, limit: Int = 100) async throws -> [StoreAppSearchResult] {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country.lowercased()),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200))),
            URLQueryItem(name: "explicit", value: "No"),
        ]
        guard let url = components.url else { throw ServiceError.invalidURL }

        return try AppStoreSearchResponseParser.parse(try await request(url))
    }

    public func lookup(adamID: Int64, country: String) async throws -> StoreAppSearchResult? {
        guard var components = URLComponents(url: lookupBaseURL, resolvingAgainstBaseURL: false) else {
            throw ServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "id", value: String(adamID)),
            URLQueryItem(name: "country", value: country.lowercased()),
            URLQueryItem(name: "entity", value: "software"),
        ]
        guard let url = components.url else { throw ServiceError.invalidURL }

        return try AppStoreSearchResponseParser.parse(try await request(url)).first
    }

    private func request(_ url: URL, retries: Int = 1) async throws -> Data {
        try await Self.requestLimiter.waitForTurn()
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        if httpResponse.statusCode == 429, retries > 0 {
            let retryAfter = httpResponse.retryAfterDelay(fallback: 5)
            await Self.requestLimiter.deferRequests(by: max(retryAfter, 3.1))
            return try await request(url, retries: retries - 1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ServiceError.httpStatus(httpResponse.statusCode)
        }
        return data
    }
}

public enum AppStoreIdentifier {
    public static func parse(_ value: String) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let numeric = Int64(trimmed) {
            return numeric
        }

        guard let expression = try? NSRegularExpression(pattern: #"(?:^|/)id(\d+)(?:[/?]|$)"#) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = expression.firstMatch(in: trimmed, range: range),
              let identifierRange = Range(match.range(at: 1), in: trimmed)
        else {
            return nil
        }
        return Int64(trimmed[identifierRange])
    }
}

public enum AppStoreSearchResponseParser {
    public static func parse(_ data: Data) throws -> [StoreAppSearchResult] {
        let payload = try JSONDecoder().decode(AppStorePayload.self, from: data)
        return payload.results.enumerated().compactMap { offset, item in
            guard let adamID = item.trackID, let name = item.trackName, !name.isEmpty else {
                return nil
            }
            return StoreAppSearchResult(
                adamID: adamID,
                name: name,
                developerName: item.artistName ?? item.sellerName ?? "",
                bundleID: item.bundleID ?? "",
                primaryGenre: item.primaryGenreName ?? "",
                appStoreURL: item.trackViewURL.flatMap(URL.init(string:)),
                position: offset + 1,
                artworkURL: (item.artworkURL100 ?? item.artworkURL60).flatMap(URL.init(string:)),
                userRatingCount: item.userRatingCount,
                averageRating: item.averageUserRating,
                version: normalized(item.version),
                releaseDate: item.releaseDate.flatMap(parseDate),
                currentVersionReleaseDate: item.currentVersionReleaseDate.flatMap(parseDate)
            )
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct AppStorePayload: Decodable {
    var resultCount: Int
    var results: [AppStoreItem]
}

private struct AppStoreItem: Decodable {
    var trackID: Int64?
    var trackName: String?
    var artistName: String?
    var sellerName: String?
    var bundleID: String?
    var primaryGenreName: String?
    var trackViewURL: String?
    var artworkURL60: String?
    var artworkURL100: String?
    var userRatingCount: Int?
    var averageUserRating: Double?
    var version: String?
    var releaseDate: String?
    var currentVersionReleaseDate: String?

    enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
        case trackName
        case artistName
        case sellerName
        case bundleID = "bundleId"
        case primaryGenreName
        case trackViewURL = "trackViewUrl"
        case artworkURL60 = "artworkUrl60"
        case artworkURL100 = "artworkUrl100"
        case userRatingCount
        case averageUserRating
        case version
        case releaseDate
        case currentVersionReleaseDate
    }
}
