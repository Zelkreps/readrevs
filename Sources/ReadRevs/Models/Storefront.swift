import Foundation

enum Storefront: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case unitedStates = "us"
    case unitedKingdom = "gb"
    case canada = "ca"
    case australia = "au"
    case germany = "de"
    case france = "fr"
    case czechia = "cz"
    case japan = "jp"
    case india = "in"
    case brazil = "br"

    static let priority: [Storefront] = [
        .unitedStates,
        .unitedKingdom,
        .canada,
        .australia,
        .germany,
        .france,
        .czechia,
        .japan,
        .india,
        .brazil,
    ]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unitedStates: "United States"
        case .unitedKingdom: "United Kingdom"
        case .canada: "Canada"
        case .australia: "Australia"
        case .germany: "Germany"
        case .france: "France"
        case .czechia: "Czechia"
        case .japan: "Japan"
        case .india: "India"
        case .brazil: "Brazil"
        }
    }

    var flagEmoji: String {
        rawValue
            .uppercased()
            .unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }

    var accessibilityLabel: String {
        displayName
    }
}
