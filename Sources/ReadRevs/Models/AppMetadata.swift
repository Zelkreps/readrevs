import Foundation

struct AppMetadata: Identifiable, Codable, Hashable, Sendable {
    var id: Int64 { appID }

    let appID: Int64
    let name: String
    let sellerName: String
    let artworkURL: URL?
    let version: String
    let primaryGenre: String
    let releaseDate: Date?
    let currentVersionReleaseDate: Date?
    let averageRating: Double?
    let ratingCount: Int?
    let appStoreURL: URL?
    let primaryStorefront: Storefront

    init(
        appID: Int64,
        name: String,
        sellerName: String = "",
        artworkURL: URL? = nil,
        version: String = "",
        primaryGenre: String = "",
        releaseDate: Date? = nil,
        currentVersionReleaseDate: Date? = nil,
        averageRating: Double? = nil,
        ratingCount: Int? = nil,
        appStoreURL: URL? = nil,
        primaryStorefront: Storefront = .unitedStates
    ) {
        self.appID = appID
        self.name = name
        self.sellerName = sellerName
        self.artworkURL = artworkURL
        self.version = version
        self.primaryGenre = primaryGenre
        self.releaseDate = releaseDate
        self.currentVersionReleaseDate = currentVersionReleaseDate
        self.averageRating = averageRating
        self.ratingCount = ratingCount
        self.appStoreURL = appStoreURL
        self.primaryStorefront = primaryStorefront
    }
}
