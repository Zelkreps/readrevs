import Foundation
import Testing
@testable import ReadRevs

@Suite("Apple endpoint construction")
struct AppleEndpointBuilderTests {
    @Test("Builds the legacy per-storefront customer review URL")
    func buildsReviewURL() throws {
        let url = try AppleEndpointBuilder.reviewFeedURL(
            appID: 284_910_350,
            storefront: .unitedStates,
            page: 3
        )

        #expect(
            url.absoluteString ==
                "https://itunes.apple.com/us/rss/customerreviews/page=3/id=284910350/sortby=mostrecent/json"
        )
    }

    @Test("Rejects pages beyond Apple's observed limit")
    func rejectsInvalidReviewPage() {
        #expect(throws: AppleEndpointBuilder.Error.invalidPage) {
            try AppleEndpointBuilder.reviewFeedURL(
                appID: 284_910_350,
                storefront: .unitedStates,
                page: 11
            )
        }
    }

    @Test("Builds a country-scoped Lookup URL")
    func buildsLookupURL() throws {
        let url = try AppleEndpointBuilder.lookupURL(
            appID: 284_910_350,
            storefront: .czechia
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        #expect(components.scheme == "https")
        #expect(components.host == "itunes.apple.com")
        #expect(components.path == "/lookup")
        #expect(items["id"] == "284910350")
        #expect(items["country"] == "cz")
    }

    @Test("Builds a country-scoped software autocomplete URL")
    func buildsSoftwareSearchURL() throws {
        let url = try AppleEndpointBuilder.softwareSearchURL(
            term: "meal planner",
            storefront: .czechia,
            limit: 25
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        #expect(components.scheme == "https")
        #expect(components.host == "itunes.apple.com")
        #expect(components.path == "/search")
        #expect(items["term"] == "meal planner")
        #expect(items["country"] == "cz")
        #expect(items["media"] == "software")
        #expect(items["entity"] == "software")
        #expect(items["limit"] == "25")
    }

    @Test("Rejects an empty autocomplete term")
    func rejectsEmptySoftwareSearchTerm() {
        #expect(throws: AppleEndpointBuilder.Error.invalidSearchTerm) {
            try AppleEndpointBuilder.softwareSearchURL(
                term: "  ",
                storefront: .unitedStates,
                limit: 10
            )
        }
    }

    @Test("Rejects autocomplete limits outside Apple's supported range")
    func rejectsInvalidSoftwareSearchLimit() {
        #expect(throws: AppleEndpointBuilder.Error.invalidLimit) {
            try AppleEndpointBuilder.softwareSearchURL(
                term: "Read reviews",
                storefront: .unitedStates,
                limit: 201
            )
        }
    }
}
