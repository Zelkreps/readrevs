import ReadRevsCore
import Foundation

enum ReadRevsMigration {
    static let readRevsBundleIdentifier = "com.zelkreps.ReadRevs"
    static let asoResearchBundleIdentifier = "com.zelkreps.asoresearch"
    static let savedAppsKey = "savedApps.v1"
    static let selectedAppIDKey = "selectedAppID.v1"

    private static let preferenceKeys = [
        CodexResearchPreferences.modelIDStorageKey,
        CodexReasoningEffort.storageKey,
        CodexResearchPromptPreferences.storageKey,
    ]

    static func readRevsDefaults() -> UserDefaults? {
        UserDefaults(suiteName: readRevsBundleIdentifier)
    }

    static func asoResearchDefaults() -> UserDefaults? {
        UserDefaults(suiteName: asoResearchBundleIdentifier)
    }

    static func copyPreferences(from legacy: UserDefaults, to current: UserDefaults) {
        for key in preferenceKeys where current.object(forKey: key) == nil {
            guard let value = legacy.object(forKey: key) else { continue }
            current.set(value, forKey: key)
        }
    }

    static func migrateHistory(
        from legacyRoot: URL,
        to currentRoot: URL
    ) throws {
        let legacyRepository = CodexResearchHistoryRepository(rootDirectory: legacyRoot)
        let legacyEntries = try legacyRepository.load()
        guard !legacyEntries.isEmpty else { return }
        try CodexResearchHistoryRepository(rootDirectory: currentRoot)
            .mergeImported(legacyEntries)
    }

    static func migrateHistory(fileManager: FileManager = .default) throws {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return
        }
        try migrateHistory(
            from: applicationSupport
                .appending(path: "ASO Research", directoryHint: .isDirectory)
                .appending(path: "ResearchHistory", directoryHint: .isDirectory),
            to: applicationSupport
                .appending(path: "ReadRevs", directoryHint: .isDirectory)
                .appending(path: "ResearchHistory", directoryHint: .isDirectory)
        )
    }
}
