import CryptoKit
import Foundation

public struct AppleAdsCredentials: Codable, Equatable, Sendable {
    public var clientID: String
    public var teamID: String
    public var keyID: String
    public var privateKeyRawRepresentation: Data
    public var adAccountID: Int64?
    public var adAccountName: String?
    public var researchAppAdamID: Int64?
    public var researchAppName: String?

    public init(
        clientID: String,
        teamID: String,
        keyID: String,
        privateKeyRawRepresentation: Data,
        adAccountID: Int64? = nil,
        adAccountName: String? = nil,
        researchAppAdamID: Int64? = nil,
        researchAppName: String? = nil
    ) {
        self.clientID = Self.normalizedIdentifier(clientID)
        self.teamID = Self.normalizedIdentifier(teamID)
        self.keyID = Self.normalizedIdentifier(keyID)
        self.privateKeyRawRepresentation = privateKeyRawRepresentation
        self.adAccountID = adAccountID
        self.adAccountName = adAccountName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.researchAppAdamID = researchAppAdamID
        self.researchAppName = researchAppName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var hasOAuthIdentifiers: Bool {
        !clientID.isEmpty && !teamID.isEmpty && !keyID.isEmpty
    }

    public var isConnected: Bool {
        hasOAuthIdentifiers && adAccountID != nil
    }

    public var hasResearchApp: Bool {
        researchAppAdamID != nil
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = lines.first,
              lines.count > 1,
              lines.allSatisfy({ $0 == first })
        else {
            return trimmed
        }
        return first
    }
}

public struct AppleAdsKeyPair: Equatable, Sendable {
    public let privateKeyRawRepresentation: Data
    public let publicKeyPEM: String

    public init(privateKeyRawRepresentation: Data, publicKeyPEM: String) {
        self.privateKeyRawRepresentation = privateKeyRawRepresentation
        self.publicKeyPEM = publicKeyPEM
    }

    public static func generate() -> AppleAdsKeyPair {
        let privateKey = P256.Signing.PrivateKey()
        return AppleAdsKeyPair(
            privateKeyRawRepresentation: privateKey.rawRepresentation,
            publicKeyPEM: publicKeyPEM(for: privateKey.publicKey)
        )
    }

    public static func publicKeyPEM(privateKeyRawRepresentation: Data) throws -> String {
        let privateKey: P256.Signing.PrivateKey
        do {
            privateKey = try P256.Signing.PrivateKey(rawRepresentation: privateKeyRawRepresentation)
        } catch {
            throw AppleAdsPlatformError.invalidPrivateKey
        }
        return publicKeyPEM(for: privateKey.publicKey)
    }

    private static func publicKeyPEM(for publicKey: P256.Signing.PublicKey) -> String {
        // SubjectPublicKeyInfo header for an id-ecPublicKey / prime256v1 key.
        let header = Data([
            0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE,
            0x3D, 0x02, 0x01, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D,
            0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
        ])
        let encoded = (header + publicKey.x963Representation).base64EncodedString()
        let lines = stride(from: 0, to: encoded.count, by: 64).map { offset in
            let start = encoded.index(encoded.startIndex, offsetBy: offset)
            let end = encoded.index(start, offsetBy: min(64, encoded.count - offset))
            return String(encoded[start..<end])
        }
        return (["-----BEGIN PUBLIC KEY-----"] + lines + ["-----END PUBLIC KEY-----"])
            .joined(separator: "\n")
    }
}

public enum AppleAdsClientSecret {
    public static func make(
        credentials: AppleAdsCredentials,
        issuedAt: Date = Date(),
        lifetime: TimeInterval = 15 * 60
    ) throws -> String {
        guard credentials.hasOAuthIdentifiers else {
            throw AppleAdsPlatformError.incompleteCredentials
        }
        guard lifetime > 0, lifetime <= 180 * 24 * 60 * 60 else {
            throw AppleAdsPlatformError.invalidClientSecretLifetime
        }

        let privateKey: P256.Signing.PrivateKey
        do {
            privateKey = try P256.Signing.PrivateKey(
                rawRepresentation: credentials.privateKeyRawRepresentation
            )
        } catch {
            throw AppleAdsPlatformError.invalidPrivateKey
        }

        let issuedAtSeconds = Int(issuedAt.timeIntervalSince1970)
        let header: [String: String] = [
            "alg": "ES256",
            "kid": credentials.keyID,
        ]
        let claims = ClientSecretClaims(
            issuer: credentials.teamID,
            issuedAt: issuedAtSeconds,
            expiresAt: issuedAtSeconds + Int(lifetime),
            audience: "https://appleid.apple.com",
            subject: credentials.clientID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedHeader = try encoder.encode(header).base64URLEncodedString()
        let encodedClaims = try encoder.encode(claims).base64URLEncodedString()
        let signingInput = Data("\(encodedHeader).\(encodedClaims)".utf8)
        let signature = try privateKey.signature(for: signingInput)
        return "\(encodedHeader).\(encodedClaims).\(signature.rawRepresentation.base64URLEncodedString())"
    }
}

public struct AppleAdsAccountAccess: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let organizationID: Int64
    public let roles: [String]

