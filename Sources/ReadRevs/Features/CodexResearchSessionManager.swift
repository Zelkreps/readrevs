import Foundation
import Observation

struct CodexResearchSessionRequest {
    let bundle: CodexResearchBundle
    let appID: Int64
    let appName: String
    let reviewCount: Int
    let storefrontCount: Int
    let codexModel: CodexModelConfiguration
    let reasoningEffort: CodexReasoningEffort
    let initialDraft: String
}

struct CodexResearchCompletionNotice: Equatable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let appName: String
}

@MainActor
@Observable
final class CodexResearchSessionManager {
    enum ManagerError: Swift.Error, LocalizedError {
        case historyUnavailable

        var errorDescription: String? {
            switch self {
            case .historyUnavailable:
                "Research history could not be opened from Application Support."
            }
        }
    }

    private(set) var sessions: [CodexResearchChatModel] = []
    var presentedSession: CodexResearchChatModel?
    private(set) var completionNotice: CodexResearchCompletionNotice?
    private(set) var historyEntries: [CodexResearchHistoryEntry] = []
    private(set) var historyErrorMessage: String?

    private let historyRepository: CodexResearchHistoryRepository?
    private var noticeDismissalTask: Task<Void, Never>?

    init(
        historyRepository: CodexResearchHistoryRepository? = try? CodexResearchHistoryRepository.live()
    ) {
        self.historyRepository = historyRepository
    }

    var runningSessionCount: Int {
        sessions.count(where: \.isRunning)
    }

    var researchCenterSessions: [CodexResearchChatModel] {
        sessions.filter(\.hasStarted)
    }

    @discardableResult
    func presentNewSession(
        _ request: CodexResearchSessionRequest
    ) throws -> CodexResearchChatModel {
        guard let historyRepository else {
            throw ManagerError.historyUnavailable
        }

        let session = CodexResearchChatModel(
            bundle: request.bundle,
            appID: request.appID,
            appName: request.appName,
            reviewCount: request.reviewCount,
            storefrontCount: request.storefrontCount,
            codexModel: request.codexModel,
            reasoningEffort: request.reasoningEffort,
            initialDraft: request.initialDraft,
            historyRepository: historyRepository
        )
        session.onTurnCompleted = { [weak self] completedSession in
            self?.sessionDidCompleteTurn(completedSession)
        }
        sessions.insert(session, at: 0)
        presentedSession = session
        return session
    }

    func present(_ session: CodexResearchChatModel) {
        guard sessions.contains(where: { $0.id == session.id }) else { return }
        presentedSession = session
    }

    func dismissPresentation() {
        presentedSession = nil
        discardUnsubmittedSessions()
    }

    func discardUnsubmittedSessions() {
        let presentedSessionID = presentedSession?.id
        sessions.removeAll { session in
            !session.hasStarted && session.id != presentedSessionID
        }
    }

    func refreshHistory() {
        guard let historyRepository else {
            historyEntries = []
            historyErrorMessage = ManagerError.historyUnavailable.localizedDescription
            return
        }

        do {
            historyEntries = try historyRepository.load()
            historyErrorMessage = nil
        } catch {
            historyEntries = []
            historyErrorMessage = error.localizedDescription
        }
    }

    func sessionDidCompleteTurn(_ session: CodexResearchChatModel) {
        refreshHistory()
        guard presentedSession?.id != session.id else { return }

        let notice = CodexResearchCompletionNotice(
            id: UUID(),
            sessionID: session.id,
            appName: session.appName
        )
        completionNotice = notice
        noticeDismissalTask?.cancel()
        noticeDismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled, self?.completionNotice?.id == notice.id else { return }
            self?.completionNotice = nil
        }
    }

    func openCompletionNotice() {
        guard
            let completionNotice,
            let session = sessions.first(where: { $0.id == completionNotice.sessionID })
        else {
            self.completionNotice = nil
            return
        }
        noticeDismissalTask?.cancel()
        self.completionNotice = nil
        presentedSession = session
    }

    func dismissCompletionNotice() {
        noticeDismissalTask?.cancel()
        completionNotice = nil
    }
}
