import CryptoKit
import Foundation
import Testing
@testable import ReadRevsCore

@Test("Apple Ads client secret contains the required ES256 claims and a valid signature")
func appleAdsClientSecretIsValidES256JWT() throws {
    let privateKey = P256.Signing.PrivateKey()
    let credentials = AppleAdsCredentials(
        clientID: "SEARCHADS.client",
        teamID: "SEARCHADS.team",
        keyID: "key-id",
        privateKeyRawRepresentation: privateKey.rawRepresentation
    )
    let issuedAt = Date(timeIntervalSince1970: 1_700_000_000)

    let token = try AppleAdsClientSecret.make(
        credentials: credentials,
        issuedAt: issuedAt,
        lifetime: 900
    )

    let components = token.split(separator: ".")
    #expect(components.count == 3)
    let header = try jsonObject(fromBase64URL: String(components[0]))
    let claims = try jsonObject(fromBase64URL: String(components[1]))
    #expect(header["alg"] as? String == "ES256")
    #expect(header["kid"] as? String == "key-id")
    #expect(claims["iss"] as? String == "SEARCHADS.team")
    #expect(claims["sub"] as? String == "SEARCHADS.client")
    #expect(claims["aud"] as? String == "https://appleid.apple.com")
    #expect(claims["iat"] as? Int == 1_700_000_000)
    #expect(claims["exp"] as? Int == 1_700_000_900)

    let signedData = Data("\(components[0]).\(components[1])".utf8)
    let signatureData = try #require(Data(base64URL: String(components[2])))
    let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
    #expect(privateKey.publicKey.isValidSignature(signature, for: signedData))
}

@Test("Apple Ads key pair exports an uploadable P-256 public key")
func appleAdsKeyPairExportsPublicPEM() throws {
    let keyPair = AppleAdsKeyPair.generate()

    #expect(keyPair.privateKeyRawRepresentation.count == 32)
    #expect(keyPair.publicKeyPEM.hasPrefix("-----BEGIN PUBLIC KEY-----\n"))
    #expect(keyPair.publicKeyPEM.hasSuffix("\n-----END PUBLIC KEY-----"))

    let pemBody = keyPair.publicKeyPEM
        .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
        .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
        .replacingOccurrences(of: "\n", with: "")
    let subjectPublicKeyInfo = try #require(Data(base64Encoded: pemBody))
    #expect(subjectPublicKeyInfo.count == 91)
    #expect(subjectPublicKeyInfo.suffix(65).first == 0x04)
}

@Test("Apple Ads credentials collapse an identical identifier pasted on multiple lines")
func appleAdsCredentialsNormalizeRepeatedPaste() {
    let privateKey = P256.Signing.PrivateKey()
    let credentials = AppleAdsCredentials(
        clientID: "SEARCHADS.client\n\nSEARCHADS.client",
        teamID: "SEARCHADS.team\nSEARCHADS.team",
        keyID: "key-id\n\nkey-id\n\nkey-id",
        privateKeyRawRepresentation: privateKey.rawRepresentation
    )

    #expect(credentials.clientID == "SEARCHADS.client")
    #expect(credentials.teamID == "SEARCHADS.team")
    #expect(credentials.keyID == "key-id")
}

@Test("Stored Apple Ads credentials decode before a research app has been selected")
func legacyAppleAdsCredentialsRemainDecodable() throws {
    struct LegacyCredentials: Encodable {
        let clientID: String
        let teamID: String
        let keyID: String
        let privateKeyRawRepresentation: Data
        let adAccountID: Int64
        let adAccountName: String
    }

    let data = try JSONEncoder().encode(
        LegacyCredentials(
            clientID: "SEARCHADS.client",
            teamID: "SEARCHADS.team",
            keyID: "key-id",
            privateKeyRawRepresentation: Data(repeating: 1, count: 32),
            adAccountID: 42,
            adAccountName: "Research Account"
        )
    )

    let credentials = try JSONDecoder().decode(AppleAdsCredentials.self, from: data)

    #expect(credentials.isConnected)
    #expect(credentials.researchAppAdamID == nil)
    #expect(credentials.researchAppName == nil)
}

