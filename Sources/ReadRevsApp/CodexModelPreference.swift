import Foundation

struct CodexModelConfiguration: Codable, Equatable, Sendable {
    let modelID: String?
    let displayName: String
}

enum CodexReasoningEffort: String, CaseIterable, Identifiable, Codable, Sendable {
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    static let storageKey = "codexResearchReasoningEffort"
    static let defaultValue: Self = .medium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "XHigh"
        case .max: "Max"
        case .ultra: "Ultra"
        }
    }

    var detail: String {
        switch self {
        case .low:
            "Prioritizes speed for straightforward review questions."
        case .medium:
            "Balances depth and speed for most review research."
        case .high:
            "Spends more time tracing patterns and checking assumptions."
        case .xhigh:
            "Uses extra reasoning depth for demanding product and strategy analysis."
        case .max:
            "Uses maximum reasoning depth for the hardest research questions."
        case .ultra:
            "Uses maximum reasoning with automatic task delegation."
        }
    }

    static func resolve(storedValue: String?) -> Self {
        storedValue.flatMap(Self.init(rawValue:)) ?? defaultValue
    }

    var cliConfigurationOverride: String {
        #"model_reasoning_effort="\#(rawValue)""#
    }
}

struct CodexModelDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let modelDescription: String
    let defaultReasoningEffort: CodexReasoningEffort
    let supportedReasoningEfforts: [CodexReasoningEffort]

    var configuration: CodexModelConfiguration {
        CodexModelConfiguration(modelID: id, displayName: displayName)
    }
}

struct CodexModelCatalog: Equatable, Sendable {
    let models: [CodexModelDescriptor]

    var defaultModel: CodexModelDescriptor {
        model(id: CodexResearchPreferences.defaultModelID) ?? models[0]
    }

    func model(id: String?) -> CodexModelDescriptor? {
        guard let id else { return nil }
        return models.first { $0.id == id }
    }

    static func decode(_ data: Data) throws -> Self {
        let payload = try JSONDecoder().decode(CatalogPayload.self, from: data)
        let models = payload.models
            .filter { $0.visibility == "list" }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.priority < rhs.priority
            }
            .compactMap { model -> CodexModelDescriptor? in
                guard
                    let defaultEffort = CodexReasoningEffort(rawValue: model.defaultReasoningLevel),
                    !model.slug.isEmpty,
                    !model.displayName.isEmpty
                else {
                    return nil
                }

                let supported = model.supportedReasoningLevels.compactMap {
                    CodexReasoningEffort(rawValue: $0.effort)
                }
                guard !supported.isEmpty else { return nil }

                return CodexModelDescriptor(
                    id: model.slug,
                    displayName: model.displayName,
                    modelDescription: model.description,
                    defaultReasoningEffort: supported.contains(defaultEffort) ? defaultEffort : supported[0],
                    supportedReasoningEfforts: supported
                )
            }

        guard !models.isEmpty else { throw CatalogError.noVisibleModels }
        return Self(models: models)
    }

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Self {
        let catalogURL: URL?
        if let codexHome = environment["CODEX_HOME"], !codexHome.isEmpty {
            catalogURL = URL(fileURLWithPath: codexHome, isDirectory: true)
                .appendingPathComponent("models_cache.json")
        } else if let home = environment["HOME"], !home.isEmpty {
            catalogURL = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".codex/models_cache.json")
        } else {
            catalogURL = nil
        }

        guard
            let catalogURL,
            let data = fileManager.contents(atPath: catalogURL.path),
            let catalog = try? decode(data)
        else {
            return fallback
        }
        return catalog
    }

    static let fallback = Self(models: [
        descriptor(
            "gpt-5.6-sol",
            "GPT-5.6-Sol",
            "Latest frontier agentic coding model.",
            defaultEffort: .low,
            efforts: [.low, .medium, .high, .xhigh, .max, .ultra]
        ),
        descriptor(
            "gpt-5.6-terra",
            "GPT-5.6-Terra",
            "Balanced agentic coding model for everyday work.",
            defaultEffort: .medium,
            efforts: [.low, .medium, .high, .xhigh, .max, .ultra]
        ),
        descriptor(
            "gpt-5.6-luna",
            "GPT-5.6-Luna",
            "Fast and affordable agentic coding model.",
            defaultEffort: .medium,
            efforts: [.low, .medium, .high, .xhigh, .max]
        ),
        descriptor(
            "gpt-5.5",
            "GPT-5.5",
            "Frontier model for complex coding, research, and real-world work.",
            defaultEffort: .medium,
            efforts: [.low, .medium, .high, .xhigh]
        ),
        descriptor(
            "gpt-5.4",
            "GPT-5.4",
            "Strong model for everyday coding.",
            defaultEffort: .medium,
            efforts: [.low, .medium, .high, .xhigh]
        ),
        descriptor(
            "gpt-5.4-mini",
            "GPT-5.4-Mini",
            "Small, fast, and cost-efficient model for simpler coding tasks.",
            defaultEffort: .medium,
            efforts: [.low, .medium, .high, .xhigh]
        ),
        descriptor(
            "gpt-5.3-codex-spark",
            "GPT-5.3-Codex-Spark",
            "Ultra-fast coding model.",
            defaultEffort: .high,
            efforts: [.low, .medium, .high, .xhigh]
        ),
    ])

    private static func descriptor(
        _ id: String,
        _ displayName: String,
        _ description: String,
        defaultEffort: CodexReasoningEffort,
        efforts: [CodexReasoningEffort]
    ) -> CodexModelDescriptor {
        CodexModelDescriptor(
            id: id,
            displayName: displayName,
            modelDescription: description,
            defaultReasoningEffort: defaultEffort,
            supportedReasoningEfforts: efforts
        )
    }

    private struct CatalogPayload: Decodable {
        let models: [CatalogModel]
    }

    private struct CatalogModel: Decodable {
        let slug: String
        let displayName: String
        let description: String
        let defaultReasoningLevel: String
        let supportedReasoningLevels: [CatalogReasoningLevel]
        let visibility: String
        let priority: Int

        enum CodingKeys: String, CodingKey {
            case slug
            case displayName = "display_name"
            case description
            case defaultReasoningLevel = "default_reasoning_level"
            case supportedReasoningLevels = "supported_reasoning_levels"
            case visibility
            case priority
        }
    }

    private struct CatalogReasoningLevel: Decodable {
        let effort: String
    }

    private enum CatalogError: Error {
        case noVisibleModels
    }
}

struct CodexResearchConfiguration: Equatable, Sendable {
    let model: CodexModelConfiguration
    let reasoningEffort: CodexReasoningEffort
}

enum CodexResearchPreferences {
    static let modelIDStorageKey = "codexResearchModelID"
    static let defaultModelID = "gpt-5.6-terra"

    static func resolve(
        storedModelID: String?,
        storedReasoningEffort: String?,
        catalog: CodexModelCatalog = .live()
    ) -> CodexResearchConfiguration {
        let descriptor = catalog.model(id: storedModelID) ?? catalog.defaultModel
        let storedEffort = storedReasoningEffort.flatMap(CodexReasoningEffort.init(rawValue:))
        let effort = storedEffort.flatMap { candidate in
            descriptor.supportedReasoningEfforts.contains(candidate) ? candidate : nil
        } ?? descriptor.defaultReasoningEffort

        return CodexResearchConfiguration(
            model: descriptor.configuration,
            reasoningEffort: effort
        )
    }
}
