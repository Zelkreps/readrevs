import Foundation
import Testing
@testable import ReadRevs

@Suite("Codex research history")
struct CodexResearchHistoryTests {
    @Test("Persists completed conversations and updates an existing analysis")
    func persistsAndUpdatesHistory() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ReadRevsHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = CodexResearchHistoryRepository(rootDirectory: root)
        let identifier = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let initial = sampleEntry(
            id: identifier,
            appID: 42,
            appName: "Quizpad",
            createdAt: createdAt,
            updatedAt: createdAt,
            messages: [
                CodexChatMessage(role: .user, text: "Analyze the reviews."),
                CodexChatMessage(role: .assistant, text: "Initial findings"),
            ]
        )
        try repository.upsert(initial)

        let updated = sampleEntry(
            id: identifier,
            appID: 42,
            appName: "Quizpad",
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(120),
            messages: initial.messages + [
                CodexChatMessage(role: .user, text: "What is the easiest win?"),
                CodexChatMessage(role: .assistant, text: "Improve onboarding copy."),
            ]
        )
        try repository.upsert(updated)
        try repository.upsert(
            sampleEntry(
                id: UUID(),
                appID: 84,
                appName: "Another App",
                createdAt: createdAt.addingTimeInterval(60),
                updatedAt: createdAt.addingTimeInterval(60),
                messages: [
                    CodexChatMessage(role: .user, text: "Analyze."),
                    CodexChatMessage(role: .assistant, text: "Another result"),
                ]
            )
        )

        let reloaded = CodexResearchHistoryRepository(rootDirectory: root)
        let all = try reloaded.load()
        #expect(all.count == 2)
        #expect(all.first?.id == identifier)
        #expect(all.first?.messages.last?.text == "Improve onboarding copy.")
        #expect(try reloaded.load(appID: 42) == [updated])
    }

    @Test("Opening research creates a draft without starting a conversation")
    @MainActor
    func opensAsEditableDraft() {
        let bundle = CodexResearchBundle(
            directoryURL: URL(fileURLWithPath: "/private/tmp/readrevs-draft-test"),
            systemInstructions: "Fixed safety instructions"
        )
        let model = CodexResearchChatModel(
            bundle: bundle,
            appID: 42,
            appName: "Quizpad",
            reviewCount: 5,
            storefrontCount: 4,
            codexModel: CodexModelConfiguration(modelID: "gpt-5.6-terra", displayName: "GPT-5.6-Terra"),
            reasoningEffort: .medium,
            initialDraft: "Analyze all 5 synced reviews for Quizpad.",
            historyRepository: CodexResearchHistoryRepository(
                rootDirectory: URL(fileURLWithPath: "/private/tmp/readrevs-history-test")
            )
        )

        #expect(model.draft == "Analyze all 5 synced reviews for Quizpad.")
        #expect(model.messages.isEmpty)
        #expect(!model.isRunning)
        #expect(model.canSendMessage)
        #expect(model.primaryActionTitle == "Analyze")
    }

    private func sampleEntry(
        id: UUID,
        appID: Int64,
        appName: String,
        createdAt: Date,
        updatedAt: Date,
        messages: [CodexChatMessage]
    ) -> CodexResearchHistoryEntry {
        CodexResearchHistoryEntry(
            id: id,
            appID: appID,
            appName: appName,
            reviewCount: 5,
            storefrontCount: 4,
            createdAt: createdAt,
            updatedAt: updatedAt,
            codexModel: CodexModelConfiguration(
                modelID: "gpt-5.6-terra",
                displayName: "GPT-5.6-Terra"
            ),
            reasoningEffort: .medium,
            messages: messages
        )
    }
}