@Test("Apple Ads account lookup exchanges OAuth credentials and parses ACLs")
func appleAdsAccountLookupUsesOAuthAndParsesACLs() async throws {
    let transport = AppleAdsTestTransport(responses: [
        .json(#"{"access_token":"access-token","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}"#),
        .json(#"{"result":{"acls":[{"adAccount":{"id":123456789,"name":"Example Ads","orgId":987654321},"roles":["API Read Only"]}]}}"#),
    ])
    let client = AppleAdsPlatformClient(
        transport: transport,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let accounts = try await client.fetchAccounts(credentials: appleAdsTestCredentials())

    #expect(accounts == [
        AppleAdsAccountAccess(
            id: 123_456_789,
            name: "Example Ads",
            organizationID: 987_654_321,
            roles: ["API Read Only"]
        ),
    ])
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests[0].url?.scheme == "https")
    #expect(requests[0].url?.host == "appleid.apple.com")
    #expect(requests[0].url?.path == "/auth/oauth2/token")
    #expect(requests[0].url?.query == nil)
    #expect(requests[0].httpMethod == "POST")
    #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    let form = try formValues(from: requests[0])
    #expect(form["grant_type"] == "client_credentials")
    #expect(form["client_id"] == "SEARCHADS.client")
    #expect(form["scope"] == "searchadsorg")
    #expect(form["client_secret"]?.split(separator: ".").count == 3)
    #expect(requests[1].url?.absoluteString == "https://api.ads.apple.com/v1/acls")
    #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
    #expect(requests[1].value(forHTTPHeaderField: "X-AP-Context") == nil)
}

@Test("Apple Ads explains an OAuth invalid_client response")
func appleAdsExplainsInvalidOAuthClient() async throws {
    let transport = AppleAdsTestTransport(responses: [
        .json(#"{"error":"invalid_client"}"#, statusCode: 400),
    ])
    let client = AppleAdsPlatformClient(
        transport: transport,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    await #expect(throws: AppleAdsPlatformError.invalidOAuthClient) {
        _ = try await client.fetchAccounts(credentials: appleAdsTestCredentials())
    }
    #expect(
        AppleAdsPlatformError.invalidOAuthClient.localizedDescription.contains(
            "same Apple Ads API key"
        )
    )
}

