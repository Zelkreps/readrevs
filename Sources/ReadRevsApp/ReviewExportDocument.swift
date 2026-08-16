import ReadRevsCore
import SwiftUI
import UniformTypeIdentifiers

struct ReviewExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension ReviewExportFormat {
    var contentType: UTType {
        switch self {
        case .json: .json
        case .csv: .commaSeparatedText
        }
    }

    var displayName: String {
        switch self {
        case .json: "JSON (raw data)"
        case .csv: "CSV (spreadsheet)"
        }
    }
}
