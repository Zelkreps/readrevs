import Foundation
import Testing
@testable import ReadRevs

@Suite("Review export")
struct ReviewExportServiceTests {
    private let app = AppMetadata(
        appID: 42,
        name: "Example App",
        sellerName: "Example Studio",
        version: "2.0",
        primaryGenre: "Utilities",
        primaryStorefront: .unitedStates
    )

    private let reviews = [
        AppReview(
            id: "us-1",
            sourceID: "1",
            appID: 42,
            storefront: .unitedStates,
            rating: 1,
            title: "=SUM(1,1)",
            body: "Crashes after launch, every time.\nPlease fix it.",
            reviewerName: "A \"quoted\" reviewer",
            version: "2.0",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
    ]

    @Test("JSON export contains every synced review and coverage metadata")
    func exportsJSON() throws {
        let data = try ReviewExportService.data(
            format: .json,
            app: app,
            reviews: reviews,
            completedStorefronts: [.unitedStates, .czechia],
            failures: [],
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exportedReviews = try #require(object["reviews"] as? [[String: Any]])
        let coverage = try #require(object["completedStorefronts"] as? [String])

        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["reviewCount"] as? Int == 1)
        #expect(exportedReviews.first?["body"] as? String == reviews[0].body)
        #expect(Set(coverage) == Set(["us", "cz"]))
    }

    @Test("CSV export escapes user text and neutralizes spreadsheet formulas")
    func exportsSafeCSV() throws {
        let data = try ReviewExportService.data(
            format: .csv,
            app: app,
            reviews: reviews,
            completedStorefronts: [.unitedStates],
            failures: [],
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let csv = try #require(String(data: data, encoding: .utf8))

        #expect(csv.hasPrefix("review_id,app_id,storefront"))
        #expect(csv.contains("\"'=SUM(1,1)\""))
        #expect(csv.contains("\"Crashes after launch, every time.\nPlease fix it.\""))
        #expect(csv.contains("\"A \"\"quoted\"\" reviewer\""))
    }

    @Test("CSV export neutralizes formulas hidden behind whitespace")
    func neutralizesWhitespacePrefixedFormulas() throws {
        let dangerousReview = AppReview(
            id: "us-2",
            sourceID: "2",
            appID: 42,
            storefront: .unitedStates,
            rating: 1,
            title: "  =SUM(1,1)",
            body: "\t@IMPORT",
            reviewerName: "\r+COMMAND",
            version: "2.0",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try ReviewExportService.data(
            format: .csv,
            app: app,
            reviews: [dangerousReview],
            completedStorefronts: [.unitedStates],
            failures: []
        )
        let csv = try #require(String(data: data, encoding: .utf8))

        #expect(csv.contains("\"'  =SUM(1,1)\""))
        #expect(csv.contains("'\t@IMPORT"))
        #expect(csv.contains("\"'\r+COMMAND\""))
    }
}
