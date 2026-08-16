import Foundation

public enum TrackedAppKind: String, Codable, CaseIterable, Sendable {
    case owned
    case competitor
}

public enum ResearchProjectKind: String, Codable, Sendable {
    case manual
    case appSearchPresence
}

public enum KeywordSource: String, Sendable {
    case legacyPopularity
    case csvImport
    case appleAds
    case appleSearchHints
    case manual

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "tryAstro":
            self = .legacyPopularity
        case "astroCSV":
            self = .csvImport
        default:
            guard let source = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown keyword source: \(value)"
                )
            }
            self = source
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension KeywordSource: Codable {}

public struct StoreTarget: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(language)-\(store)" }

    public var language: String
    public var store: String

    public init(language: String, store: String) {
        self.language = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.store = store.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct KeywordRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String { deduplicationKey }

    public var keyword: String
    public var language: String
    public var store: String
    public var country: String?
    public var genre: String
    public var popularity: Int
    public var relevanceScore: Double
    public var opportunityScore: Double
    public var intentTags: [String]
    public var matchedTerms: [String]
    public var month: String?
    public var sourceID: String?
    public var source: KeywordSource
    public var isFavorite: Bool
    public var isTracked: Bool?
    public var updatedAt: Date?
    public var popularityCheckedAt: Date?
    public var note: String?

    public init(
        keyword: String,
        language: String,
        store: String,
        country: String? = nil,
        genre: String,
        popularity: Int,
        relevanceScore: Double = 0,
        opportunityScore: Double = 0,
        intentTags: [String] = [],
        matchedTerms: [String] = [],
        month: String? = nil,
        sourceID: String? = nil,
        source: KeywordSource = .manual,
        isFavorite: Bool = false,
        isTracked: Bool? = nil,
        updatedAt: Date? = nil,
        popularityCheckedAt: Date? = nil,
        note: String? = nil
    ) {
        self.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.store = store.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.country = country?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.genre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        self.popularity = popularity
        self.relevanceScore = relevanceScore
        self.opportunityScore = opportunityScore
        self.intentTags = intentTags
        self.matchedTerms = matchedTerms
        self.month = month
        self.sourceID = sourceID
        self.source = source
        self.isFavorite = isFavorite
        self.isTracked = isTracked
        self.updatedAt = updatedAt
        self.popularityCheckedAt = popularityCheckedAt
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isActivelyTracked: Bool {
        isTracked ?? (source != .legacyPopularity && source != .appleSearchHints)
    }

    public var hasPopularityMeasurement: Bool {
        switch source {
        case .legacyPopularity, .csvImport, .appleAds:
            true
        case .appleSearchHints, .manual:
            false
        }
    }

    public var deduplicationKey: String {
        [keyword, language, store, genre]
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased() }
            .joined(separator: "|")
    }

    public static func merge(existing: [KeywordRecord], incoming: [KeywordRecord]) -> [KeywordRecord] {
        var byKey: [String: KeywordRecord] = [:]

        for record in existing {
            byKey[record.deduplicationKey] = record
        }

        for record in incoming {
            let key = record.deduplicationKey
            var refreshed = record
            let current = byKey[key]
            refreshed.isFavorite = record.isFavorite || current?.isFavorite == true
            refreshed.isTracked = record.isActivelyTracked || current?.isActivelyTracked == true
            if refreshed.note?.isEmpty != false {
                refreshed.note = current?.note
            }
            refreshed.popularityCheckedAt = record.popularityCheckedAt ?? current?.popularityCheckedAt
            byKey[key] = refreshed
        }

        let trackedKeywords = Set(byKey.values.filter(\.isActivelyTracked).map(\.trackingKey))
        for (key, record) in byKey where trackedKeywords.contains(record.trackingKey) {
            var trackedRecord = record
            trackedRecord.isTracked = true
            byKey[key] = trackedRecord
        }

        return byKey.values.sorted {
            if $0.opportunityScore != $1.opportunityScore {
                return $0.opportunityScore > $1.opportunityScore
            }
            if $0.popularity != $1.popularity {
                return $0.popularity > $1.popularity
            }
            return $0.keyword.localizedCaseInsensitiveCompare($1.keyword) == .orderedAscending
        }
    }

    private var trackingKey: String {
        [keyword, language, store]
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased() }
            .joined(separator: "|")
    }

}

