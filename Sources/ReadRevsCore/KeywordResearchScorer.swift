import Foundation

public enum KeywordResearchScorer {
    public static func enrich(
        _ records: [KeywordRecord],
        topic: String,
        seedKeywords: [String]
    ) -> [KeywordRecord] {
        let terms = scoringTerms(topic: topic, seedKeywords: seedKeywords)
        return records.map { record in
            var enriched = record
            let normalizedKeyword = normalize(record.keyword)
            var relevance = 0.0
              var matchedTerms = record.matchedTerms
              var tags = record.intentTags

            for term in terms where matches(keyword: normalizedKeyword, term: term.normalized) {
                relevance += term.weight
                if !matchedTerms.contains(term.display) { matchedTerms.append(term.display) }
                if !tags.contains(term.source) { tags.append(term.source) }
            }

            relevance *= genreBoost(record.genre)
            enriched.relevanceScore = rounded(relevance, places: 3)
            let popularitySignal = record.isAppleAdsSuggestion ? 0 : record.popularity
            enriched.opportunityScore = rounded(
                relevance * Foundation.sqrt(Double(max(popularitySignal, 0))) * 10,
                places: 2
            )
            enriched.matchedTerms = matchedTerms
            enriched.intentTags = tags
            return enriched
        }
    }

    private static func scoringTerms(topic: String, seedKeywords: [String]) -> [ScoringTerm] {
        var byNormalized: [String: ScoringTerm] = [:]

        for seed in seedKeywords {
            addTerm(seed, weight: 2.4, source: "seed", to: &byNormalized)
            for token in tokens(seed) {
                addTerm(token, weight: 1.0, source: "seed", to: &byNormalized)
            }
        }

        for token in tokens(topic) {
            addTerm(token, weight: 0.8, source: "topic", to: &byNormalized)
        }

        let context = normalize(([topic] + seedKeywords).joined(separator: " "))
        for concept in geoConcepts where concept.signals.contains(where: {
            matches(keyword: context, term: normalize($0))
        }) {
            for term in concept.terms {
                addTerm(term, weight: concept.weight, source: concept.name, to: &byNormalized)
            }
        }

        return byNormalized.values.sorted { lhs, rhs in
            if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
            return lhs.display.localizedCaseInsensitiveCompare(rhs.display) == .orderedAscending
        }
    }

    private static func addTerm(
        _ display: String,
        weight: Double,
        source: String,
        to terms: inout [String: ScoringTerm]
    ) {
        let normalized = normalize(display)
        guard !normalized.isEmpty else { return }
        let candidate = ScoringTerm(
            display: display.trimmingCharacters(in: .whitespacesAndNewlines),
            normalized: normalized,
            weight: weight,
            source: source
        )
        if let current = terms[normalized], current.weight >= candidate.weight { return }
        terms[normalized] = candidate
    }

    private static func tokens(_ value: String) -> [String] {
        normalize(value).split(separator: " ").map(String.init).filter { token in
            token.count >= 3 || token.unicodeScalars.contains { $0.value > 127 }
        }
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let characters = folded.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(characters)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func matches(keyword: String, term: String) -> Bool {
        guard !term.isEmpty else { return false }
        if term.contains(" ") || term.unicodeScalars.contains(where: { $0.value > 127 }) {
            return keyword.contains(term)
        }
        return keyword.split(separator: " ").contains(Substring(term))
    }

    private static func genreBoost(_ genre: String) -> Double {
        switch genre.lowercased() {
        case "education": 1.18
        case "games", "reference": 1.12
        case "travel": 1.05
        case "entertainment": 1.02
        default: 1
        }
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let factor = Foundation.pow(10, Double(places))
        return (value * factor).rounded() / factor
    }

    private static let geoConcepts: [ResearchConcept] = [
        ResearchConcept(
            name: "flags",
            signals: ["flag", "flags", "vlajka", "vlajky"],
            terms: [
                "flag", "flags", "vlajka", "vlajky", "bandera", "banderas", "flagge", "flaggen",
                "drapeau", "drapeaux", "국기", "깃발",
            ],
            weight: 1.6
        ),
        ResearchConcept(
            name: "countries",
            signals: ["country", "countries", "země", "státy"],
            terms: [
                "country", "countries", "země", "státy", "país", "países", "land", "länder", "pays",
                "국가", "나라",
            ],
            weight: 1.3
        ),
        ResearchConcept(
            name: "capitals",
            signals: ["capital", "capitals", "hlavní město", "hlavní města"],
            terms: [
                "capital", "capitals", "hlavní město", "hlavní města", "capitales", "hauptstadt",
                "hauptstädte", "capitale", "capitales", "수도",
            ],
            weight: 1.4
        ),
        ResearchConcept(
            name: "geography",
            signals: ["geography", "zeměpis", "geografie"],
            terms: [
                "geography", "zeměpis", "geografie", "geografía", "erdkunde", "géographie", "지리",
            ],
            weight: 1.7
        ),
        ResearchConcept(
            name: "map",
            signals: ["map", "maps", "mapa"],
            terms: ["map", "maps", "mapa", "karte", "carte", "지도"],
            weight: 1.1
        ),
        ResearchConcept(
            name: "quiz",
            signals: ["quiz", "quizzes", "kvíz"],
            terms: ["quiz", "quizzes", "kvíz", "cuestionario", "퀴즈"],
            weight: 0.8
        ),
    ]
}

private struct ScoringTerm {
    let display: String
    let normalized: String
    let weight: Double
    let source: String
}

private struct ResearchConcept {
    let name: String
    let signals: [String]
    let terms: [String]
    let weight: Double
}