    public init(id: Int64, name: String, organizationID: Int64, roles: [String]) {
        self.id = id
        self.name = name
        self.organizationID = organizationID
        self.roles = roles
    }

    public var grantsReadOnlyAPIAccess: Bool {
        guard !roles.isEmpty else { return false }
        let allowedRoles: Set<String> = [
            "api account read only",
            "api read only",
            "account read only",
            "read only",
            "readonly",
        ]
        return roles.allSatisfy { role in
            allowedRoles.contains(
                role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        }
    }
}

public struct AppleAdsKeywordSuggestion: Codable, Equatable, Sendable {
    public let text: String
    public let popularity: Int

    public init(text: String, popularity: Int) {
        self.text = text
        self.popularity = popularity
    }
}

public struct AppleAdsPromotableApp: Codable, Equatable, Identifiable, Sendable {
    public let adamID: Int64
    public let name: String
    public let developerName: String
    public let countryOrRegionCodes: [String]

    public var id: Int64 { adamID }

    public init(
        adamID: Int64,
        name: String,
        developerName: String,
        countryOrRegionCodes: [String]
    ) {
        self.adamID = adamID
        self.name = name
        self.developerName = developerName
        self.countryOrRegionCodes = countryOrRegionCodes
    }

    enum CodingKeys: String, CodingKey {
        case adamID = "adamId"
        case name = "appName"
        case developerName
        case countryOrRegionCodes
    }
}

public struct AppleAdsSearchTermPopularity: Equatable, Sendable {
    public let period: String
    public let countryOrRegion: String
    public let genre: String
    public let searchTerm: String
    public let rankInGenre: Int
    public let popularityInGenre: Int
    public let popularity: Int
    public let popularityTier: Int

    public init(
        period: String,
        countryOrRegion: String,
        genre: String,
        searchTerm: String,
        rankInGenre: Int,
        popularityInGenre: Int,
        popularity: Int,
        popularityTier: Int
    ) {
        self.period = period
        self.countryOrRegion = countryOrRegion
        self.genre = genre
        self.searchTerm = searchTerm
        self.rankInGenre = rankInGenre
        self.popularityInGenre = popularityInGenre
        self.popularity = popularity
        self.popularityTier = popularityTier
    }
}

public protocol AppleAdsPlatformProviding: Sendable {
    func fetchAccounts(credentials: AppleAdsCredentials) async throws -> [AppleAdsAccountAccess]

    func searchOwnedApps(
        matching query: String,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsPromotableApp]

    func fetchKeywordSuggestions(
        terms: [String],
        promotedObjectID: Int64,
        target: StoreTarget,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsKeywordSuggestion]

    func fetchSearchTermPopularity(
        target: StoreTarget,
        genre: String,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsSearchTermPopularity]

    func fetchSearchTermPopularity(
        target: StoreTarget,
        genre: String,
        terms: [String],
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsSearchTermPopularity]
}

public extension AppleAdsPlatformProviding {
    func searchOwnedApps(
        matching query: String,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsPromotableApp] {
        []
    }

