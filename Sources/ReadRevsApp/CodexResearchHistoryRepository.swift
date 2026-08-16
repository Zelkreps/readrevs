import Foundation

struct CodexResearchHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let appID: Int64
    let appName: String
    let reviewCount: Int
    let storefrontCount: Int
    let createdAt: Date
    let updatedAt: Date
    let codexModel: CodexModelConfiguration
    let reasoningEffort: CodexReasoningEffort
    let messages: [CodexChatMessage]
}

struct CodexResearchHistoryRepository {
    enum RepositoryError: Swift.Error, LocalizedError {
        case applicationSupportUnavailable

        var errorDescription: String? {
            switch self {
            case .applicationSupportUnavailable:
                "The Application Support folder is unavailable."
            }
        }
    }

    let rootDirectory: URL

    private var historyURL: URL {
        rootDirectory.appending(path: "history.json")
    }

    static func live(fileManager: FileManager = .default) throws -> Self {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw RepositoryError.applicationSupportUnavailable
        }

        return Self(
            rootDirectory: applicationSupport
                .appending(path: "ReadRevs", directoryHint: .isDirectory)
                .appending(path: "ResearchHistory", directoryHint: .isDirectory)
        )
    }

    func load(appID: Int64? = nil) throws -> [CodexResearchHistoryEntry] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        let data = try Data(contentsOf: historyURL)
        let entries = try JSONDecoder().decode([CodexResearchHistoryEntry].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
        guard let appID else { return entries }
        return entries.filter { $0.appID == appID }
    }

    func upsert(_ entry: CodexResearchHistoryEntry) throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        var entries = try load()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        entries.sort { $0.updatedAt > $1.updatedAt }

        try save(entries)
    }

    func mergeImported(_ importedEntries: [CodexResearchHistoryEntry]) throws {
        var entriesByID: [UUID: CodexResearchHistoryEntry] = [:]
        for entry in try load() {
            if let current = entriesByID[entry.id], current.updatedAt >= entry.updatedAt {
                continue
            }
            entriesByID[entry.id] = entry
        }
        for entry in importedEntries {
            if let current = entriesByID[entry.id], current.updatedAt >= entry.updatedAt {
                continue
            }
            entriesByID[entry.id] = entry
        }
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try save(entriesByID.values.sorted { $0.updatedAt > $1.updatedAt })
    }

    private func save(_ entries: [CodexResearchHistoryEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entries).write(to: historyURL, options: .atomic)
    }
}
