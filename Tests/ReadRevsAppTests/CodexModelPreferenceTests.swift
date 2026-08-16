import Foundation
import Testing
@testable import ReadRevsApp

@Suite("Codex model preferences and CLI boundary")
struct CodexModelPreferenceTests {
    @Test("Builds a read-only new-thread invocation for the isolated bundle")
    func buildsSafeNewThreadInvocation() {
        let workspace = URL(fileURLWithPath: "/private/tmp/ReadRevs")

        let arguments = CodexCLICommand.arguments(
            for: .start(workspace: workspace),
            modelID: "gpt-5.6-terra",
            reasoningEffort: .medium
        )

        #expect(arguments == [
            "--sandbox", "read-only",
            "--ask-for-approval", "never",
            "--cd", workspace.path,
            "--model", "gpt-5.6-terra",
            "--config", #"model_reasoning_effort="medium""#,
            "exec",
            "--json",
            "--ignore-user-config",
            "--ignore-rules",
            "--strict-config",
            "--skip-git-repo-check",
            "-",
        ])
        #expect(!arguments.contains("--ephemeral"))
        #expect(!arguments.contains("--dangerously-bypass-approvals-and-sandbox"))
    }

    @Test("Resumes the exact conversation instead of the latest CLI thread")
    func buildsExactResumeInvocation() {
        let arguments = CodexCLICommand.arguments(
            for: .resume(
                workspace: URL(fileURLWithPath: "/private/tmp/research"),
                threadID: "thread-42"
            ),
            modelID: nil,
            reasoningEffort: .high
        )

        #expect(arguments.suffix(2) == ["thread-42", "-"])
        #expect(arguments.contains("resume"))
        #expect(arguments.contains(#"model_reasoning_effort="high""#))
        #expect(!arguments.contains("--last"))
        #expect(!arguments.contains("--model"))
    }

    @Test("Loads visible model capabilities and normalizes stored preferences")
    func resolvesPreferencesFromCatalog() throws {
        let catalog = try CodexModelCatalog.decode(Data(Self.sampleCatalog.utf8))

        #expect(catalog.models.map(\.id) == ["gpt-5.6-sol", "gpt-5.6-terra"])
        #expect(catalog.model(id: "hidden") == nil)

        let supported = CodexResearchPreferences.resolve(
            storedModelID: "gpt-5.6-sol",
            storedReasoningEffort: "high",
            catalog: catalog
        )
        #expect(supported.model.modelID == "gpt-5.6-sol")
        #expect(supported.reasoningEffort == .high)

        let unsupported = CodexResearchPreferences.resolve(
            storedModelID: "gpt-5.6-terra",
            storedReasoningEffort: "ultra",
            catalog: catalog
        )
        #expect(unsupported.reasoningEffort == .medium)
    }

    @Test("Parses conversation JSONL defensively")
    func parsesConversationEvents() {
        #expect(
            CodexCLIEventParser.parse(
                #"{"type":"thread.started","thread_id":"thread-123"}"#
            ) == .threadStarted("thread-123")
        )
        #expect(
            CodexCLIEventParser.parse(
                #"{"type":"item.completed","item":{"type":"agent_message","text":"Findings"}}"#
            ) == .assistantMessage("Findings")
        )
        #expect(
            CodexCLIEventParser.parse(
                #"{"type":"turn.failed","error":{"message":"Authentication required"}}"#
            ) == .failure("Authentication required")
        )
        #expect(CodexCLIEventParser.parse("unstructured warning") == .ignored)
        #expect(CodexCLIEventParser.parse(#"{"type":"future.event"}"#) == .ignored)
    }

    @Test("Keeps the original reasoning choices and balanced fallback")
    func resolvesReasoningPreferences() {
        #expect(CodexReasoningEffort.allCases.map(\.rawValue) == [
            "low", "medium", "high", "xhigh", "max", "ultra",
        ])
        #expect(CodexReasoningEffort.resolve(storedValue: nil) == .medium)
        #expect(CodexReasoningEffort.resolve(storedValue: "unsupported") == .medium)
    }

    private static let sampleCatalog = #"""
    {
      "models": [
        {
          "slug": "gpt-5.6-terra",
          "display_name": "GPT-5.6-Terra",
          "description": "Balanced model.",
          "default_reasoning_level": "medium",
          "supported_reasoning_levels": [
            { "effort": "low" },
            { "effort": "medium" }
          ],
          "visibility": "list",
          "priority": 2
        },
        {
          "slug": "hidden",
          "display_name": "Hidden",
          "description": "Hidden model.",
          "default_reasoning_level": "medium",
          "supported_reasoning_levels": [{ "effort": "medium" }],
          "visibility": "hidden",
          "priority": 0
        },
        {
          "slug": "gpt-5.6-sol",
          "display_name": "GPT-5.6-Sol",
          "description": "Deep model.",
          "default_reasoning_level": "low",
          "supported_reasoning_levels": [
            { "effort": "low" },
            { "effort": "medium" },
            { "effort": "high" }
          ],
          "visibility": "list",
          "priority": 1
        }
      ]
    }
    """#
}