    func fetchSearchTermPopularity(
        target: StoreTarget,
        genre: String,
        terms: [String],
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsSearchTermPopularity] {
        let requested = Set(terms.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        })
        guard !requested.isEmpty else { return [] }
        return try await fetchSearchTermPopularity(
            target: target,
            genre: genre,
            credentials: credentials
        ).filter {
            requested.contains(
                $0.searchTerm.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            )
        }
    }
}

public protocol AppleAdsHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionAppleAdsHTTPTransport: AppleAdsHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppleAdsPlatformError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public actor AppleAdsPlatformClient: AppleAdsPlatformProviding {
    public static let shared = AppleAdsPlatformClient()

    private static let tokenURL = URL(string: "https://appleid.apple.com/auth/oauth2/token")!
    private static let baseURL = URL(string: "https://api.ads.apple.com/v1/")!
    private static let campaignBaseURL = URL(
        string: "https://api.searchads.apple.com/api/v5/"
    )!

    private let transport: any AppleAdsHTTPTransport
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var cachedAccessToken: CachedAccessToken?
    private var inFlightAccessToken: InFlightAccessToken?

    public init(
        transport: any AppleAdsHTTPTransport = URLSessionAppleAdsHTTPTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.transport = transport
        self.now = now
        self.sleep = sleep
    }

    public func fetchAccounts(
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsAccountAccess] {
        let request = URLRequest(url: Self.baseURL.appending(path: "acls"))
        let data = try await perform(request, credentials: credentials, requiresAccount: false)
        let response = try decode(ACLResponse.self, from: data)
        return response.result.acls.map { acl in
            AppleAdsAccountAccess(
                id: acl.adAccount.id,
                name: acl.adAccount.name,
                organizationID: acl.adAccount.organizationID,
                roles: acl.roles
            )
        }
    }

    public func searchOwnedApps(
        matching query: String,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsPromotableApp] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 3 else {
            throw AppleAdsPlatformError.appSearchQueryTooShort
        }
        guard let accountID = credentials.adAccountID else {
            throw AppleAdsPlatformError.missingAdAccount
        }
        guard let organizationID = try await fetchAccounts(credentials: credentials)
            .first(where: { $0.id == accountID })?
            .organizationID
        else {
            throw AppleAdsPlatformError.selectedAdAccountUnavailable
        }

        var offset = 0
        var apps: [AppleAdsPromotableApp] = []
        repeat {
            var components = URLComponents(
                url: Self.campaignBaseURL.appending(path: "search/apps"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "query", value: normalizedQuery),
                URLQueryItem(name: "limit", value: "1000"),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "returnOwnedApps", value: "true"),
            ]
            guard let url = components.url else {
                throw AppleAdsPlatformError.invalidResponse
            }
            let request = URLRequest(url: url)
            let data = try await perform(
                request,
                credentials: credentials,
                requiresAccount: false,
                context: "orgId=\(organizationID)"
            )
            let response = try decode(OwnedAppSearchResponse.self, from: data)
            apps.append(contentsOf: response.apps)
            guard let nextOffset = response.nextOffset else { break }
            offset = nextOffset
        } while true

