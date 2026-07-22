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
}
