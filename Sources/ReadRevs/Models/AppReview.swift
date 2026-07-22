import Foundation

struct AppReview: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let appID: Int64
    let storefront: Storefront
    let rating: Int
    let title: String
    let body: String
    let reviewerName: String
    let version: String?
    let updatedAt: Date
}
