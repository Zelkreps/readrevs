import Foundation

public enum RankingIndex {
    public static func observations(
        projectID: UUID,
        keyword: String,
        store: String,
        results: [StoreAppSearchResult],
        checkedAt: Date = Date()
    ) -> [RankingObservation] {
        results.map { result in
            RankingObservation(
                projectID: projectID,
                keyword: keyword,
                store: store.lowercased(),
                adamID: result.adamID,
                appName: result.name,
                developerName: result.developerName,
                bundleID: result.bundleID,
                primaryGenre: result.primaryGenre,
                appStoreURL: result.appStoreURL,
                artworkURL: result.artworkURL,
                userRatingCount: result.userRatingCount,
                position: result.position,
                checkedAt: checkedAt
            )
        }
    }

    public static func merge(
        existing: [RankingObservation],
        incoming: [RankingObservation]
    ) -> [RankingObservation] {
        var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for observation in incoming {
            if let current = merged[observation.id], current.checkedAt > observation.checkedAt {
                continue
            }
            merged[observation.id] = observation
        }
        return merged.values.sorted(by: observationOrder)
    }

    public static func replacing(
        existing: [RankingObservation],
        with incoming: [RankingObservation],
        for scan: RankingScan
    ) -> [RankingObservation] {
        let retained = existing.filter { !matches($0, scan: scan) }
        let replacements = incoming.filter { matches($0, scan: scan) }
        return merge(existing: retained, incoming: replacements)
    }

    public static func mergeScans(existing: [RankingScan], incoming: [RankingScan]) -> [RankingScan] {
        var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for scan in incoming {
            if let current = merged[scan.id], current.checkedAt > scan.checkedAt {
                continue
            }
            merged[scan.id] = scan
        }
        return merged.values.sorted { $0.checkedAt > $1.checkedAt }
    }

    public static func summaries(from observations: [RankingObservation]) -> [AppRankingSummary] {
        Dictionary(grouping: observations) {
            AppStoreKey(adamID: $0.adamID, store: $0.store.lowercased())
        }.compactMap { key, items in
            guard let representative = items.sorted(by: observationOrder).first else { return nil }
            let keywords = Array(Set(items.map(\.keyword))).sorted()
            let positions = items.map(\.position)
            return AppRankingSummary(
                adamID: key.adamID,
                store: key.store,
                name: representative.appName,
                developerName: representative.developerName,
                bundleID: representative.bundleID,
                primaryGenre: representative.primaryGenre,
                appStoreURL: representative.appStoreURL,
                artworkURL: representative.artworkURL,
                keywordCount: keywords.count,
                bestPosition: positions.min() ?? 0,
                averagePosition: positions.isEmpty ? 0 : Double(positions.reduce(0, +)) / Double(positions.count),
                keywords: keywords
            )
        }.sorted {
            if $0.keywordCount != $1.keywordCount { return $0.keywordCount > $1.keywordCount }
            if $0.bestPosition != $1.bestPosition { return $0.bestPosition < $1.bestPosition }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public static func keywords(for adamID: Int64, in observations: [RankingObservation]) -> [RankingObservation] {
        var latestByKeywordAndStore: [String: RankingObservation] = [:]
        for observation in observations where observation.adamID == adamID {
            let key = "\(observation.keyword.lowercased())|\(observation.store.lowercased())"
            if let current = latestByKeywordAndStore[key], current.checkedAt > observation.checkedAt {
                continue
            }
            latestByKeywordAndStore[key] = observation
        }
        return latestByKeywordAndStore.values.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.keyword.localizedCaseInsensitiveCompare($1.keyword) == .orderedAscending
        }
    }

    public static func searchMetrics(
        keyword: String,
        store: String,
        focusAppAdamID: Int64?,
        observations: [RankingObservation]
    ) -> KeywordSearchMetrics {
        let matching = observations.filter {
            $0.store.caseInsensitiveCompare(store) == .orderedSame
                && normalized($0.keyword) == normalized(keyword)
        }.sorted { $0.position < $1.position }

        return KeywordSearchMetrics(
            difficulty: difficultyProxy(from: matching),
            focusAppPosition: focusAppAdamID.flatMap { adamID in
                matching.first(where: { $0.adamID == adamID })?.position
            },
            topApps: matching
        )
    }

    private static func observationOrder(_ lhs: RankingObservation, _ rhs: RankingObservation) -> Bool {
        if lhs.keyword != rhs.keyword { return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending }
        if lhs.store != rhs.store { return lhs.store < rhs.store }
        return lhs.position < rhs.position
    }

    private static func matches(_ observation: RankingObservation, scan: RankingScan) -> Bool {
        observation.projectID == scan.projectID
            && observation.store.caseInsensitiveCompare(scan.store) == .orderedSame
            && normalized(observation.keyword) == normalized(scan.keyword)
    }

    private static func difficultyProxy(from observations: [RankingObservation]) -> Int? {
        let topResults = observations.prefix(10)
        let weightedRatings = topResults.enumerated().compactMap { offset, observation -> (Double, Double)? in
            guard let ratingCount = observation.userRatingCount else { return nil }
            let weight = 1 / Double(offset + 1)
            return (Foundation.log10(Double(max(ratingCount, 0)) + 1), weight)
        }
        guard !weightedRatings.isEmpty else { return nil }
        let totalWeight = weightedRatings.reduce(0) { $0 + $1.1 }
        let weightedLogRating = weightedRatings.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
        return min(100, max(0, Int((weightedLogRating / 6 * 100).rounded())))
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

private struct AppStoreKey: Hashable {
    let adamID: Int64
    let store: String
}
