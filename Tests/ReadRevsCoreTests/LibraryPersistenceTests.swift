import Foundation
import Testing
@testable import ReadRevsCore

@Test
func libraryPersistenceRoundTripsProjectsAndApps() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "aso-library-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let target = StoreTarget(language: "cs", store: "cz")
    let project = ResearchProject(
        name: "World Flags",
        topic: "Flags, capitals and geography quizzes",
        targets: [target],
        genres: ["Education", "Games"],
        seedKeywords: ["vlajky", "zeměpis"]
    )
    let app = TrackedApp(
        adamID: 123_456,
        name: "Example App",
        developerName: "Example Developer",
        bundleID: "com.example.sample",
        primaryStore: "cz",
        kind: .owned
    )
    let expected = ASOLibrary(projects: [project], apps: [app])
    let persistence = LibraryPersistence(fileURL: directory.appending(path: "library.json"))

    try persistence.save(expected)

    #expect(try persistence.load() == expected)
}

@Test
func missingLibraryFileLoadsAnEmptyLibrary() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "missing-\(UUID().uuidString).json")

    #expect(try LibraryPersistence(fileURL: fileURL).load() == ASOLibrary())
}

@Test
func unsupportedLibrarySchemaIsRejectedWithoutChangingTheFile() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "future-library-\(UUID().uuidString).json")
    let original = Data(#"{"schemaVersion":999,"projects":[],"apps":[]}"#.utf8)
    try original.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    do {
        _ = try LibraryPersistence(fileURL: fileURL).load()
        Issue.record("Expected an unsupported schema error")
    } catch let error as LibraryPersistenceError {
        #expect(error == .unsupportedSchema(found: 999, supported: ASOLibrary.currentSchemaVersion))
    }

    #expect(try Data(contentsOf: fileURL) == original)
}

@Test
func schemaOneProjectWithoutRankingFieldsStillDecodes() throws {
    let projectID = UUID(uuidString: "F3BEEBA4-FF3E-4B3D-AFD2-1B20A08B9718")!
    let payload = """
    {
      "schemaVersion": 1,
      "projects": [
        {
          "id": "\(projectID.uuidString)",
          "name": "Legacy Research",
          "topic": "Geography",
          "targets": [{"language": "en", "store": "us"}],
          "genres": ["Education"],
          "seedKeywords": ["flags"],
          "keywords": [],
          "createdAt": 0,
          "updatedAt": 0
        }
      ],
      "apps": []
    }
    """

    let library = try JSONDecoder().decode(ASOLibrary.self, from: Data(payload.utf8))

    #expect(library.projects.first?.id == projectID)
    #expect(library.projects.first?.rankingObservations == [])
    #expect(library.projects.first?.rankingScans == [])
}

@Test
func schemaOneTrackedAppWithoutReviewMetadataStillDecodes() throws {
    let payload = """
    {
      "schemaVersion": 1,
      "projects": [],
      "apps": [
        {
          "adamID": 42,
          "name": "Legacy App",
          "developerName": "Studio",
          "bundleID": "com.example.legacy",
          "primaryStore": "us",
          "primaryGenre": "Education",
          "appStoreURL": null,
          "artworkURL": null,
          "kind": "owned",
          "addedAt": 0
        }
      ]
    }
    """

    let library = try JSONDecoder().decode(ASOLibrary.self, from: Data(payload.utf8))

    #expect(library.apps.first?.adamID == 42)
    #expect(library.apps.first?.averageRating == nil)
    #expect(library.apps.first?.ratingCount == nil)
    #expect(library.apps.first?.version == nil)
}

@Test
func legacyReadRevsSavedAppsMergeWithoutReplacingCurrentMetadata() throws {
    let existing = TrackedApp(
        adamID: 42,
        name: "Current Name",
        developerName: "Current Developer",
        bundleID: "com.example.current",
        primaryStore: "gb",
        kind: .owned,
        addedAt: Date(timeIntervalSince1970: 100)
    )
    let legacyPayload = Data(
        #"""
        [
          {
            "appID": 42,
            "name": "Legacy Name",
            "sellerName": "Legacy Developer",
            "version": "1.0",
            "primaryGenre": "Education",
            "primaryStorefront": "us"
          },
          {
            "appID": 84,
            "name": "Imported App",
            "sellerName": "Imported Studio",
            "artworkURL": "https://example.com/icon.png",
            "version": "2.3",
            "primaryGenre": "Games",
            "averageRating": 4.7,
            "ratingCount": 1200,
            "appStoreURL": "https://apps.apple.com/app/id84",
            "primaryStorefront": "cz"
          }
        ]
        """#.utf8
    )
    let importedAt = Date(timeIntervalSince1970: 200)
    let current = ASOLibrary(apps: [existing])

    let merged = try LegacyReadRevsLibraryImporter.merge(
        savedAppsData: legacyPayload,
        into: current,
        importedAt: importedAt
    )
    let mergedAgain = try LegacyReadRevsLibraryImporter.merge(
        savedAppsData: legacyPayload,
        into: merged,
        importedAt: importedAt
    )

    #expect(merged.apps.count == 2)
    #expect(merged.apps.first(where: { $0.adamID == 42 }) == existing)
    #expect(merged.apps.first(where: { $0.adamID == 84 }) == TrackedApp(
        adamID: 84,
        name: "Imported App",
        developerName: "Imported Studio",
        bundleID: "",
        primaryStore: "cz",
        primaryGenre: "Games",
        appStoreURL: URL(string: "https://apps.apple.com/app/id84"),
        artworkURL: URL(string: "https://example.com/icon.png"),
        version: "2.3",
        averageRating: 4.7,
        ratingCount: 1200,
        kind: .owned,
        addedAt: importedAt
    ))
    #expect(mergedAgain == merged)
}
