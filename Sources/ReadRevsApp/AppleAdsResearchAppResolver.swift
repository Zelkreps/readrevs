import ReadRevsCore
import Foundation

struct AppleAdsResearchAppResolver: Sendable {
    let client: any AppleAdsPlatformProviding
    let credentialStore: any AppleAdsCredentialStoring

    func resolve(
        credentials: AppleAdsCredentials,
        candidates: [TrackedApp],
        target: StoreTarget
    ) async throws -> AppleAdsCredentials {
        if credentials.hasResearchApp {
            return credentials
        }

        let queries = candidates
            .filter { $0.kind == .owned }
            .map(\.name)
        guard !queries.isEmpty else {
            throw AppleAdsResearchAppError.noLocalOwnedApps
        }

        guard let app = try await eligibleApps(
            credentials: credentials,
            queries: queries,
            target: target
        ).first else {
            throw AppleAdsResearchAppError.noAccessibleApps
        }
        return try persist(credentials: credentials, app: app)
    }

    func eligibleApps(
        credentials: AppleAdsCredentials,
        queries: [String],
        target: StoreTarget
    ) async throws -> [AppleAdsPromotableApp] {
        var seenQueries: Set<String> = []
        let normalizedQueries = queries.compactMap { value -> String? in
            let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = query.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ).lowercased()
            guard query.count >= 3, seenQueries.insert(key).inserted else { return nil }
            return query
        }

        var discovered: [AppleAdsPromotableApp] = []
        for query in normalizedQueries {
            do {
                discovered.append(
                    contentsOf: try await client.searchOwnedApps(
                        matching: query,
                        credentials: credentials
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            }
        }

        var seenApps: Set<Int64> = []
        let uniqueApps = discovered.filter { seenApps.insert($0.adamID).inserted }
        var eligible: [AppleAdsPromotableApp] = []
        for app in uniqueApps {
            do {
                _ = try await client.fetchKeywordSuggestions(
                    terms: ["app"],
                    promotedObjectID: app.adamID,
                    target: target,
                    credentials: credentials
                )
                eligible.append(app)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard isUnavailableApp(error) else { throw error }
            }
        }
        return eligible.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func select(
        credentials: AppleAdsCredentials,
        app: AppleAdsPromotableApp,
        target: StoreTarget
    ) async throws -> AppleAdsCredentials {
        _ = try await client.fetchKeywordSuggestions(
            terms: ["app"],
            promotedObjectID: app.adamID,
            target: target,
            credentials: credentials
        )
        return try persist(credentials: credentials, app: app)
    }

    private func persist(
        credentials: AppleAdsCredentials,
        app: AppleAdsPromotableApp
    ) throws -> AppleAdsCredentials {
        var resolved = credentials
        resolved.researchAppAdamID = app.adamID
        resolved.researchAppName = app.name
        try credentialStore.save(resolved)
        return resolved
    }

    private func isUnavailableApp(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains(
            "app not found or access denied"
        )
    }
}

enum AppleAdsResearchAppError: LocalizedError, Equatable {
    case noLocalOwnedApps
    case noAccessibleApps

    var errorDescription: String? {
        switch self {
        case .noLocalOwnedApps:
            "Search for an app owned by this Apple Ads account in Settings before requesting exact popularity."
        case .noAccessibleApps:
            "Apple Ads did not return an eligible app for the connected account."
        }
    }
}
