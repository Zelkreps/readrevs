import Foundation
import Testing
@testable import ReadRevsCore

@Test
func appStoreSearchHintsParserExtractsUniqueTerms() throws {
    let data = Data(
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
          <dict>
            <key>title</key><string>Suggestions</string>
            <key>hints</key>
            <array>
              <dict><key>term</key><string>metronom</string></dict>
              <dict><key>term</key><string>metronom zdarma</string></dict>
              <dict><key>term</key><string> Metronom </string></dict>
              <dict><key>url</key><string>https://example.com</string></dict>
            </array>
          </dict>
        </plist>
        """.utf8
    )

    let hints = try AppStoreSearchHintsParser.parse(data)

    #expect(hints.map(\.term) == ["metronom", "metronom zdarma"])
}

@Test
func appStoreSearchHintsRequestUsesTheSelectedStorefrontAndLanguage() throws {
    let request = try AppStoreSearchHintsClient.request(
        seed: "metronom",
        target: StoreTarget(language: "cs", store: "cz")
    )

    #expect(request.value(forHTTPHeaderField: "X-Apple-Store-Front") == "143489,29")
    #expect(request.value(forHTTPHeaderField: "Accept-Language") == "cs_CZ")
    #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "term" })?.value == "metronom")
}

@Test
func suggestionSeedsUseProjectContextAndIgnoreOtherStores() {
    let project = ResearchProject(
        name: "Geography Practice Research",
        topic: "world geography",
        targets: [StoreTarget(language: "cs", store: "cz")],
        genres: ["Education"],
        seedKeywords: ["flag quiz"],
        keywords: [
            KeywordRecord(
                keyword: "vlajky",
                language: "cs",
                store: "cz",
                genre: "Manual",
                popularity: 0,
                source: .manual,
                isTracked: true
            ),
            KeywordRecord(
                keyword: "countries",
                language: "en",
                store: "us",
                genre: "Manual",
                popularity: 0,
                source: .manual,
                isTracked: true
            ),
        ]
    )

    let seeds = KeywordSuggestionSeedBuilder.seeds(
        project: project,
        store: "cz",
        focusAppName: "World Flags Quiz"
    )

    #expect(seeds == [
        "flag quiz",
        "vlajky",
        "world geography",
        "World Flags Quiz",
        "Geography Practice",
    ])
}

@Test
func genericProjectNameDoesNotCreateSuggestionContext() {
    let project = ResearchProject(
        name: "test",
        topic: "",
        targets: [StoreTarget(language: "cs", store: "cz")],
        genres: [],
        seedKeywords: []
    )

    #expect(KeywordSuggestionSeedBuilder.seeds(project: project, store: "cz").isEmpty)
}

@Test
func appleSearchHintRecordsRemainUntrackedAndDoNotPretendToHavePopularity() {
    let record = KeywordRecord(
        keyword: "metronom zdarma",
        language: "cs",
        store: "cz",
        genre: "Apple Search Suggestions",
        popularity: 0,
        source: .appleSearchHints
    )

    #expect(!record.isActivelyTracked)
    #expect(!record.hasPopularityMeasurement)
}
