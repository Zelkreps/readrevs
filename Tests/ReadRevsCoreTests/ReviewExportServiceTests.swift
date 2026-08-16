import Foundation
import Testing
@testable import ReadRevsCore

@Suite("Review export")
struct ReviewExportServiceTests {
    private let app = TrackedApp(
        adamID: 42,
        name: "Example App",
        developerName: "Example Studio",
        bundleID: "com.example.app",
        primaryStore: "us",
        primaryGenre: "Utilities",
        appStoreURL: URL(string: "https://apps.apple.com/us/app/example/id42"),
        artworkURL: URL(string: "https://example.com/artwork.png"),
        version: "2.0",
        releaseDate: Date(timeIntervalSince1970: 1_600_000_000.125),
        currentVersionReleaseDate: Date(timeIntervalSince1970: 1_700_000_000.25),
        averageRating: 4.25,
        ratingCount: 12_345,
        kind: .owned,
        addedAt: Date(timeIntervalSince1970: 1_500_000_000.375)
    )

    private let reviews = [
        AppReview(
            id: "us-1",
            sourceID: "1",
            appID: 42,
            storefront: "us",
            rating: 1,
            title: "=SUM(1,1)",
            body: "Crashes after launch, every time.\nPlease fix it.",
            reviewerName: "A \"quoted\" reviewer",
            version: "2.0",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100.5)
        ),
        AppReview(
            id: "cz-2",
            sourceID: "2",
            appID: 42,
            storefront: "cz",
            rating: 5,
            title: "Skvela aplikace",
            body: "Funguje bez problemu.",
            reviewerName: "Eva",
            version: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200.75)
        ),
    ]

    @Test("JSON export round-trips all app, coverage, failure, and review data")
    func exportsLosslessJSON() throws {
        let exportedAt = Date(timeIntervalSince1970: 1_800_000_000.875)
        let completedStorefronts = ["us", "cz"]
        let failures = [ReviewSyncFailure(storefront: "de", message: "Timed out / retry later")]

        let data = try ReviewExportService.data(
            format: .json,
            app: app,
            reviews: reviews,
            completedStorefronts: completedStorefronts,
            failures: failures,
            exportedAt: exportedAt
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let payload = try decoder.decode(ReviewExportPayload.self, from: data)

        #expect(payload.schemaVersion == 1)
        #expect(payload.exportedAt == exportedAt)
        #expect(payload.app == app)
        #expect(payload.reviewCount == reviews.count)
        #expect(payload.completedStorefronts == completedStorefronts)
        #expect(payload.failures == failures)
        #expect(payload.reviews == reviews)
        #expect(payload.reviews[0].title == "=SUM(1,1)")
    }

    @Test("CSV export escapes user text and neutralizes spreadsheet formulas")
    func exportsSafeCSV() throws {
        let data = try ReviewExportService.data(
            format: .csv,
            app: app,
            reviews: reviews,
            completedStorefronts: ["us", "cz"],
            failures: [],
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let csv = try #require(String(data: data, encoding: .utf8))

        #expect(csv.hasPrefix("review_id,app_id,storefront,storefront_name,rating,title,body,reviewer,version,updated_at\n"))
        #expect(csv.contains("\"'=SUM(1,1)\""))
        #expect(csv.contains("\"Crashes after launch, every time.\nPlease fix it.\""))
        #expect(csv.contains("\"A \"\"quoted\"\" reviewer\""))
        #expect(csv.hasSuffix("\n"))
    }

    @Test("CSV export neutralizes formula prefixes hidden behind whitespace or controls")
    func neutralizesWhitespacePrefixedFormulas() throws {
        let dangerousReviews = [
            review(id: "1", title: "  =SUM(1,1)", body: "\t@IMPORT", reviewer: "\r+COMMAND"),
            review(id: "2", title: "-2+3", body: "+cmd", reviewer: "@lookup"),
        ]

        let data = try ReviewExportService.data(
            format: .csv,
            app: app,
            reviews: dangerousReviews,
            completedStorefronts: ["us"],
            failures: []
        )
        let csv = try #require(String(data: data, encoding: .utf8))

        #expect(csv.contains("\"'  =SUM(1,1)\""))
        #expect(csv.contains("'\t@IMPORT"))
        #expect(csv.contains("\"'\r+COMMAND\""))
        #expect(csv.contains("'-2+3"))
        #expect(csv.contains("'+cmd"))
        #expect(csv.contains("'@lookup"))
    }

    @Test("Empty CSV export still contains a complete header")
    func exportsEmptyCSV() throws {
        let data = try ReviewExportService.data(
            format: .csv,
            app: app,
            reviews: [],
            completedStorefronts: [],
            failures: []
        )

        #expect(
            String(data: data, encoding: .utf8)
                == "review_id,app_id,storefront,storefront_name,rating,title,body,reviewer,version,updated_at\n"
        )
    }

    private func review(
        id: String,
        title: String,
        body: String,
        reviewer: String
    ) -> AppReview {
        AppReview(
            id: "us-\(id)",
            sourceID: id,
            appID: app.adamID,
            storefront: "us",
            rating: 1,
            title: title,
            body: body,
            reviewerName: reviewer,
            version: "2.0",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
