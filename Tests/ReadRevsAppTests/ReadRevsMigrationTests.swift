import ReadRevsCore
import Foundation
import Testing
@testable import ReadRevsApp

@Suite("ReadRevs migration")
struct LegacyReadRevsMigrationTests {
    @Test("Surfaces nonfatal migration warnings without making the current library read-only")
    @MainActor
    func surfacesMigrationWarnings() {
        let persistence = LibraryPersistence(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
                .appending(path: "library.json")
        )
        let warning = PresentedError(
            title: "Some Previous Data Could Not Be Imported",
            message: "Research history: Invalid data"
        )

        let store = LibraryStore(persistence: persistence, migrationWarning: warning)

        #expect(!store.isReadOnly)
        #expect(store.presentedError?.title == warning.title)
        #expect(store.presentedError?.message == warning.message)
    }

    @Test("Copies ASO Research preferences only when ReadRevs has no value")
    func copiesMissingPreferences() {
        let legacySuite = "LegacyReadRevsTests.legacy.\(UUID().uuidString)"
        let currentSuite = "LegacyReadRevsTests.current.\(UUID().uuidString)"
        let legacy = UserDefaults(suiteName: legacySuite)!
        let current = UserDefaults(suiteName: currentSuite)!
        defer {
            legacy.removePersistentDomain(forName: legacySuite)
            current.removePersistentDomain(forName: currentSuite)
        }
        legacy.set("legacy-model", forKey: CodexResearchPreferences.modelIDStorageKey)
        legacy.set("high", forKey: CodexReasoningEffort.storageKey)
        legacy.set("Legacy prompt", forKey: CodexResearchPromptPreferences.storageKey)
        current.set("current-model", forKey: CodexResearchPreferences.modelIDStorageKey)

        ReadRevsMigration.copyPreferences(from: legacy, to: current)

        #expect(current.string(forKey: CodexResearchPreferences.modelIDStorageKey) == "current-model")
        #expect(current.string(forKey: CodexReasoningEffort.storageKey) == "high")
        #expect(current.string(forKey: CodexResearchPromptPreferences.storageKey) == "Legacy prompt")
    }

    @Test("Merges legacy history and keeps the newest entry for the same ID")
    func mergesHistory() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "legacy-readrevs-history-\(UUID().uuidString)")
        let legacyRoot = root.appending(path: "ASO Research")
        let currentRoot = root.appending(path: "ReadRevs")
        defer { try? FileManager.default.removeItem(at: root) }

        let sharedID = UUID()
        let legacyRepository = CodexResearchHistoryRepository(rootDirectory: legacyRoot)
        let currentRepository = CodexResearchHistoryRepository(rootDirectory: currentRoot)
        try legacyRepository.upsert(entry(
            id: sharedID,
            appID: 42,
            updatedAt: Date(timeIntervalSince1970: 100),
            text: "Old"
        ))
        let current = entry(
            id: sharedID,
            appID: 42,
            updatedAt: Date(timeIntervalSince1970: 200),
            text: "Current"
        )
        try currentRepository.upsert(current)
        let legacyOnly = entry(
            id: UUID(),
            appID: 84,
            updatedAt: Date(timeIntervalSince1970: 150),
            text: "Imported"
        )
        try legacyRepository.upsert(legacyOnly)

        try ReadRevsMigration.migrateHistory(
            from: legacyRoot,
            to: currentRoot
        )
        try ReadRevsMigration.migrateHistory(
            from: legacyRoot,
            to: currentRoot
        )

        let merged = try currentRepository.load()
        #expect(merged.count == 2)
        #expect(merged.first(where: { $0.id == sharedID }) == current)
        #expect(merged.contains(legacyOnly))
    }

    @Test("Merges the ASO Research library without replacing ReadRevs records")
    @MainActor
    func importsASOResearchLibrary() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "readrevs-library-migration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = LibraryPersistence(fileURL: root.appending(path: "library.json"))
        let currentApp = trackedApp(id: 42, name: "Current")
        try persistence.save(ASOLibrary(apps: [currentApp]))

        let store = LibraryStore(
            persistence: persistence,
            importedLibrary: ASOLibrary(apps: [
                trackedApp(id: 42, name: "Legacy"),
                trackedApp(id: 84, name: "Imported"),
            ])
        )

        #expect(store.library.apps.map(\.adamID) == [42, 84])
        #expect(store.library.apps.first(where: { $0.adamID == 42 })?.name == "Current")
        #expect(try persistence.load() == store.library)
    }

    @Test("Library startup imports legacy saved apps and persists the merge")
    @MainActor
    func importsSavedAppsAtStartup() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "legacy-readrevs-library-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = LibraryPersistence(fileURL: root.appending(path: "library.json"))
        let payload = Data(
            #"""
            [{
              "appID": 84,
              "name": "Imported App",
              "sellerName": "Studio",
              "version": "1.0",
              "primaryGenre": "Education",
              "primaryStorefront": "us"
            }]
            """#.utf8
        )

        let store = LibraryStore(
            persistence: persistence,
            legacySavedAppsData: payload,
            legacySelectedAppID: 84,
            migrationDate: Date(timeIntervalSince1970: 300)
        )

        #expect(store.library.apps.map(\.adamID) == [84])
        #expect(store.selection == .app(84))
        #expect(try persistence.load() == store.library)
    }

    private func entry(
        id: UUID,
        appID: Int64,
        updatedAt: Date,
        text: String
    ) -> CodexResearchHistoryEntry {
        CodexResearchHistoryEntry(
            id: id,
            appID: appID,
            appName: "App \(appID)",
            reviewCount: 1,
            storefrontCount: 1,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            codexModel: CodexModelConfiguration(modelID: "test", displayName: "Test"),
            reasoningEffort: .medium,
            messages: [CodexChatMessage(role: .assistant, text: text)]
        )
    }

    private func trackedApp(id: Int64, name: String) -> TrackedApp {
        TrackedApp(
            adamID: id,
            name: name,
            developerName: "Example Studio",
            bundleID: "com.example.\(id)",
            primaryStore: "us",
            primaryGenre: "Education",
            kind: .owned
        )
    }
}
