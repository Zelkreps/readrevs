import ReadRevsCore
import CryptoKit
import Foundation
import Testing
@testable import ReadRevsApp

@Test("Apple Ads research app discovery skips apps outside the connected account")
func appleAdsResearchAppDiscoverySelectsAnAccessibleOwnedApp() async throws {
    let credentials = researchTestCredentials()
    let store = ResearchCredentialStore(credentials: credentials)
    let client = ResearchAppleAdsClient(ownedApps: [
        AppleAdsPromotableApp(
            adamID: 22,
            name: "My Promotable App",
            developerName: "Developer",
            countryOrRegionCodes: ["US"]
        ),
    ])
    let resolver = AppleAdsResearchAppResolver(client: client, credentialStore: store)

    let resolved = try await resolver.resolve(
        credentials: credentials,
        candidates: [
            researchTestApp(id: 11, name: "Competitor"),
            researchTestApp(id: 22, name: "My Promotable App"),
        ],
        target: StoreTarget(language: "en", store: "us")
    )

    #expect(resolved.researchAppAdamID == 22)
    #expect(resolved.researchAppName == "My Promotable App")
    #expect(await client.promotedObjectIDs == [22])
    #expect(try store.load()?.researchAppAdamID == 22)
}

@Test("Apple Ads exact popularity never falls back to keyword suggestions")
func appleAdsExactPopularityLeavesTermsMissingFromReportsUnavailable() async throws {
    var credentials = researchTestCredentials()
    credentials.researchAppAdamID = 22
    credentials.researchAppName = "My Promotable App"
    let client = ResearchAppleAdsClient(popularityByTerm: [
        "idle tower defense": 5,
        "the tower": 7,
    ])

    let resolution = try await AppleAdsKeywordPopularityResolver(client: client).resolve(
        keywords: ["idle tower defense", "the tower"],
        target: StoreTarget(language: "en", store: "us"),
        genres: ["Education"],
        credentials: credentials,
        checkedAt: Date(timeIntervalSinceReferenceDate: 123)
    )

    #expect(resolution.records.isEmpty)
    #expect(resolution.unmatchedKeywords == ["idle tower defense", "the tower"])
    #expect(await client.reportRequests == ["us|Education"])
    #expect(await client.suggestionTerms.isEmpty)
    #expect(await client.promotedObjectIDs.isEmpty)
}

@Test("Apple Ads popularity report wins over a matching keyword suggestion score")
func appleAdsPopularityUsesOnlyTheStorefrontReport() async throws {
    var credentials = researchTestCredentials()
    credentials.researchAppAdamID = 22
    credentials.researchAppName = "My Promotable App"
    let client = ResearchAppleAdsClient(
        popularityByTerm: ["world flags": 84],
        reportPopularityByTerm: ["world flags": 61]
    )

    let resolution = try await AppleAdsKeywordPopularityResolver(client: client).resolve(
        keywords: ["world flags"],
        target: StoreTarget(language: "en", store: "us"),
        genres: ["Education"],
        credentials: credentials,
        checkedAt: Date(timeIntervalSinceReferenceDate: 123)
    )

    let record = try #require(resolution.records.first)
    #expect(record.popularity == 61)
    #expect(record.hasPopularityMeasurement)
    #expect(record.intentTags == ["apple-ads-popularity"])
    #expect(resolution.unmatchedKeywords.isEmpty)
    #expect(await client.reportRequests == ["us|Education"])
    #expect(await client.suggestionTerms.isEmpty)
}

private func researchTestCredentials() -> AppleAdsCredentials {
    let privateKey = try! P256.Signing.PrivateKey(
        rawRepresentation: Data(repeating: 6, count: 32)
    )
    return AppleAdsCredentials(
        clientID: "SEARCHADS.client",
        teamID: "SEARCHADS.team",
        keyID: "key-id",
        privateKeyRawRepresentation: privateKey.rawRepresentation,
        adAccountID: 42,
        adAccountName: "Research Account"
    )
}

private func researchTestApp(id: Int64, name: String) -> TrackedApp {
    TrackedApp(
        adamID: id,
        name: name,
        developerName: "Developer",
        bundleID: "com.example.\(id)",
        primaryStore: "us",
        kind: .owned
    )
}

private final class ResearchCredentialStore: AppleAdsCredentialStoring, @unchecked Sendable {
    private var credentials: AppleAdsCredentials?

    init(credentials: AppleAdsCredentials?) {
        self.credentials = credentials
    }

    func load() throws -> AppleAdsCredentials? { credentials }
    func save(_ credentials: AppleAdsCredentials) throws { self.credentials = credentials }
    func delete() throws { credentials = nil }
}

private actor ResearchAppleAdsClient: AppleAdsPlatformProviding {
    private let ownedApps: [AppleAdsPromotableApp]
    private let deniedAppIDs: Set<Int64>
    private let popularityByTerm: [String: Int]
    private let reportPopularityByTerm: [String: Int]
    private(set) var promotedObjectIDs: [Int64] = []
    private(set) var suggestionTerms: [[String]] = []
    private(set) var reportRequests: [String] = []

    init(
        ownedApps: [AppleAdsPromotableApp] = [],
        deniedAppIDs: Set<Int64> = [],
        popularityByTerm: [String: Int] = [:],
        reportPopularityByTerm: [String: Int] = [:]
    ) {
        self.ownedApps = ownedApps
        self.deniedAppIDs = deniedAppIDs
        self.popularityByTerm = popularityByTerm
        self.reportPopularityByTerm = reportPopularityByTerm
    }

    func fetchAccounts(credentials: AppleAdsCredentials) async throws -> [AppleAdsAccountAccess] {
        []
    }

    func searchOwnedApps(
        matching query: String,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsPromotableApp] {
        ownedApps
    }

    func fetchKeywordSuggestions(
        terms: [String],
        promotedObjectID: Int64,
        target: StoreTarget,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsKeywordSuggestion] {
        promotedObjectIDs.append(promotedObjectID)
        suggestionTerms.append(terms)
        if deniedAppIDs.contains(promotedObjectID) {
            throw AppleAdsPlatformError.httpStatus(
                400,
                "App not found or access denied for adamId: \(promotedObjectID)"
            )
        }
        guard terms.count == 1,
              let term = terms.first,
              let popularity = popularityByTerm[term]
        else {
            return []
        }
        return [AppleAdsKeywordSuggestion(text: term, popularity: popularity)]
    }

    func fetchSearchTermPopularity(
        target: StoreTarget,
        genre: String,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsSearchTermPopularity] {
        reportRequests.append("\(target.store)|\(genre)")
        return reportPopularityByTerm.map { term, popularity in
            AppleAdsSearchTermPopularity(
                period: "2026-08-09",
                countryOrRegion: target.store.uppercased(),
                genre: genre.uppercased(),
                searchTerm: term,
                rankInGenre: 1,
                popularityInGenre: popularity,
                popularity: popularity,
                popularityTier: 4
            )
        }
    }
}
