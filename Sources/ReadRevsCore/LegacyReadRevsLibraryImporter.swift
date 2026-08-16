import Foundation

public enum LegacyReadRevsLibraryImporter {
    public static func merge(
        savedAppsData: Data,
        into library: ASOLibrary,
        importedAt: Date = Date()
    ) throws -> ASOLibrary {
        let legacyApps = try JSONDecoder().decode([LegacySavedApp].self, from: savedAppsData)
        var merged = library
        var seenIDs = Set(merged.apps.map(\.adamID))

        let importedApps = legacyApps
            .compactMap { $0.trackedApp(importedAt: importedAt) }
            .filter { seenIDs.insert($0.adamID).inserted }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        merged.apps.append(contentsOf: importedApps)
        return merged
    }
}

private struct LegacySavedApp: Decodable {
    let appID: Int64
    let name: String
    let sellerName: String
    let artworkURL: URL?
    let version: String
    let primaryGenre: String
    let releaseDate: Date?
    let currentVersionReleaseDate: Date?
    let averageRating: Double?
    let ratingCount: Int?
    let appStoreURL: URL?
    let primaryStorefront: String

    func trackedApp(importedAt: Date) -> TrackedApp? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appID > 0, !normalizedName.isEmpty else { return nil }
        let normalizedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return TrackedApp(
            adamID: appID,
            name: normalizedName,
            developerName: sellerName.trimmingCharacters(in: .whitespacesAndNewlines),
            bundleID: "",
            primaryStore: primaryStorefront,
            primaryGenre: primaryGenre.trimmingCharacters(in: .whitespacesAndNewlines),
            appStoreURL: appStoreURL,
            artworkURL: artworkURL,
            version: normalizedVersion.isEmpty ? nil : normalizedVersion,
            releaseDate: releaseDate,
            currentVersionReleaseDate: currentVersionReleaseDate,
            averageRating: averageRating,
            ratingCount: ratingCount,
            kind: .owned,
            addedAt: importedAt
        )
    }
}
