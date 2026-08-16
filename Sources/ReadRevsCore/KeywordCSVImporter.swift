import Foundation

public enum KeywordCSVImportError: Error, LocalizedError, Sendable {
    case invalidEncoding
    case missingHeader
    case missingKeywordColumn
    case unterminatedQuotedField

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding: "The CSV file is not valid UTF-8."
        case .missingHeader: "The CSV file has no header row."
        case .missingKeywordColumn: "The CSV file has no keyword column."
        case .unterminatedQuotedField: "The CSV file contains an unterminated quoted field."
        }
    }
}

public struct KeywordCSVImporter: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> [KeywordRecord] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw KeywordCSVImportError.invalidEncoding
        }

        let rows = try parseRows(text)
        guard let rawHeader = rows.first else {
            throw KeywordCSVImportError.missingHeader
        }

        let header = rawHeader.enumerated().reduce(into: [String: Int]()) { result, item in
            let normalized = item.element
                .replacingOccurrences(of: "\u{feff}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            result[normalized] = item.offset
        }
        guard header["keyword"] != nil else {
            throw KeywordCSVImportError.missingKeywordColumn
        }

        return rows.dropFirst().compactMap { row in
            let value: (String) -> String = { key in
                guard let index = header[key], row.indices.contains(index) else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let keyword = value("keyword")
            guard !keyword.isEmpty else { return nil }

            return KeywordRecord(
                keyword: keyword,
                language: value("language"),
                store: value("store"),
                country: optional(value("country")),
                genre: value("genre").isEmpty ? "All" : value("genre"),
                popularity: Int(value("popularity")) ?? 0,
                relevanceScore: Double(value("relevance_score")) ?? 0,
                opportunityScore: Double(value("opportunity_score")) ?? 0,
                intentTags: splitList(value("intent_tags")),
                matchedTerms: splitList(value("matched_terms")),
                month: optional(value("month")),
                sourceID: optional(value("source_id")),
                source: .csvImport,
                isTracked: true,
                updatedAt: Date()
            )
        }
    }

    private func parseRows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)
            let isLineBreak = character == "\n" || character == "\r" || character == "\r\n"

            if character == "\"" {
                if isQuoted, nextIndex < text.endIndex, text[nextIndex] == "\"" {
                    field.append("\"")
                    index = text.index(after: nextIndex)
                    continue
                }
                isQuoted.toggle()
            } else if character == ",", !isQuoted {
                row.append(field)
                field = ""
            } else if isLineBreak, !isQuoted {
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) {
                    rows.append(row)
                }
                row = []
                field = ""
            } else if isLineBreak {
                field.append("\n")
            } else {
                field.append(character)
            }

            index = nextIndex
        }

        guard !isQuoted else {
            throw KeywordCSVImportError.unterminatedQuotedField
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

private func optional(_ value: String) -> String? {
    value.isEmpty ? nil : value
}

private func splitList(_ value: String) -> [String] {
    value.split(separator: ";").map {
        String($0).trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
}
