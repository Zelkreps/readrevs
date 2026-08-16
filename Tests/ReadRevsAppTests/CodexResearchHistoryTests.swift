import Foundation
import Testing
@testable import ReadRevsApp

@Suite("Codex research history")
struct CodexResearchHistoryTests {
    @Test("Persists conversations atomically and updates an existing session")
    func persistsAndUpdatesHistory() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ASOCodexHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = CodexResearchHistoryRepository(rootDirectory: root)
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let initial = sampleEntry(
            id: id,
            appID: 42,
            appName: "Example Flashcards",
            createdAt: createdAt,
            updatedAt: createdAt,
            messages: [
                CodexChatMessage(role: .user, text: "Analyze the reviews."),
                CodexChatMessage(role: .assistant, text: "Initial findings"),
            ]
        )
        try repository.upsert(initial)

        let updated = sampleEntry(
            id: id,
            appID: 42,
            appName: "Example Flashcards",
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
                messages: [CodexChatMessage(role: .assistant, text: "Another result")]
            )
        )

        #expect(try repository.load().count == 2)
        #expect(try repository.load().first?.id == id)
        #expect(try repository.load(appID: 42) == [updated])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "history.json").path))
    }

    @Test("Opens a research conversation as an editable unsent draft")
    @MainActor
    func opensAsEditableDraft() {
        let model = CodexResearchChatModel(
            bundle: CodexResearchBundle(
                directoryURL: URL(fileURLWithPath: "/private/tmp/aso-draft-test"),
                systemInstructions: "Fixed safety instructions"
            ),
            appID: 42,
            appName: "Example Flashcards",
            reviewCount: 5,
            storefrontCount: 4,
            codexModel: CodexModelConfiguration(
                modelID: "gpt-5.6-terra",
                displayName: "GPT-5.6-Terra"
            ),
            reasoningEffort: .medium,
            initialDraft: "Analyze all 5 synced reviews for Example Flashcards.",
            historyRepository: CodexResearchHistoryRepository(
                rootDirectory: URL(fileURLWithPath: "/private/tmp/aso-history-test")
            )
        )

        #expect(model.draft == "Analyze all 5 synced reviews for Example Flashcards.")
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
