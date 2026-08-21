import Foundation
import Testing
@testable import ReadRevsCore

@Test("Apple Ads suggestion scores are not storefront popularity measurements")
func appleAdsSuggestionScoreIsStoredSeparately() {
    let record = KeywordRecord(
        keyword: "world flags",
        language: "en",
        store: "us",
        genre: "Apple Ads Suggestions",
        popularity: 0,
        suggestionScore: 84,
        intentTags: ["apple-ads-suggestion"],
        source: .appleAds,
        isTracked: false
    )

    #expect(record.suggestionScore == 84)
    #expect(record.effectiveSuggestionScore == 84)
    #expect(!record.hasPopularityMeasurement)

    let enriched = KeywordResearchScorer.enrich(
        [record],
        topic: "world flags",
        seedKeywords: ["flags"]
    )
    #expect(enriched[0].relevanceScore > 0)
    #expect(enriched[0].opportunityScore == 0)
}

@Test("Only Apple Ads popularity report records are exact storefront measurements")
func appleAdsPopularityReportIsExact() {
    let record = KeywordRecord(
        keyword: "world flags",
        language: "en",
        store: "us",
        country: "US",
        genre: "Education",
        popularity: 81,
        intentTags: ["apple-ads-popularity"],
        source: .appleAds,
        isTracked: false
    )

    #expect(record.hasPopularityMeasurement)
    #expect(record.effectiveSuggestionScore == nil)
}

@Test("Legacy suggestion-derived exact records remain readable without becoming exact popularity")
func legacyAppleAdsExactRecordMigratesSemantically() throws {
    let json = """
    {
      "keyword": "world flags",
      "language": "en",
      "store": "us",
      "country": "US",
      "genre": "Apple Ads",
      "popularity": 84,
      "relevanceScore": 0,
      "opportunityScore": 0,
      "intentTags": ["apple-ads-exact"],
      "matchedTerms": ["world flags"],
      "source": "appleAds",
      "isFavorite": false,
      "isTracked": false
    }
    """

    let record = try JSONDecoder().decode(KeywordRecord.self, from: Data(json.utf8))

    #expect(record.suggestionScore == nil)
    #expect(record.effectiveSuggestionScore == 84)
    #expect(!record.hasPopularityMeasurement)
}

@Test("Suggestion scores round-trip through the library record format")
func suggestionScoreRoundTrips() throws {
    let expected = KeywordRecord(
        keyword: "world flags",
        language: "en",
        store: "us",
        genre: "Apple Ads Suggestions",
        popularity: 0,
        suggestionScore: 84,
        intentTags: ["apple-ads-suggestion"],
        source: .appleAds,
        isTracked: false
    )

    let encoded = try JSONEncoder().encode(expected)
    let decoded = try JSONDecoder().decode(KeywordRecord.self, from: encoded)

    #expect(decoded == expected)
}