public struct RankingObservation: Identifiable, Codable, Hashable, Sendable {
    public var id: String {
        "\(projectID.uuidString)|\(keyword.lowercased())|\(store.lowercased())|\(adamID)"
    }

    public var projectID: UUID
    public var keyword: String
    public var store: String
    public var adamID: Int64
    public var appName: String
    public var developerName: String
    public var bundleID: String
    public var primaryGenre: String
    public var appStoreURL: URL?
    public var artworkURL: URL?
    public var userRatingCount: Int?
    public var position: Int
    public var checkedAt: Date
}

public struct RankingScan: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(projectID.uuidString)|\(keyword.lowercased())|\(store.lowercased())" }

    public var projectID: UUID
    public var keyword: String
    public var store: String
    public var checkedAt: Date
    public var resultCount: Int

    public init(projectID: UUID, keyword: String, store: String, checkedAt: Date, resultCount: Int) {
        self.projectID = projectID
        self.keyword = keyword
        self.store = store.lowercased()
        self.checkedAt = checkedAt
        self.resultCount = resultCount
    }
}

public struct ResearchProject: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var topic: String
    public var targets: [StoreTarget]
    public var genres: [String]
    public var seedKeywords: [String]
    public var focusAppAdamID: Int64?
    public var kind: ResearchProjectKind
    public var keywords: [KeywordRecord]
    public var rankingObservations: [RankingObservation]
    public var rankingScans: [RankingScan]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        topic: String,
        targets: [StoreTarget],
        genres: [String],
        seedKeywords: [String],
        focusAppAdamID: Int64? = nil,
        kind: ResearchProjectKind = .manual,
        keywords: [KeywordRecord] = [],
        rankingObservations: [RankingObservation] = [],
        rankingScans: [RankingScan] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targets = targets
        self.genres = genres
        self.seedKeywords = seedKeywords
        self.focusAppAdamID = focusAppAdamID
        self.kind = kind
        self.keywords = keywords
        self.rankingObservations = rankingObservations
        self.rankingScans = rankingScans
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case topic
        case targets
        case genres
        case seedKeywords
        case focusAppAdamID
        case kind
        case keywords
        case rankingObservations
        case rankingScans
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        topic = try container.decode(String.self, forKey: .topic)
        targets = try container.decode([StoreTarget].self, forKey: .targets)
        genres = try container.decode([String].self, forKey: .genres)
        seedKeywords = try container.decode([String].self, forKey: .seedKeywords)
        focusAppAdamID = try container.decodeIfPresent(Int64.self, forKey: .focusAppAdamID)
        kind = try container.decodeIfPresent(ResearchProjectKind.self, forKey: .kind) ?? .manual
        keywords = try container.decode([KeywordRecord].self, forKey: .keywords)
        rankingObservations = try container.decodeIfPresent([RankingObservation].self, forKey: .rankingObservations) ?? []
        rankingScans = try container.decodeIfPresent([RankingScan].self, forKey: .rankingScans) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public struct TrackedApp: Identifiable, Codable, Hashable, Sendable {
    public var id: Int64 { adamID }

    public var adamID: Int64
    public var name: String
    public var developerName: String
    public var bundleID: String
    public var primaryStore: String
    public var primaryGenre: String
    public var appStoreURL: URL?
    public var artworkURL: URL?
    public var version: String?
    public var releaseDate: Date?
    public var currentVersionReleaseDate: Date?
    public var averageRating: Double?
    public var ratingCount: Int?
    public var kind: TrackedAppKind
    public var addedAt: Date

    public init(
        adamID: Int64,
        name: String,
        developerName: String,
        bundleID: String,
        primaryStore: String,
        primaryGenre: String = "",
        appStoreURL: URL? = nil,
        artworkURL: URL? = nil,
        version: String? = nil,
        releaseDate: Date? = nil,
        currentVersionReleaseDate: Date? = nil,
        averageRating: Double? = nil,
        ratingCount: Int? = nil,
        kind: TrackedAppKind,
        addedAt: Date = Date()
    ) {
        self.adamID = adamID
        self.name = name
        self.developerName = developerName
        self.bundleID = bundleID
        self.primaryStore = primaryStore.lowercased()
        self.primaryGenre = primaryGenre
        self.appStoreURL = appStoreURL
        self.artworkURL = artworkURL
        self.version = version
        self.releaseDate = releaseDate
        self.currentVersionReleaseDate = currentVersionReleaseDate
        self.averageRating = averageRating
        self.ratingCount = ratingCount
        self.kind = kind
        self.addedAt = addedAt
    }
}

