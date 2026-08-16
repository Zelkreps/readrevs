import Foundation
import Observation

enum CodexChatRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
}

struct CodexChatMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let role: CodexChatRole
    let text: String

    init(id: UUID = UUID(), role: CodexChatRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

@MainActor
@Observable
final class CodexResearchChatModel: Identifiable {
    let id: UUID
    let appID: Int64
    let appName: String
    let reviewCount: Int
    let storefrontCount: Int
    let codexModel: CodexModelConfiguration
    let reasoningEffort: CodexReasoningEffort
    let createdAt: Date

    var messages: [CodexChatMessage] = []
    var draft = ""
    var isRunning = false
    var activityText = "Preparing research..."
    var errorMessage: String?
    var historyErrorMessage: String?
    var updatedAt: Date
    var onTurnCompleted: ((CodexResearchChatModel) -> Void)?

    private let bundle: CodexResearchBundle
    private let historyRepository: CodexResearchHistoryRepository
    private var historyCreatedAt: Date?
    private var lastSubmittedPrompt: String?
    private var threadID: String?
    private var currentRun: CodexCLIRun?
    private var turnTask: Task<Void, Never>?

    init(
        id: UUID = UUID(),
        bundle: CodexResearchBundle,
        appID: Int64,
        appName: String,
        reviewCount: Int,
        storefrontCount: Int,
        codexModel: CodexModelConfiguration,
        reasoningEffort: CodexReasoningEffort,
        initialDraft: String,
        historyRepository: CodexResearchHistoryRepository
    ) {
        let now = Date.now
        self.id = id
        self.bundle = bundle
        self.appID = appID
        self.appName = appName
        self.reviewCount = reviewCount
        self.storefrontCount = storefrontCount
        self.codexModel = codexModel
        self.reasoningEffort = reasoningEffort
        draft = initialDraft
        self.historyRepository = historyRepository
        createdAt = now
        updatedAt = now
    }

    var canSendMessage: Bool {
        !isRunning
            && errorMessage == nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var primaryActionTitle: String {
        messages.isEmpty ? "Analyze" : "Send"
    }

    var canRetry: Bool {
        !isRunning && errorMessage != nil
    }

    var hasStarted: Bool {
        messages.contains(where: { $0.role == .user })
    }

    var hasCompletedResponse: Bool {
        messages.contains(where: { $0.role == .assistant })
    }

    func sendMessage() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, canSendMessage else { return }
        let isFirstTurn = threadID == nil
        draft = ""
        messages.append(CodexChatMessage(role: .user, text: prompt))
        historyCreatedAt = historyCreatedAt ?? .now
        updatedAt = .now
        let submittedPrompt = isFirstTurn ? bundle.prompt(for: prompt) : prompt
        lastSubmittedPrompt = submittedPrompt
        startTurn(prompt: submittedPrompt)
    }

    func retry() {
        guard canRetry, let lastSubmittedPrompt else { return }
        errorMessage = nil
        startTurn(prompt: lastSubmittedPrompt)
    }

    func loadHistory() throws -> [CodexResearchHistoryEntry] {
        try historyRepository.load()
    }

    func cancel() {
        currentRun?.cancel()
        currentRun = nil
        turnTask?.cancel()
        turnTask = nil
        if isRunning {
            activityText = "Stopped"
        }
        isRunning = false
        updatedAt = .now
    }

    private func startTurn(prompt: String) {
        turnTask?.cancel()
        turnTask = Task { [weak self] in
            await self?.performTurn(prompt: prompt)
        }
    }

    private func performTurn(prompt: String) async {
        isRunning = true
        errorMessage = nil
        activityText = "Checking Codex CLI..."
        var receivedAssistantMessage = false
        var completedTurn = false

        do {
            let client = try CodexCLIClient.live()
            try await client.verifyLogin()
            try Task.checkCancellation()

            let invocation: CodexCLIInvocation
            if let threadID {
                invocation = .resume(workspace: bundle.directoryURL, threadID: threadID)
            } else {
                invocation = .start(workspace: bundle.directoryURL)
            }

            let run = client.run(
                prompt: prompt,
                invocation: invocation,
                modelID: codexModel.modelID,
                reasoningEffort: reasoningEffort
            )
            currentRun = run
            activityText = threadID == nil
                ? "Starting a private research thread..."
                : "Asking Codex..."

            eventLoop: for try await event in run.events {
                try Task.checkCancellation()
                switch event {
                case let .threadStarted(identifier):
                    threadID = identifier
                case .turnStarted:
                    activityText = "Analyzing review patterns..."
                case let .activity(kind):
                    activityText = activityDescription(for: kind)
                case let .assistantMessage(text):
                    receivedAssistantMessage = true
                    messages.append(CodexChatMessage(role: .assistant, text: text))
                    persistHistory()
                    activityText = "Finishing..."
                case .turnCompleted:
                    activityText = "Ready for a follow-up"
                case let .failure(message):
                    throw ChatError.cli(message)
                case .ignored:
                    continue eventLoop
                }
            }

            try Task.checkCancellation()
            if !receivedAssistantMessage {
                throw ChatError.emptyResponse
            }
            completedTurn = true
        } catch is CancellationError {
            activityText = "Stopped"
        } catch {
            errorMessage = error.localizedDescription
            activityText = "Codex needs attention"
        }

        currentRun = nil
        isRunning = false
        turnTask = nil
        updatedAt = .now
        if completedTurn {
            onTurnCompleted?(self)
        }
    }

    private func persistHistory() {
        let now = Date.now
        let entry = CodexResearchHistoryEntry(
            id: id,
            appID: appID,
            appName: appName,
            reviewCount: reviewCount,
            storefrontCount: storefrontCount,
            createdAt: historyCreatedAt ?? now,
            updatedAt: now,
            codexModel: codexModel,
            reasoningEffort: reasoningEffort,
            messages: messages
        )
        do {
            try historyRepository.upsert(entry)
            historyErrorMessage = nil
        } catch {
            historyErrorMessage = "This response could not be saved to history: \(error.localizedDescription)"
        }
    }

    private func activityDescription(for kind: String) -> String {
        switch kind {
        case "reasoning":
            "Synthesizing findings..."
        case "command_execution":
            "Reading the review dataset..."
        case "mcp_tool_call":
            "Using a configured Codex tool..."
        case "web_search":
            "Checking supporting context..."
        default:
            "Working through the evidence..."
        }
    }

    private enum ChatError: Swift.Error, LocalizedError {
        case cli(String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case let .cli(message):
                message
            case .emptyResponse:
                "Codex finished without returning a message. Try the analysis again."
            }
        }
    }
}