@Test("Apple Ads keyword suggestions are app-aware and include a discovery score")
func appleAdsKeywordSuggestionsUseDocumentedV1Query() async throws {
    let transport = AppleAdsTestTransport(responses: [
        .json(#"{"access_token":"access-token","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}"#),
        .json(#"{"result":[{"text":"world flags","popularity":82},{"text":"geography quiz","popularity":71}],"pagination":{"offset":0,"pageSize":20}}"#),
    ])
    let client = AppleAdsPlatformClient(
        transport: transport,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let suggestions = try await client.fetchKeywordSuggestions(
        terms: ["flags", "geography"],
        promotedObjectID: 1_234_567_890,
        target: StoreTarget(language: "en", store: "us"),
        credentials: appleAdsTestCredentials(adAccountID: 42)
    )

    #expect(suggestions == [
        AppleAdsKeywordSuggestion(text: "world flags", popularity: 82),
        AppleAdsKeywordSuggestion(text: "geography quiz", popularity: 71),
    ])
    let request = try #require(await transport.requests.last)
    #expect(request.url?.absoluteString == "https://api.ads.apple.com/v1/suggestions/keywords/query")
    #expect(request.value(forHTTPHeaderField: "X-AP-Context") == "adAccountId=42")
    let body = try jsonBody(from: request)
    let filters = try #require(body["filters"] as? [[String: Any]])
    #expect(filterValue("promotedObjectId", in: filters) as? [String] == ["1234567890"])
    #expect(filterValue("promotedObjectType", in: filters) as? [String] == ["APPSTORE_APP"])
    #expect(filterValue("terms", in: filters) as? [String] == ["flags", "geography"])
    #expect(filterValue("countriesOrRegions", in: filters) as? [String] == ["US"])
    #expect(body["sorting"] == nil)
}

@Test("Apple Ads owned-app search uses the selected account organization")
func appleAdsOwnedAppSearchUsesOrganizationContext() async throws {
    let transport = AppleAdsTestTransport(responses: [
        .json(#"{"access_token":"access-token","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}"#),
        .json(#"{"result":{"acls":[{"adAccount":{"id":42,"name":"Example Ads","orgId":987654321},"roles":["API Read Only"]}]}}"#),
        .json(#"{"data":[{"adamId":555000111,"appName":"Example Flashcards","developerName":"Example Developer","countryOrRegionCodes":["US","CZ"]}],"pagination":{"totalResults":1,"startIndex":0,"itemsPerPage":1},"error":null}"#),
    ])
    let client = AppleAdsPlatformClient(
        transport: transport,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let apps = try await client.searchOwnedApps(
        matching: "quiz",
        credentials: appleAdsTestCredentials(adAccountID: 42)
    )

    #expect(apps == [
        AppleAdsPromotableApp(
            adamID: 555_000_111,
            name: "Example Flashcards",
            developerName: "Example Developer",
            countryOrRegionCodes: ["US", "CZ"]
        ),
    ])
    let requests = await transport.requests
    #expect(requests.count == 3)
    let request = requests[2]
    #expect(request.httpMethod == "GET")
    #expect(request.url?.host == "api.searchads.apple.com")
    #expect(request.url?.path == "/api/v5/search/apps")
    #expect(request.value(forHTTPHeaderField: "X-AP-Context") == "orgId=987654321")
    let query = try queryValues(from: request)
    #expect(query["query"] == "quiz")
    #expect(query["returnOwnedApps"] == "true")
    #expect(query["limit"] == "1000")
}

@Test("Apple Ads popularity report uses the previous complete week and parses direct metrics")
func appleAdsPopularityReportUsesDocumentedV1Query() async throws {
    let transport = AppleAdsTestTransport(responses: [
        .json(#"{"access_token":"access-token","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}"#),
        .json(#"{"result":{"rows":[{"week":"2026-08-09","countryOrRegion":"US","genre":"EDUCATION","searchTerm":"world flags","rankInGenre":3,"searchPopularityInGenre":91,"searchPopularity1to100":84,"searchPopularity1to5":5}]},"pagination":{"offset":0,"pageSize":20},"error":null}"#),
    ])
    let now = ISO8601DateFormatter().date(from: "2026-08-16T12:00:00Z")!
    let client = AppleAdsPlatformClient(transport: transport, now: { now })

    let rows = try await client.fetchSearchTermPopularity(
        target: StoreTarget(language: "en", store: "us"),
        genre: "Education",
        credentials: appleAdsTestCredentials(adAccountID: 42)
    )

    #expect(rows == [
        AppleAdsSearchTermPopularity(
            period: "2026-08-09",
            countryOrRegion: "US",
            genre: "EDUCATION",
            searchTerm: "world flags",
            rankInGenre: 3,
            popularityInGenre: 91,
            popularity: 84,
            popularityTier: 5
        ),
    ])
    let request = try #require(await transport.requests.last)
    #expect(request.url?.absoluteString == "https://api.ads.apple.com/v1/insights/apps/search-term-popularity/query")
    let body = try jsonBody(from: request)
    let filters = try #require(body["filters"] as? [[String: Any]])
    #expect(filterValue("countryOrRegion", in: filters) as? String == "US")
    #expect(filterValue("genre", in: filters) as? String == "EDUCATION")
    let timeRange = try #require(body["timeRange"] as? [String: Any])
    #expect(timeRange["start"] as? String == "2026-08-09")
    #expect(timeRange["end"] as? String == "2026-08-15")
    #expect(timeRange["granularity"] as? String == "WEEKLY_SUN_SAT")
    let fields = try #require(body["fields"] as? [String])
    #expect(Set(fields) == Set([
        "countryOrRegion",
        "genre",
        "searchTerm",
        "rankInGenre",
        "searchPopularityInGenre",
        "searchPopularity1to100",
        "searchPopularity1to5",
    ]))
    let sorting = try #require(body["sorting"] as? [[String: Any]])
    #expect(sorting.first?["field"] as? String == "rankInGenre")
    #expect(sorting.first?["sortOrder"] as? String == "ASC")
    #expect(sorting.first?["order"] == nil)
}

