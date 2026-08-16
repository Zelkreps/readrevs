import Foundation
import Testing
@testable import ReadRevsCore

@Test("Legacy popularity source names decode into neutral local sources")
func legacyPopularitySourcesRemainDecodable() throws {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    #expect(
        try decoder.decode(KeywordSource.self, from: Data(#""tryAstro""#.utf8))
            == .legacyPopularity
    )
    #expect(
        try decoder.decode(KeywordSource.self, from: Data(#""astroCSV""#.utf8))
            == .csvImport
    )
    #expect(String(decoding: try encoder.encode(KeywordSource.legacyPopularity), as: UTF8.self) == #""legacyPopularity""#)
    #expect(String(decoding: try encoder.encode(KeywordSource.csvImport), as: UTF8.self) == #""csvImport""#)
}

@Test
func csvImporterParsesQuotedFieldsAndExistingExportColumns() throws {
    let csv = """
    keyword,language,store,country,genre,popularity,relevance_score,opportunity_score,intent_tags,matched_terms,month,source_id
    "flags, quiz",en,us,US,Education,48,3.5,210.25,"flags;quiz","flag;quiz",2026-07,42
    """

    let records = try KeywordCSVImporter().parse(Data(csv.utf8))

    try #require(records.count == 1)
    #expect(records[0].keyword == "flags, quiz")
    #expect(records[0].popularity == 48)
    #expect(records[0].opportunityScore == 210.25)
    #expect(records[0].intentTags == ["flags", "quiz"])
    #expect(records[0].source == .csvImport)
    #expect(records[0].isActivelyTracked)
}

@Test
func csvImporterParsesWindowsLineEndingsUsedByExistingExports() throws {
    let csv = "keyword,language,store,country,genre,popularity,relevance_score,opportunity_score,intent_tags,matched_terms,month,source_id\r\n"
        + "flag quiz,en,gb,United Kingdom,Education,49,5.886,412.01,flags;quiz,flag;quiz;flag quiz,2026-01-01,110824\r\n"

    let records = try KeywordCSVImporter().parse(Data(csv.utf8))

    try #require(records.count == 1)
    #expect(records[0].keyword == "flag quiz")
    #expect(records[0].store == "gb")
    #expect(records[0].opportunityScore == 412.01)
}

@Test
func keywordMergeUsesIncomingMeasurementAndPreservesFavorite() {
    let existing = KeywordRecord(
        keyword: "Flag Quiz",
        language: "en",
        store: "us",
        genre: "Education",
        popularity: 62,
        opportunityScore: 410,
        source: .csvImport,
        isFavorite: true,
        note: "Strong fit for the subtitle"
    )
    let refreshed = KeywordRecord(
        keyword: "flag quiz",
        language: "en",
        store: "US",
        genre: "Education",
        popularity: 31,
        opportunityScore: 105,
        source: .legacyPopularity
    )

    let merged = KeywordRecord.merge(existing: [existing], incoming: [refreshed])

    #expect(merged.count == 1)
    #expect(merged[0].popularity == 31)
    #expect(merged[0].opportunityScore == 105)
    #expect(merged[0].source == .legacyPopularity)
    #expect(merged[0].isFavorite)
    #expect(merged[0].isActivelyTracked)
    #expect(merged[0].note == "Strong fit for the subtitle")
}

@Test
func keywordMergePreservesPopularityAttemptWhenIncomingRecordHasNoAttempt() {
    let checkedAt = Date(timeIntervalSince1970: 500)
    let existing = KeywordRecord(
        keyword: "flags",
        language: "en",
        store: "us",
        genre: "Education",
        popularity: 0,
        source: .manual,
        isTracked: true,
        popularityCheckedAt: checkedAt
    )
    let incoming = KeywordRecord(
        keyword: "flags",
        language: "en",
        store: "us",
        genre: "Education",
        popularity: 0,
        source: .manual,
        isTracked: true
    )

    let merged = KeywordRecord.merge(existing: [existing], incoming: [incoming])

    #expect(merged.first?.popularityCheckedAt == checkedAt)
}

@Test
func keywordMergeKeepsDifferentLanguagesInTheSameStoreSeparate() {
    let english = KeywordRecord(
        keyword: "capital",
        language: "en",
        store: "ca",
        genre: "Education",
        popularity: 40
    )
    let french = KeywordRecord(
        keyword: "capital",
        language: "fr",
        store: "ca",
        genre: "Education",
        popularity: 35
    )

    #expect(KeywordRecord.merge(existing: [english], incoming: [french]).count == 2)
}

@Test
func keywordTrackingAppliesAcrossGenresForTheSameStoreAndLanguage() {
    let tracked = KeywordRecord(
        keyword: "flag quiz",
        language: "en",
        store: "us",
        genre: "Education",
        popularity: 40,
        source: .manual,
        isTracked: true
    )
    let suggestionInAnotherGenre = KeywordRecord(
        keyword: "Flag Quiz",
        language: "en",
        store: "us",
        genre: "Games",
        popularity: 45,
        source: .legacyPopularity,
        isTracked: false
    )

    let merged = KeywordRecord.merge(existing: [tracked], incoming: [suggestionInAnotherGenre])

    #expect(merged.count == 2)
    #expect(merged.allSatisfy { $0.isActivelyTracked })
}

@Test
func researchScorerUsesTopicAndSeedKeywords() {
    let relevant = KeywordRecord(
        keyword: "world flag quiz",
        language: "en",
        store: "us",
        genre: "Education",
        popularity: 49
    )
    let unrelated = KeywordRecord(
        keyword: "photo editor",
        language: "en",
        store: "us",
        genre: "Education",
        popularity: 80
    )

    let enriched = KeywordResearchScorer.enrich(
        [relevant, unrelated],
        topic: "flags countries and geography quizzes",
        seedKeywords: ["world flag", "geography quiz"]
    )

    #expect(enriched[0].relevanceScore > enriched[1].relevanceScore)
    #expect(enriched[0].opportunityScore > enriched[1].opportunityScore)
    #expect(enriched[0].matchedTerms.contains("world flag"))
}

@Test
func researchScorerExpandsDetectedGeoConceptsAcrossLanguages() {
    let spanish = KeywordRecord(
        keyword: "banderas del mundo",
        language: "es",
        store: "es",
        genre: "Education",
        popularity: 45
    )
    let korean = KeywordRecord(
        keyword: "세계 국기 퀴즈",
        language: "ko",
        store: "kr",
        genre: "Games",
        popularity: 45
    )

    let enriched = KeywordResearchScorer.enrich(
        [spanish, korean],
        topic: "flags, countries and geography quizzes",
        seedKeywords: ["flag quiz"]
    )

    #expect(enriched.allSatisfy { $0.relevanceScore >= 1.5 })
    #expect(enriched[0].matchedTerms.contains("banderas"))
    #expect(enriched[1].matchedTerms.contains("국기"))
}