        var seen: Set<Int64> = []
        return apps.filter { seen.insert($0.adamID).inserted }
    }

    public func fetchKeywordSuggestions(
        terms: [String],
        promotedObjectID: Int64,
        target: StoreTarget,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsKeywordSuggestion] {
        let normalizedTerms = stableUniqueTerms(terms)
        guard !normalizedTerms.isEmpty else { return [] }

        var offset = 0
        var suggestions: [AppleAdsKeywordSuggestion] = []
        repeat {
            let payload = KeywordSuggestionQuery(
                filters: [
                    .init(
                        field: "promotedObjectId",
                        operatorName: "EQUALS",
                        value: [String(promotedObjectID)]
                    ),
                    .init(
                        field: "promotedObjectType",
                        operatorName: "EQUALS",
                        value: ["APPSTORE_APP"]
                    ),
                    .init(field: "terms", operatorName: "IN", value: normalizedTerms),
                    .init(
                        field: "countriesOrRegions",
                        operatorName: "IN",
                        value: [target.store.uppercased()]
                    ),
                ],
                pagination: PaginationRequest(offset: offset, pageSize: 1_000)
            )
            let response = try await post(
                path: "suggestions/keywords/query",
                payload: payload,
                response: KeywordSuggestionResponse.self,
                credentials: credentials
            )
            suggestions.append(contentsOf: response.result)
            guard let nextOffset = nextOffset(
                pagination: response.pagination,
                resultCount: response.result.count
            ) else { break }
            offset = nextOffset
        } while true

        var seen: Set<String> = []
        return suggestions.filter {
            seen.insert($0.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
        }
    }

    public func fetchSearchTermPopularity(
        target: StoreTarget,
        genre: String,
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsSearchTermPopularity] {
        try await fetchSearchTermPopularity(
            target: target,
            genre: genre,
            terms: [],
            credentials: credentials
        )
    }

    public func fetchSearchTermPopularity(
        target: StoreTarget,
        genre: String,
        terms: [String],
        credentials: AppleAdsCredentials
    ) async throws -> [AppleAdsSearchTermPopularity] {
        let normalizedTerms = stableUniqueTerms(terms)
        var period = Self.previousCompleteWeek(containing: now())
        var rows: [SearchTermPopularityRow] = []
        for attempt in 0..<2 {
            rows = try await fetchSearchTermPopularityRows(
                target: target,
                genre: genre,
                terms: normalizedTerms,
                credentials: credentials,
                period: period
            )
            if !rows.isEmpty || attempt == 1 {
                break
            }
            period = Self.week(before: period)
        }

        return rows.map {
            AppleAdsSearchTermPopularity(
                period: $0.week ?? $0.month ?? "",
                countryOrRegion: $0.countryOrRegion,
                genre: $0.genre,
                searchTerm: $0.searchTerm,
                rankInGenre: $0.rankInGenre,
                popularityInGenre: $0.searchPopularityInGenre,
                popularity: $0.searchPopularity1to100,
                popularityTier: $0.searchPopularity1to5
            )
        }
    }

    private func fetchSearchTermPopularityRows(
        target: StoreTarget,
        genre: String,
        terms: [String],
        credentials: AppleAdsCredentials,
        period: (start: Date, end: Date)
    ) async throws -> [SearchTermPopularityRow] {
        var offset = 0
        var rows: [SearchTermPopularityRow] = []
        repeat {
            var filters = [
                SearchTermPopularityFilter(
                    field: "countryOrRegion",
                    operatorName: "EQUALS",
                    value: .scalar(target.store.uppercased())
                ),
                SearchTermPopularityFilter(
                    field: "genre",
                    operatorName: "EQUALS",
                    value: .scalar(Self.genreCode(for: genre))
                ),
            ]
            if !terms.isEmpty {
                filters.append(
                    SearchTermPopularityFilter(
                        field: "searchTerm",
                        operatorName: "IN",
                        value: .list(terms)
                    )
                )
            }
            let payload = SearchTermPopularityQuery(
                fields: [
                    "countryOrRegion",
                    "genre",
                    "searchTerm",
                    "rankInGenre",
                    "searchPopularityInGenre",
                    "searchPopularity1to100",
                    "searchPopularity1to5",
                ],
                filters: filters,
                timeRange: TimeRangeRequest(
                    start: Self.apiDateFormatter.string(from: period.start),
                    end: Self.apiDateFormatter.string(from: period.end),
                    granularity: "WEEKLY_SUN_SAT"
                ),
                sorting: [SortingRequest(field: "rankInGenre", sortOrder: "ASC")],
                pagination: PaginationRequest(offset: offset, pageSize: 1_000)
            )
            let response = try await post(
                path: "insights/apps/search-term-popularity/query",
                payload: payload,
                response: SearchTermPopularityResponse.self,
                credentials: credentials
            )
            rows.append(contentsOf: response.result.rows)
            if !terms.isEmpty {
                break
            }
            guard let nextOffset = nextOffset(
                pagination: response.pagination,
                resultCount: response.result.rows.count
            ) else { break }
            offset = nextOffset
        } while true
        return rows
    }

    private func post<Payload: Encodable, Response: Decodable>(
        path: String,
        payload: Payload,
        response: Response.Type,
        credentials: AppleAdsCredentials
    ) async throws -> Response {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let data = try await perform(request, credentials: credentials, requiresAccount: true)
        return try decode(response, from: data)
    }

    private func perform(
        _ request: URLRequest,
        credentials: AppleAdsCredentials,
        requiresAccount: Bool,
        context: String? = nil
    ) async throws -> Data {
        if requiresAccount, credentials.adAccountID == nil {
            throw AppleAdsPlatformError.missingAdAccount
        }

        var authorizedRequest = request
        let token = try await accessToken(credentials: credentials)
        authorizedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let context {
            authorizedRequest.setValue(context, forHTTPHeaderField: "X-AP-Context")
        } else if let adAccountID = credentials.adAccountID, requiresAccount {
            authorizedRequest.setValue(
                "adAccountId=\(adAccountID)",
                forHTTPHeaderField: "X-AP-Context"
            )
        }

        var (data, response) = try await sendWithRetry(authorizedRequest)
        if response.statusCode == 401 {
            cachedAccessToken = nil
            inFlightAccessToken?.task.cancel()
            inFlightAccessToken = nil
            let refreshedToken = try await accessToken(credentials: credentials)
            authorizedRequest.setValue(
                "Bearer \(refreshedToken)",
                forHTTPHeaderField: "Authorization"
            )
            (data, response) = try await sendWithRetry(authorizedRequest)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw Self.apiError(statusCode: response.statusCode, data: data)
        }
        return data
    }

    private func accessToken(credentials: AppleAdsCredentials) async throws -> String {
        guard credentials.hasOAuthIdentifiers else {
            throw AppleAdsPlatformError.incompleteCredentials
        }
        let privateKeyFingerprint = Data(
            SHA256.hash(data: credentials.privateKeyRawRepresentation)
        ).base64EncodedString()
        let credentialFingerprint = [
            credentials.clientID,
            credentials.teamID,
            credentials.keyID,
            privateKeyFingerprint,
        ].joined(separator: "|")
        let currentDate = now()
        if let cachedAccessToken,
           cachedAccessToken.credentialFingerprint == credentialFingerprint,
           cachedAccessToken.expiresAt.timeIntervalSince(currentDate) > 60
        {
            return cachedAccessToken.value
        }

        if let inFlightAccessToken,
           inFlightAccessToken.credentialFingerprint == credentialFingerprint
        {
            return try await inFlightAccessToken.task.value.value
        }

        let tokenTask = Task {
            try await requestAccessToken(
                credentials: credentials,
                currentDate: currentDate,
                credentialFingerprint: credentialFingerprint
            )
        }
        inFlightAccessToken = InFlightAccessToken(
            credentialFingerprint: credentialFingerprint,
            task: tokenTask
        )
        do {
            let token = try await tokenTask.value
            if inFlightAccessToken?.credentialFingerprint == credentialFingerprint {
                cachedAccessToken = token
                inFlightAccessToken = nil
            }
            return token.value
        } catch {
            if inFlightAccessToken?.credentialFingerprint == credentialFingerprint {
                inFlightAccessToken = nil
            }
            throw error
        }
    }

    private func requestAccessToken(
        credentials: AppleAdsCredentials,
        currentDate: Date,
        credentialFingerprint: String
    ) async throws -> CachedAccessToken {
        let clientSecret = try AppleAdsClientSecret.make(
            credentials: credentials,
            issuedAt: currentDate
        )
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "scope", value: "searchadsorg"),
        ]
        guard let formBody = components.percentEncodedQuery?.data(using: .utf8) else {
            throw AppleAdsPlatformError.invalidResponse
        }
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.httpBody = formBody
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        let (data, response) = try await sendWithRetry(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.oauthError(statusCode: response.statusCode, data: data)
        }
        let tokenResponse = try decode(AccessTokenResponse.self, from: data)
        return CachedAccessToken(
            value: tokenResponse.accessToken,
            expiresAt: currentDate.addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            credentialFingerprint: credentialFingerprint
        )
    }

    private func sendWithRetry(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let fallbackDelays = [4, 8, 16]
        var attempt = 0
        while true {
            let result: (Data, HTTPURLResponse)
            do {
                result = try await transport.data(for: request)
            } catch {
                guard attempt < fallbackDelays.count else { throw error }
                try await sleep(.seconds(fallbackDelays[attempt]))
                attempt += 1
                continue
            }

            let response = result.1
            let isTransientStatus = response.statusCode == 429
                || (500..<600).contains(response.statusCode)
            guard isTransientStatus, attempt < fallbackDelays.count else {
                return result
            }

            let delay: Duration
            if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
               let seconds = Int(retryAfter), seconds >= 0
            {
                delay = .seconds(seconds)
            } else {
                delay = .seconds(fallbackDelays[attempt])
            }
            try await sleep(delay)
            attempt += 1
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AppleAdsPlatformError.decoding(String(describing: error))
        }
    }

    private static func apiError(statusCode: Int, data: Data) -> AppleAdsPlatformError {
        if let response = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            let detail = response.error.details?.map(\.message).joined(separator: " ")
            let message = [response.error.message, detail]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return .httpStatus(statusCode, message)
        }
        return .httpStatus(statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    private static func oauthError(statusCode: Int, data: Data) -> AppleAdsPlatformError {
        if let response = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            if response.error == "invalid_client" {
                return .invalidOAuthClient
            }
            return .httpStatus(
                statusCode,
                response.errorDescription ?? response.error
            )
        }
        return .httpStatus(statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    private static func genreCode(for genre: String) -> String {
        genre.uppercased()
            .replacingOccurrences(of: "&", with: "AND")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private static func previousCompleteWeek(containing date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfToday = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfToday)
        let daysBackToCompletedSaturday = weekday == 7 ? 7 : weekday
        let end = calendar.date(
            byAdding: .day,
            value: -daysBackToCompletedSaturday,
            to: startOfToday
        )!
        let start = calendar.date(byAdding: .day, value: -6, to: end)!
        return (start, end)
    }

    private static func week(
        before period: (start: Date, end: Date)
    ) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return (
            calendar.date(byAdding: .day, value: -7, to: period.start)!,
            calendar.date(byAdding: .day, value: -7, to: period.end)!
        )
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func stableUniqueTerms(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ).lowercased()
            guard !trimmed.isEmpty, seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private func nextOffset(
        pagination: PaginationResponse?,
        resultCount: Int
    ) -> Int? {
        guard let pagination, resultCount > 0 else { return nil }
        if let totalCount = pagination.totalCount {
            let next = pagination.offset + max(pagination.pageSize, resultCount)
            return next < totalCount ? next : nil
        }
        guard pagination.pageSize > 0,
              resultCount >= pagination.pageSize
        else {
            return nil
        }
        return pagination.offset + pagination.pageSize
    }
}

public enum AppleAdsPlatformError: LocalizedError, Equatable, Sendable {
    case incompleteCredentials
    case invalidPrivateKey
    case invalidClientSecretLifetime
    case invalidOAuthClient
    case missingAdAccount
    case selectedAdAccountUnavailable
    case appSearchQueryTooShort
    case invalidResponse
    case decoding(String)
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .incompleteCredentials:
            "Apple Ads Client ID, Team ID, and Key ID are required."
        case .invalidPrivateKey:
            "The saved Apple Ads private key is invalid. Generate a new API key pair."
        case .invalidClientSecretLifetime:
            "The Apple Ads client secret lifetime must be between 1 second and 180 days."
        case .invalidOAuthClient:
            "Apple rejected the OAuth client. Confirm that Client ID, Team ID, and Key ID come from the same Apple Ads API key, and that Apple Ads still has the public key shown on this Mac."
        case .missingAdAccount:
            "Select an Apple Ads ad account before requesting research data."
        case .selectedAdAccountUnavailable:
            "The selected Apple Ads account is no longer available to this API user."
        case .appSearchQueryTooShort:
            "Enter at least three characters to search your Apple Ads apps."
        case .invalidResponse:
            "Apple Ads returned an invalid response."
        case let .decoding(message):
            "Apple Ads returned an unexpected response: \(message)"
        case let .httpStatus(statusCode, message):
            message.isEmpty
                ? "Apple Ads returned HTTP \(statusCode)."
                : "Apple Ads returned HTTP \(statusCode): \(message)"
        }
    }
}