@Test("Apple Ads popularity report filters a batch of exact search terms")
func appleAdsPopularityReportFiltersExactTerms() async throws {
    let transport = AppleAdsTestTransport(responses: [
        .json(#"{"access_token":"access-token","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}"#),
        .json(#"{"result":{"rows":[{"week":"2026-08-09","countryOrRegion":"US","genre":"GAMES","searchTerm":"idle","rankInGenre":193,"searchPopularityInGenre":71,"searchPopularity1to100":61,"searchPopularity1to5":4}]},"pagination":{"offset":0,"pageSize":20},"error":null}"#),
    ])
    let now = ISO8601DateFormatter().date(from: "2026-08-16T12:00:00Z")!
    let client = AppleAdsPlatformClient(transport: transport, now: { now })

    let rows = try await client.fetchSearchTermPopularity(
        target: StoreTarget(language: "en", store: "us"),
        genre: "Games",
        terms: ["idle", "idle games", "idle tower defense"],
        credentials: appleAdsTestCredentials(adAccountID: 42)
    )

    #expect(rows.map(\.searchTerm) == ["idle"])
    #expect(await transport.requests.count == 2)
    let request = try #require(await transport.requests.last)
    let body = try jsonBody(from: request)
    let filters = try #require(body["filters"] as? [[String: Any]])
    #expect(filterValue("searchTerm", in: filters) as? [String] == [
        "idle",
        "idle games",
        "idle tower defense",
    ])
    let searchTermFilter = try #require(
        filters.first { $0["field"] as? String == "searchTerm" }
    )
    #expect(searchTermFilter["operator"] as? String == "IN")
}