public struct ASOLibrary: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var projects: [ResearchProject]
    public var apps: [TrackedApp]

    public init(
        schemaVersion: Int = ASOLibrary.currentSchemaVersion,
        projects: [ResearchProject] = [],
        apps: [TrackedApp] = []
    ) {
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.apps = apps
    }
}

public struct StoreAppSearchResult: Identifiable, Hashable, Sendable {
    public var id: Int64 { adamID }

    public var adamID: Int64
    public var name: String
    public var developerName: String
    public var bundleID: String
    public var primaryGenre: String
    public var appStoreURL: URL?
    public var position: Int
    public var artworkURL: URL?
    public var userRatingCount: Int?
    public var averageRating: Double?
    public var version: String?
    public var releaseDate: Date?
    public var currentVersionReleaseDate: Date?

    public init(
        adamID: Int64,
        name: String,
        developerName: String,
        bundleID: String,
        primaryGenre: String,
        appStoreURL: URL?,
        position: Int,
        artworkURL: URL? = nil,
        userRatingCount: Int? = nil,
        averageRating: Double? = nil,
        version: String? = nil,
        releaseDate: Date? = nil,
        currentVersionReleaseDate: Date? = nil
    ) {
        self.adamID = adamID
        self.name = name
        self.developerName = developerName
        self.bundleID = bundleID
        self.primaryGenre = primaryGenre
        self.appStoreURL = appStoreURL
        self.position = position
        self.artworkURL = artworkURL
        self.userRatingCount = userRatingCount
        self.averageRating = averageRating
        self.version = version
        self.releaseDate = releaseDate
        self.currentVersionReleaseDate = currentVersionReleaseDate
    }
}

public extension TrackedApp {
    func updatingMetadata(from result: StoreAppSearchResult) -> TrackedApp {
        guard result.adamID == adamID else { return self }
        var value = self
        if !result.name.isEmpty { value.name = result.name }
        if !result.developerName.isEmpty { value.developerName = result.developerName }
        if !result.bundleID.isEmpty { value.bundleID = result.bundleID }
        if !result.primaryGenre.isEmpty { value.primaryGenre = result.primaryGenre }
        value.appStoreURL = result.appStoreURL ?? value.appStoreURL
        value.artworkURL = result.artworkURL ?? value.artworkURL
        value.version = result.version ?? value.version
        value.releaseDate = result.releaseDate ?? value.releaseDate
        value.currentVersionReleaseDate = result.currentVersionReleaseDate ?? value.currentVersionReleaseDate
        value.averageRating = result.averageRating ?? value.averageRating
        value.ratingCount = result.userRatingCount ?? value.ratingCount
        return value
    }
}

public struct AppRankingSummary: Identifiable, Hashable, Sendable {
    public var id: String { "\(adamID)|\(store.lowercased())" }

    public var adamID: Int64
    public var store: String
    public var name: String
    public var developerName: String
    public var bundleID: String
    public var primaryGenre: String
    public var appStoreURL: URL?
    public var artworkURL: URL?
    public var keywordCount: Int
    public var bestPosition: Int
    public var averagePosition: Double
    public var keywords: [String]
}

public struct KeywordSearchMetrics: Hashable, Sendable {
    public var difficulty: Int?
    public var focusAppPosition: Int?
    public var topApps: [RankingObservation]

    public init(difficulty: Int?, focusAppPosition: Int?, topApps: [RankingObservation]) {
        self.difficulty = difficulty
        self.focusAppPosition = focusAppPosition
        self.topApps = topApps
    }
}