private struct ClientSecretClaims: Encodable {
    let issuer: String
    let issuedAt: Int
    let expiresAt: Int
    let audience: String
    let subject: String

    enum CodingKeys: String, CodingKey {
        case issuer = "iss"
        case issuedAt = "iat"
        case expiresAt = "exp"
        case audience = "aud"
        case subject = "sub"
    }
}

private struct CachedAccessToken: Sendable {
    let value: String
    let expiresAt: Date
    let credentialFingerprint: String
}

private struct InFlightAccessToken: Sendable {
    let credentialFingerprint: String
    let task: Task<CachedAccessToken, Error>
}

private struct AccessTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private struct PaginationRequest: Encodable {
    let offset: Int
    let pageSize: Int
}

private struct PaginationResponse: Decodable {
    let offset: Int
    let pageSize: Int
    let totalCount: Int?
}

private struct KeywordSuggestionFilter: Encodable {
    let field: String
    let operatorName: String
    let value: [String]

    enum CodingKeys: String, CodingKey {
        case field
        case operatorName = "operator"
        case value
    }
}

private struct KeywordSuggestionQuery: Encodable {
    let filters: [KeywordSuggestionFilter]
    let pagination: PaginationRequest
}

private struct KeywordSuggestionResponse: Decodable {
    let result: [AppleAdsKeywordSuggestion]
    let pagination: PaginationResponse?
}

