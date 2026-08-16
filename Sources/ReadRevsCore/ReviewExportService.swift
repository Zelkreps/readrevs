import Foundation

public enum ReviewExportFormat: String, CaseIterable, Hashable, Sendable {
    case json
    case csv

    public var filenameExtension: String { rawValue }
}

public struct ReviewExportPayload: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let exportedAt: Date
    public let app: TrackedApp
    public let reviewCount: Int
    public let completedStorefronts: [String]
    public let failures: [ReviewSyncFailure]
    public let reviews: [AppReview]
}

public enum ReviewExportService {
    public static func data(
        format: ReviewExportFormat,
        app: TrackedApp,
        reviews: [AppReview],
        completedStorefronts: [String],
        failures: [ReviewSyncFailure],
        exportedAt: Date = .now
    ) throws -> Data {
        switch format {
        case .json:
            try jsonData(
                app: app,
                reviews: reviews,
                completedStorefronts: completedStorefronts,
                failures: failures,
                exportedAt: exportedAt
            )
        case .csv:
            Data(csv(reviews: reviews).utf8)
        }
    }

    private static func jsonData(
        app: TrackedApp,
        reviews: [AppReview],
        completedStorefronts: [String],
        failures: [ReviewSyncFailure],
        exportedAt: Date
    ) throws -> Data {
        let payload = ReviewExportPayload(
            schemaVersion: 1,
            exportedAt: exportedAt,
            app: app,
            reviewCount: reviews.count,
            completedStorefronts: completedStorefronts,
            failures: failures,
            reviews: reviews
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private static func csv(reviews: [AppReview]) -> String {
        let header = [
            "review_id",
            "app_id",
            "storefront",
            "storefront_name",
            "rating",
            "title",
            "body",
            "reviewer",
            "version",
            "updated_at",
        ].joined(separator: ",")

        let rows = reviews.map { review in
            [
                review.sourceID,
                String(review.appID),
                review.storefront,
                storefrontDisplayName(review.storefront),
                String(review.rating),
                review.title,
                review.body,
                review.reviewerName,
                review.version ?? "",
                review.updatedAt.formatted(.iso8601),
            ]
            .map(csvCell)
            .joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func storefrontDisplayName(_ storefront: String) -> String {
        let regionCode = storefront.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return Locale(identifier: "en_US_POSIX").localizedString(forRegionCode: regionCode) ?? regionCode
    }

    private static func csvCell(_ value: String) -> String {
        let formulaPrefixes: Set<Character> = ["=", "+", "-", "@"]
        let controlPrefixes: Set<Character> = ["\t", "\r", "\n"]
        let firstNonWhitespace = value.first { !$0.isWhitespace }
        let startsWithControl = value.first.map(controlPrefixes.contains) ?? false
        let safeValue: String

        if startsWithControl || firstNonWhitespace.map(formulaPrefixes.contains) == true {
            safeValue = "'" + value
        } else {
            safeValue = value
        }

        guard safeValue.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return safeValue
        }
        return "\"" + safeValue.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
