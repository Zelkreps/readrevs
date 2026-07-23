import Foundation
import Observation

enum CodexChatRole: Equatable, Sendable {
    case user
    case assistant
}

struct CodexChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: CodexChatRole
    let text: String
}

@MainActor
@Observable
final class CodexResearchChatModel {
    let appName: String
    let reviewCount: Int
    let storefrontCount: Int
    let codexModel: CodexModelConfiguration
    let reasoningEffort: CodexReasoningEffort

    var messages: [CodexChatMessage] = []
    var draft = ""
    var isRunning = false
    var activityText = "Preparing research…"
    var errorMessage: String?

    private let bundle: CodexResearchBundle
    private var hasStarted = false
    private var threadID: String?
    private var currentRun: CodexCLIRun?
    private var turnTask: Task<Void, Never>?

    init(
        bundle: CodexResearchBundle,
        appName: String,
        reviewCount: Int,
        storefrontCount: Int,
        codexModel: CodexModelConfiguration,
        reasoningEffort: CodexReasoningEffort
    ) {
        self.bundle = bundle
        self.appName = appName
        self.reviewCount = reviewCount
        self.storefrontCount = storefrontCount
        self.codexModel = codexModel
        self.reasoningEffort = reasoningEffort
    }

    var canSendFollowUp: Bool {
        threadID != nil && !isRunning && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRetry: Bool {
        !isRunning && errorMessage != nil
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        messages.append(
            CodexChatMessage(
                role: .user,
                text: "Analyze all \(reviewCount.formatted()) synced reviews for \(appName)."
            )
        )
        startTurn(prompt: bundle.initialPrompt)
    }

    func sendFollowUp() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isRunning, threadID != nil else { return }
        draft = ""
        messages.append(CodexChatMessage(role: .user, text: prompt))
        startTurn(prompt: prompt)
    }

    func retry() {
        guard canRetry else { return }
        errorMessage = nil
        startTurn(prompt: threadID == nil ? bundle.initialPrompt : "Continue the interrupted analysis.")
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
        activityText = "Checking Codex CLI…"
        var receivedAssistantMessage = false

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
            activityText = threadID == nil ? "Starting a private research thread…" : "Asking Codex…"

            eventLoop: for try await event in run.events {
                try Task.checkCancellation()
                switch event {
                case let .threadStarted(identifier):
                    threadID = identifier
                case .turnStarted:
                    activityText = "Analyzing review patterns…"
                case let .activity(kind):
                    activityText = activityDescription(for: kind)
                case let .assistantMessage(text):
                    receivedAssistantMessage = true
                    messages.append(CodexChatMessage(role: .assistant, text: text))
                    activityText = "Finishing…"
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
        } catch is CancellationError {
            activityText = "Stopped"
        } catch {
            errorMessage = error.localizedDescription
            activityText = "Codex needs attention"
        }

        currentRun = nil
        isRunning = false
        turnTask = nil
    }

    private func activityDescription(for kind: String) -> String {
        switch kind {
        case "reasoning":
            "Synthesizing findings…"
        case "command_execution":
            "Reading the review dataset…"
        case "mcp_tool_call":
            "Using a configured Codex tool…"
        case "web_search":
            "Checking supporting context…"
        default:
            "Working through the evidence…"
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
