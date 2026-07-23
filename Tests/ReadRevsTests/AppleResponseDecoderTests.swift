import Foundation
import Testing
@testable import ReadRevs

@Suite("Apple response decoding")
struct AppleResponseDecoderTests {
    @Test("Decodes valid reviews and skips malformed entries")
    func decodesReviewFeed() throws {
        let data = try #require(reviewFeedJSON.data(using: .utf8))
        let reviews = try AppleResponseDecoder.reviews(
            from: data,
            appID: 284_910_350,
            storefront: .unitedStates
        )

        #expect(reviews.count == 1)
        let review = try #require(reviews.first)
        #expect(review.id == "us-14330676239")
        #expect(review.sourceID == "14330676239")
        #expect(review.rating == 5)
        #expect(review.title == "Taco Tuesday")
        #expect(review.body == "Friendly service.")
        #expect(review.reviewerName == "elenayscarletttita")
        #expect(review.version == "26.30.0")
        #expect(review.storefront == .unitedStates)
    }

    @Test("Treats a feed without entry as empty")
    func decodesEmptyReviewFeed() throws {
        let data = Data(#"{"feed":{"title":{"label":"Customer Reviews"}}}"#.utf8)
        let reviews = try AppleResponseDecoder.reviews(
            from: data,
            appID: 284_910_350,
            storefront: .czechia
        )

        #expect(reviews.isEmpty)
    }

    @Test("Decodes storefront-specific lookup metadata")
    func decodesLookup() throws {
        let data = try #require(lookupJSON.data(using: .utf8))
        let app = try AppleResponseDecoder.app(
            from: data,
            storefront: .unitedStates
        )

        #expect(app.appID == 284_910_350)
        #expect(app.name == "Yelp: Food & Reviews")
        #expect(app.sellerName == "Yelp, Inc.")
        #expect(app.version == "26.30.0")
        #expect(app.averageRating == 4.53)
        #expect(app.ratingCount == 2_002_740)
        #expect(app.primaryStorefront == .unitedStates)
    }

    @Test("Decodes all valid software autocomplete results")
    func decodesSoftwareSearchResults() throws {
        let data = try #require(searchJSON.data(using: .utf8))
        let apps = try AppleResponseDecoder.apps(
            from: data,
            storefront: .czechia
        )

        #expect(apps.map(\.appID) == [284_910_350, 1_234_567_890])
        #expect(apps.map(\.name) == ["Yelp: Food & Reviews", "Meal Planner"])
        #expect(apps.allSatisfy { $0.primaryStorefront == .czechia })
    }

    @Test("Treats an autocomplete response without matches as empty")
    func decodesEmptySoftwareSearchResults() throws {
        let apps = try AppleResponseDecoder.apps(
            from: Data(#"{"resultCount":0,"results":[]}"#.utf8),
            storefront: .unitedStates
        )

        #expect(apps.isEmpty)
    }

    @Test("Rejects a non-software identifier returned by generic lookup")
    func rejectsNonSoftwareLookup() {
        let song = Data(
            #"{"resultCount":1,"results":[{"wrapperType":"track","kind":"song","trackId":1689284187,"trackName":"A Song"}]}"#.utf8
        )

        #expect(throws: AppleResponseDecoder.Error.notSoftware) {
            try AppleResponseDecoder.app(
                from: song,
                storefront: .unitedStates
            )
        }
    }
}

private let reviewFeedJSON = #"""
{
  "feed": {
    "entry": [
      {
        "id": {"label": "14330676239"},
        "author": {"name": {"label": "elenayscarletttita"}},
        "updated": {"label": "2026-07-21T08:02:12-07:00"},
        "im:rating": {"label": "5"},
        "im:version": {"label": "26.30.0"},
        "title": {"label": "Taco Tuesday"},
        "content": {"label": "Friendly service."}
      },
      {
        "id": {"label": "broken"},
        "author": {"name": {"label": "Unknown"}},
        "updated": {"label": "not-a-date"},
        "im:rating": {"label": "9"},
        "title": {"label": "Malformed"},
        "content": {"label": "This row must not poison the feed."}
      }
    ]
  }
}
"""#

private let lookupJSON = #"""
{
  "resultCount": 1,
  "results": [
    {
      "wrapperType": "software",
      "kind": "software",
      "trackId": 284910350,
      "trackName": "Yelp: Food & Reviews",
      "sellerName": "Yelp, Inc.",
      "artworkUrl100": "https://example.com/icon.png",
      "version": "26.30.0",
      "primaryGenreName": "Food & Drink",
      "releaseDate": "2019-02-11T08:00:00Z",
      "currentVersionReleaseDate": "2026-07-20T11:47:08Z",
      "averageUserRating": 4.53,
      "userRatingCount": 2002740,
      "trackViewUrl": "https://apps.apple.com/us/app/id284910350"
    }
  ]
}
"""#

private let searchJSON = #"""
{
  "resultCount": 3,
  "results": [
    {
      "wrapperType": "software",
      "kind": "software",
      "trackId": 284910350,
      "trackName": "Yelp: Food & Reviews",
      "sellerName": "Yelp, Inc.",
      "artworkUrl100": "https://example.com/yelp.png",
      "version": "26.30.0",
      "primaryGenreName": "Food & Drink",
      "averageUserRating": 4.53,
      "userRatingCount": 2002740,
      "trackViewUrl": "https://apps.apple.com/cz/app/id284910350"
    },
    {
      "wrapperType": "software",
      "kind": "software",
      "trackId": 1234567890,
      "trackName": "Meal Planner",
      "sellerName": "Example Studio",
      "artworkUrl100": "https://example.com/meal.png",
      "version": "2.0",
      "primaryGenreName": "Lifestyle"
    },
    {
      "wrapperType": "track",
      "kind": "song",
      "trackId": 1689284187,
      "trackName": "A Song"
    }
  ]
}
"""#
