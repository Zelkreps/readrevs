import Foundation

protocol AppleReviewClientProtocol: Sendable {
    func reviews(
        appID: Int64,
        storefront: Storefront,
        page: Int
    ) async throws -> [AppReview]

    func lookup(
        appID: Int64,
        storefront: Storefront
    ) async throws -> AppMetadata
}

struct AppleReviewClient: AppleReviewClientProtocol, Sendable {
    enum Error: Swift.Error, Equatable, LocalizedError, Sendable {
        case invalidResponse
        case requestFailed(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Apple returned an invalid network response."
            case let .requestFailed(statusCode):
                "Apple returned HTTP status \(statusCode)."
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func reviews(
        appID: Int64,
        storefront: Storefront,
        page: Int
    ) async throws -> [AppReview] {
        let url = try AppleEndpointBuilder.reviewFeedURL(
            appID: appID,
            storefront: storefront,
            page: page
        )
        let data = try await data(from: url)
        return try AppleResponseDecoder.reviews(
            from: data,
            appID: appID,
            storefront: storefront
        )
    }

    func lookup(
        appID: Int64,
        storefront: Storefront
    ) async throws -> AppMetadata {
        let url = try AppleEndpointBuilder.lookupURL(
            appID: appID,
            storefront: storefront
        )
        let data = try await data(from: url)
        return try AppleResponseDecoder.app(from: data, storefront: storefront)
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw Error.requestFailed(statusCode: response.statusCode)
        }
        return data
    }
}

typealias URLSessionAppleReviewClient = AppleReviewClient
