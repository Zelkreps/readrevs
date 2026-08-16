import Foundation

public struct AppStoreSearchHint: Equatable, Sendable {
    public let term: String

    public init(term: String) {
        self.term = term.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol AppStoreSearchHintsProviding: Sendable {
    func fetch(seed: String, target: StoreTarget) async throws -> [AppStoreSearchHint]
}

public struct AppStoreSearchHintsClient: AppStoreSearchHintsProviding {
    private static let requestLimiter = RequestRateLimiter(minimumInterval: 0.25)

    public init() {}

    public func fetch(seed: String, target: StoreTarget) async throws -> [AppStoreSearchHint] {
        let request = try Self.request(seed: seed, target: target)
        try await Self.requestLimiter.waitForTurn()
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ServiceError.httpStatus(httpResponse.statusCode)
        }
        return try AppStoreSearchHintsParser.parse(data)
    }

    public static func request(seed: String, target: StoreTarget) throws -> URLRequest {
        let trimmedSeed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSeed.isEmpty,
              let storefrontID = AppStoreStorefrontID.value(for: target.store),
              var components = URLComponents(
                  string: "https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints"
              )
        else {
            throw ServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "clientApplication", value: "Software"),
            URLQueryItem(name: "term", value: trimmedSeed),
        ]
        guard let url = components.url else { throw ServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("application/x-plist", forHTTPHeaderField: "Accept")
        request.setValue("\(storefrontID),29", forHTTPHeaderField: "X-Apple-Store-Front")
        request.setValue(
            "\(target.language.lowercased())_\(target.store.uppercased())",
            forHTTPHeaderField: "Accept-Language"
        )
        request.setValue("readrevs-macos/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }
}

public enum AppStoreSearchHintsParser {
    public static func parse(_ data: Data) throws -> [AppStoreSearchHint] {
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let root = propertyList as? [String: Any],
              let rawHints = root["hints"] as? [[String: Any]]
        else {
            throw ServiceError.invalidResponse
        }

        var seen: Set<String> = []
        return rawHints.compactMap { item in
            guard let rawTerm = item["term"] as? String else { return nil }
            let hint = AppStoreSearchHint(term: rawTerm)
            let normalized = normalizedKeyword(hint.term)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return hint
        }
    }
}

public enum KeywordSuggestionSeedBuilder {
    public static func seeds(
        project: ResearchProject,
        store storeCode: String,
        focusAppName: String? = nil,
        limit: Int = 6
    ) -> [String] {
        let normalizedStore = storeCode.lowercased()
        let trackedKeywords = project.keywords.compactMap { record -> String? in
            guard record.isActivelyTracked, record.store == normalizedStore else { return nil }
            return record.keyword
        }

        let candidates = project.seedKeywords
            + trackedKeywords
            + [project.topic]
            + [focusAppName ?? ""]
            + [cleanedProjectName(project.name)]

        var seen: Set<String> = []
        return candidates.compactMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = normalizedKeyword(trimmed)
            guard !trimmed.isEmpty, seen.insert(normalized).inserted else { return nil }
            return trimmed
        }.prefix(max(limit, 0)).map { $0 }
    }

    private static func cleanedProjectName(_ value: String) -> String {
        var humanized = ""
        var previousWasLowercase = false
        for character in value {
            if character.isUppercase, previousWasLowercase {
                humanized.append(" ")
            }
            humanized.append(character)
            previousWasLowercase = character.isLowercase || character.isNumber
        }

        let words = humanized.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let meaningful = words.filter { !genericProjectWords.contains($0.lowercased()) }
        return meaningful.joined(separator: " ")
    }

    private static let genericProjectWords: Set<String> = [
        "app", "apps", "application", "idea", "ideas", "keyword", "keywords",
        "new", "project", "research", "aso", "temp", "temporary", "test",
    ]
}

public enum AppStoreStorefrontID {
    public static func value(for countryCode: String) -> Int? {
        values[countryCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    private static let values: [String: Int] = [
        "ae": 143481, "al": 143575, "am": 143524, "ar": 143505, "at": 143445,
        "au": 143460, "az": 143568, "be": 143446, "bg": 143526, "bh": 143559,
        "bo": 143556, "br": 143503, "ca": 143455, "ch": 143459, "cl": 143483,
        "cn": 143465, "co": 143501, "cr": 143495, "cy": 143557, "cz": 143489,
        "de": 143443, "dk": 143458, "do": 143508, "dz": 143563, "ec": 143509,
        "ee": 143518, "eg": 143516, "es": 143454, "fi": 143447, "fr": 143442,
        "gb": 143444, "gh": 143573, "gr": 143448, "gt": 143504, "hk": 143463,
        "hn": 143510, "hr": 143494, "hu": 143482, "id": 143476, "ie": 143449,
        "il": 143491, "in": 143467, "iq": 143617, "is": 143558, "it": 143450,
        "jo": 143528, "jp": 143462, "ke": 143529, "kg": 143586, "kh": 143579,
        "kr": 143466, "kw": 143493, "kz": 143517, "lb": 143497, "lk": 143486,
        "lu": 143451, "lv": 143519, "ma": 143620, "mn": 143592, "mo": 143515,
        "mx": 143468, "my": 143473, "nl": 143452, "no": 143457, "np": 143484,
        "nz": 143461, "om": 143562, "pa": 143485, "pe": 143507, "ph": 143474,
        "pk": 143477, "pl": 143478, "pt": 143453, "py": 143513, "qa": 143498,
        "ro": 143487, "sa": 143479, "se": 143456, "sg": 143464, "si": 143499,
        "sk": 143496, "sv": 143506, "th": 143475, "tr": 143480, "tw": 143470,
        "ua": 143492, "us": 143441, "uz": 143566, "vn": 143471, "za": 143472,
    ]
}

private func normalizedKeyword(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}