private struct OwnedAppSearchResponse: Decodable {
    let apps: [AppleAdsPromotableApp]
    let pagination: OwnedAppSearchPagination?

    var nextOffset: Int? {
        guard let pagination,
              pagination.itemsPerPage > 0
        else {
            return nil
        }
        let next = pagination.startIndex + pagination.itemsPerPage
        return next < pagination.totalResults ? next : nil
    }

    private enum CodingKeys: String, CodingKey {
        case data
        case pagination
    }

    init(from decoder: Decoder) throws {
        if let directApps = try? decoder.singleValueContainer().decode(
            [AppleAdsPromotableApp].self
        ) {
            apps = directApps
            pagination = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decode([AppleAdsPromotableApp].self, forKey: .data)
        pagination = try container.decodeIfPresent(
            OwnedAppSearchPagination.self,
            forKey: .pagination
        )
    }
}

private struct OwnedAppSearchPagination: Decodable {
    let totalResults: Int
    let startIndex: Int
    let itemsPerPage: Int
}

private struct SearchTermPopularityFilter: Encodable {
    let field: String
    let operatorName: String
    let value: SearchTermPopularityFilterValue

    enum CodingKeys: String, CodingKey {
        case field
        case operatorName = "operator"
        case value
    }
}

private enum SearchTermPopularityFilterValue: Encodable {
    case scalar(String)
    case list([String])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .scalar(value):
            try container.encode(value)
        case let .list(values):
            try container.encode(values)
        }
    }
}

