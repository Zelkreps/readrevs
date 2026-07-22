import Foundation
import Testing
@testable import ReadRevs

@Suite("Saved app library")
struct SavedAppsStoreTests {
    @Test("Persists apps and updates duplicates by App Store ID")
    @MainActor
    func persistsAndDeduplicates() throws {
        let suiteName = "ReadRevsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = sampleMetadata(name: "Original")
        let refreshed = sampleMetadata(name: "Refreshed")

        let store = SavedAppsStore(defaults: defaults)
        store.upsert(initial)
        store.upsert(refreshed)

        #expect(store.apps.count == 1)
        #expect(store.apps.first?.name == "Refreshed")
        #expect(store.selectedAppID == 42)

        let reloaded = SavedAppsStore(defaults: defaults)
        #expect(reloaded.apps == [refreshed])
        #expect(reloaded.selectedAppID == 42)
    }
}

private func sampleMetadata(name: String) -> AppMetadata {
    AppMetadata(
        appID: 42,
        name: name,
        sellerName: "Example Studio",
        artworkURL: nil,
        version: "1.0",
        primaryGenre: "Productivity",
        releaseDate: nil,
        currentVersionReleaseDate: nil,
        averageRating: 4.5,
        ratingCount: 10,
        appStoreURL: nil,
        primaryStorefront: .unitedStates
    )
}
