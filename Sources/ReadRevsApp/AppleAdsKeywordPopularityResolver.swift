import ReadRevsCore
import Foundation

struct AppleAdsPopularityResolution: Sendable {
    let records: [KeywordRecord]
    let unmatchedKeywords: [String]
    let reportRequestCount: Int
    let reportSuccessCount: Int
    let reportMatchCount: Int
    let reportFailures: [String]
}

struct AppleAdsKeywordPopularityResolver: Sendable {
    let client: any AppleAdsPlatformProviding

    func resolve(
        keywords: [String],
        target: StoreTarget,
        genres: [String],
        credentials: AppleAdsCredentials,
        checkedAt: Date
    ) async throws -> AppleAdsPopularityResolution {
        let requested = stableUniqueKeywords(keywords)
        var remainingKeys = Set(requested.map(normalizedKeyword))
        let requestedByKey = Dictionary(
            uniqueKeysWithValues: requested.map { (normalizedKeyword($0), $0) }
        )
        var records: [KeywordRecord] = []
        var reportRequestCount = 0
        var reportSuccessCount = 0
        var reportMatchCount = 0
        var reportFailures: [String] = []

        for genre in stableUniqueKeywords(genres) where !remainingKeys.isEmpty {
            reportRequestCount += 1
            let rows: [AppleAdsSearchTermPopularity]
            do {
                rows = try await client.fetchSearchTermPopularity(
                    target: target,
                    genre: genre,
                    terms: requested.filter {
                        remainingKeys.contains(normalizedKeyword($0))
                    },
                    credentials: credentials
                )
                reportSuccessCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                reportFailures.append(error.localizedDescription)
                continue
            }

            for row in rows {
                let key = normalizedKeyword(row.searchTerm)
                guard remainingKeys.remove(key) != nil,
                      let requestedKeyword = requestedByKey[key]
                else {
                    continue
                }
                records.append(
                    KeywordRecord(
                        keyword: requestedKeyword,
                        language: target.language,
                        store: target.store,
                        country: row.countryOrRegion,
                        genre: genre,
                        popularity: row.popularity,
                        intentTags: ["apple-ads-popularity"],
                        matchedTerms: [requestedKeyword],
                        month: row.period,
                        sourceID: String(row.rankInGenre),
                        source: .appleAds,
                        isTracked: false,
                        updatedAt: checkedAt,
                        popularityCheckedAt: checkedAt
                    )
                )
                reportMatchCount += 1
            }
        }

        return AppleAdsPopularityResolution(
            records: records,
            unmatchedKeywords: requested.filter {
                remainingKeys.contains(normalizedKeyword($0))
            },
            reportRequestCount: reportRequestCount,
            reportSuccessCount: reportSuccessCount,
            reportMatchCount: reportMatchCount,
            reportFailures: reportFailures
        )
    }

    private func stableUniqueKeywords(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedKeyword(trimmed)
            guard !trimmed.isEmpty, seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private func normalizedKeyword(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