private struct TimeRangeRequest: Encodable {
    let start: String
    let end: String
    let granularity: String
}

private struct SortingRequest: Encodable {
    let field: String
    let sortOrder: String
}

private struct SearchTermPopularityQuery: Encodable {
    let fields: [String]
    let filters: [SearchTermPopularityFilter]
    let timeRange: TimeRangeRequest
    let sorting: [SortingRequest]
    let pagination: PaginationRequest
}

private struct SearchTermPopularityResponse: Decodable {
    let result: SearchTermPopularityResult
    let pagination: PaginationResponse?
}

private struct SearchTermPopularityResult: Decodable {
    let rows: [SearchTermPopularityRow]
}

private struct SearchTermPopularityRow: Decodable {
    let week: String?
    let month: String?
    let countryOrRegion: String
    let genre: String
    let searchTerm: String
    let rankInGenre: Int
    let searchPopularityInGenre: Int
    let searchPopularity1to100: Int
    let searchPopularity1to5: Int
}

private struct ACLResponse: Decodable {
    let result: ACLResult
}

private struct ACLResult: Decodable {
    let acls: [ACL]
}

private struct ACL: Decodable {
    let adAccount: ACLAdAccount
    let roles: [String]
}

private struct ACLAdAccount: Decodable {
    let id: Int64
    let name: String
    let organizationID: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case organizationID = "orgId"
    }
}

private struct APIErrorResponse: Decodable {
    let error: APIErrorPayload
}

private struct APIErrorPayload: Decodable {
    let message: String?
    let details: [APIErrorDetail]?
}

private struct APIErrorDetail: Decodable {
    let message: String
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
