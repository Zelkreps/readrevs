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

@Test("Apple Ads exact popularity requests each unmatched keyword separately")
func appleAdsExactPopularityUsesSingleTermRequestsAndResearchApp() async throws {
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
        genres: [],
        credentials: credentials,
        checkedAt: Date(timeIntervalSinceReferenceDate: 123)
    )

    #expect(Dictionary(uniqueKeysWithValues: resolution.records.map {
        ($0.keyword, $0.popularity)
    }) == [
        "idle tower defense": 5,
        "the tower": 7,
    ])
    #expect(resolution.unmatchedKeywords.isEmpty)
    #expect(await client.suggestionTerms == [
        ["idle tower defense"],
        ["the tower"],
    ])
    #expect(await client.promotedObjectIDs == [22, 22])
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
    private(set) var promotedObjectIDs: [Int64] = []
    private(set) var suggestionTerms: [[String]] = []

    init(
        ownedApps: [AppleAdsPromotableApp] = [],
        deniedAppIDs: Set<Int64> = [],
        popularityByTerm: [String: Int] = [:]
    ) {
        self.ownedApps = ownedApps
        self.deniedAppIDs = deniedAppIDs
        self.popularityByTerm = popularityByTerm
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
        []
    }
}
