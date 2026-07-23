import Foundation

struct Storefront: RawRepresentable, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        guard Self.supportedCodes.contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    private init(_ supportedCode: String) {
        rawValue = supportedCode
    }

    static let allCases: [Storefront] = codes.map(Storefront.init)

    // Named conveniences retained for source compatibility with the original catalog.
    static let unitedStates = Storefront("us")
    static let unitedKingdom = Storefront("gb")
    static let canada = Storefront("ca")
    static let australia = Storefront("au")
    static let germany = Storefront("de")
    static let france = Storefront("fr")
    static let czechia = Storefront("cz")
    static let japan = Storefront("jp")
    static let india = Storefront("in")
    static let brazil = Storefront("br")

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
        Locale(identifier: "en_US").localizedString(
            forRegionCode: rawValue.uppercased()
        ) ?? rawValue.uppercased()
    }

    var flagEmoji: String {
        rawValue
            .uppercased()
            .unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }

    var accessibilityLabel: String { displayName }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let code = try container.decode(String.self)
        guard let storefront = Storefront(rawValue: code) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported App Store country or region code: \(code)"
            )
        }
        self = storefront
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static let codes = [
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

    private static let supportedCodes = Set(codes)
}