@Test("Apple Ads popularity falls back one week when the newest completed report is not published")
func appleAdsPopularityFallsBackToOlderPublishedWeek() async throws {
    let transport = AppleAdsTestTransport(responses: [
        .json(#"{"access_token":"access-token","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}"#),
        .json(#"{"result":{"rows":[]},"pagination":{"offset":0,"pageSize":0},"error":null}"#),
        .json(#"{"result":{"rows":[{"week":"2026-08-02","countryOrRegion":"US","genre":"EDUCATION","searchTerm":"flags","rankInGenre":4,"searchPopularityInGenre":80,"searchPopularity1to100":74,"searchPopularity1to5":4}]},"pagination":{"offset":0,"pageSize":20},"error":null}"#),
    ])
    let now = ISO8601DateFormatter().date(from: "2026-08-16T12:00:00Z")!
    let client = AppleAdsPlatformClient(transport: transport, now: { now })

    let rows = try await client.fetchSearchTermPopularity(
        target: StoreTarget(language: "en", store: "us"),
        genre: "Education",
        credentials: appleAdsTestCredentials(adAccountID: 42)
    )

    #expect(rows.map(\.period) == ["2026-08-02"])
    let requests = await transport.requests
    #expect(requests.count == 3)
    let fallbackBody = try jsonBody(from: requests[2])
    let fallbackRange = try #require(fallbackBody["timeRange"] as? [String: Any])
    #expect(fallbackRange["start"] as? String == "2026-08-02")
    #expect(fallbackRange["end"] as? String == "2026-08-08")
}

@Test("Apple Ads popularity paginates without a total count until Apple returns an empty page")
func appleAdsPopularityPaginatesWithoutTotalCount() async throws {
    let transport = AppleAdsTestTransport(responses: [
        .json(#"{"access_token":"access-token","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}"#),
        .json(#"{"result":{"rows":[{"week":"2026-08-09","countryOrRegion":"US","genre":"GAMES","searchTerm":"first","rankInGenre":1,"searchPopularityInGenre":100,"searchPopularity1to100":90,"searchPopularity1to5":5}]},"pagination":{"offset":0,"pageSize":1},"error":null}"#),
        .json(#"{"result":{"rows":[{"week":"2026-08-09","countryOrRegion":"US","genre":"GAMES","searchTerm":"second","rankInGenre":2,"searchPopularityInGenre":99,"searchPopularity1to100":89,"searchPopularity1to5":5}]},"pagination":{"offset":1,"pageSize":1},"error":null}"#),
        .json(#"{"result":{"rows":[]},"pagination":{"offset":2,"pageSize":0},"error":null}"#),
    ])
    let now = ISO8601DateFormatter().date(from: "2026-08-16T12:00:00Z")!
    let client = AppleAdsPlatformClient(transport: transport, now: { now })

    let rows = try await client.fetchSearchTermPopularity(
        target: StoreTarget(language: "en", store: "us"),
        genre: "Games",
        credentials: appleAdsTestCredentials(adAccountID: 42)
    )

    #expect(rows.map(\.searchTerm) == ["first", "second"])
    let requests = await transport.requests
    #expect(requests.count == 4)
    let secondPage = try jsonBody(from: requests[2])
    let secondPagination = try #require(secondPage["pagination"] as? [String: Any])
    #expect(secondPagination["offset"] as? Int == 1)
    let finalPage = try jsonBody(from: requests[3])
    let finalPagination = try #require(finalPage["pagination"] as? [String: Any])
    #expect(finalPagination["offset"] as? Int == 2)
}

@Test("Apple Ads retries a rate-limited request using Retry-After")
func appleAdsRetriesRateLimitResponse() async throws {
    let delayRecorder = RetryDelayRecorder()
    let transport = AppleAdsTestTransport(responses: [
        .json(#"{"access_token":"access-token","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}"#),
        .json(#"{"error":{"message":"Too many requests"}}"#, statusCode: 429, headers: ["Retry-After": "2"]),
        .json(#"{"result":{"acls":[]}}"#),
    ])
    let client = AppleAdsPlatformClient(
        transport: transport,
        now: { Date(timeIntervalSince1970: 1_700_000_000) },
        sleep: { duration in await delayRecorder.record(duration) }
    )

    let accounts = try await client.fetchAccounts(credentials: appleAdsTestCredentials())

    #expect(accounts.isEmpty)
    #expect(await delayRecorder.delays == [.seconds(2)])
    #expect(await transport.requests.count == 3)
}

@Test("Concurrent Apple Ads requests share one OAuth token exchange")
func appleAdsSharesConcurrentTokenExchange() async throws {
    let transport = DelayedTokenAppleAdsTransport()
    let client = AppleAdsPlatformClient(
        transport: transport,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    let credentials = appleAdsTestCredentials()

    async let first = client.fetchAccounts(credentials: credentials)
    async let second = client.fetchAccounts(credentials: credentials)
    _ = try await (first, second)

    #expect(await transport.tokenRequestCount == 1)
    #expect(await transport.aclRequestCount == 2)
}

private func appleAdsTestCredentials(adAccountID: Int64? = nil) -> AppleAdsCredentials {
    let privateKey = try! P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 1, count: 32))
    return AppleAdsCredentials(
        clientID: "SEARCHADS.client",
        teamID: "SEARCHADS.team",
        keyID: "key-id",
        privateKeyRawRepresentation: privateKey.rawRepresentation,
        adAccountID: adAccountID,
        adAccountName: adAccountID == nil ? nil : "Example Ads"
    )
}

private actor AppleAdsTestTransport: AppleAdsHTTPTransport {
    struct Response: Sendable {
        let statusCode: Int
        let data: Data
        let headers: [String: String]

        static func json(
            _ value: String,
            statusCode: Int = 200,
            headers: [String: String] = [:]
        ) -> Response {
            Response(statusCode: statusCode, data: Data(value.utf8), headers: headers)
        }
    }

    private var queuedResponses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) {
        queuedResponses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = queuedResponses.removeFirst()
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"].merging(
                response.headers,
                uniquingKeysWith: { _, new in new }
            )
        )!
        return (response.data, httpResponse)
    }
}

private actor RetryDelayRecorder {
    private(set) var delays: [Duration] = []

    func record(_ duration: Duration) {
        delays.append(duration)
    }
}

private actor DelayedTokenAppleAdsTransport: AppleAdsHTTPTransport {
    private(set) var tokenRequestCount = 0
    private(set) var aclRequestCount = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let isTokenRequest = request.url?.host == "appleid.apple.com"
        if isTokenRequest {
            tokenRequestCount += 1
            try await Task.sleep(for: .milliseconds(30))
        } else {
            aclRequestCount += 1
        }
        let payload = isTokenRequest
            ? #"{"access_token":"access-token","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}"#
            : #"{"result":{"acls":[]}}"#
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(payload.utf8), response)
    }
}

private func jsonObject(fromBase64URL value: String) throws -> [String: Any] {
    let data = try #require(Data(base64URL: value))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func queryValues(from request: URLRequest) throws -> [String: String] {
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
        ($0.name, $0.value ?? "")
    })
}

private func formValues(from request: URLRequest) throws -> [String: String] {
    let data = try #require(request.httpBody)
    let body = try #require(String(data: data, encoding: .utf8))
    var components = URLComponents()
    components.percentEncodedQuery = body
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
        ($0.name, $0.value ?? "")
    })
}

private func jsonBody(from request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func filterValue(_ field: String, in filters: [[String: Any]]) -> Any? {
    filters.first { $0["field"] as? String == field }?["value"]
}

private extension Data {
    init?(base64URL value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
