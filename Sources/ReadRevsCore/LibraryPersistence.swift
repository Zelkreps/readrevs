import Foundation

public enum LibraryPersistenceError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchema(found: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(found, supported):
            "This library uses schema version \(found), but this app supports version \(supported). The original file was not changed."
        }
    }
}

public struct LibraryPersistence: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> ASOLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ASOLibrary()
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let library = try decoder.decode(ASOLibrary.self, from: data)
        guard library.schemaVersion == ASOLibrary.currentSchemaVersion else {
            throw LibraryPersistenceError.unsupportedSchema(
                found: library.schemaVersion,
                supported: ASOLibrary.currentSchemaVersion
            )
        }
        return library
    }

    public func save(_ library: ASOLibrary) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: fileURL, options: .atomic)
    }

    public static func defaultFileURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appending(path: "ReadRevs", directoryHint: .isDirectory)
            .appending(path: "library.json")
    }
}
