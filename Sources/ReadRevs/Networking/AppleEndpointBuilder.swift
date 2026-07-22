import Foundation

enum AppleEndpointBuilder {
    enum Error: Swift.Error, Equatable, LocalizedError, Sendable {
        case invalidAppID
        case invalidPage
        case unableToBuildURL

        var errorDescription: String? {
            switch self {
            case .invalidAppID:
                "The App Store identifier must be a positive number."
            case .invalidPage:
                "Apple review feeds support pages 1 through 10."
            case .unableToBuildURL:
                "The Apple endpoint URL could not be created."
            }
        }
    }

    static func reviewFeedURL(
        appID: Int64,
        storefront: Storefront,
        page: Int
    ) throws -> URL {
        guard appID > 0 else { throw Error.invalidAppID }
        guard (1 ... 10).contains(page) else { throw Error.invalidPage }

        let endpoint =
            "https://itunes.apple.com/\(storefront.rawValue)/rss/customerreviews/" +
            "page=\(page)/id=\(appID)/sortby=mostrecent/json"
        guard let url = URL(string: endpoint) else {
            throw Error.unableToBuildURL
        }
        return url
    }

    static func lookupURL(
        appID: Int64,
        storefront: Storefront
    ) throws -> URL {
        guard appID > 0 else { throw Error.invalidAppID }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [
            URLQueryItem(name: "id", value: String(appID)),
            URLQueryItem(name: "country", value: storefront.rawValue),
        ]

        guard let url = components.url else {
            throw Error.unableToBuildURL
        }
        return url
    }
}
