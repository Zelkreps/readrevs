import Foundation
import Testing
@testable import ReadRevs

@Suite("Embedded Codex CLI integration")
struct CodexCLIIntegrationTests {
    @Test("Builds a safe new-thread invocation for an isolated workspace")
    func buildsNewThreadInvocation() {
        let workspace = URL(fileURLWithPath: "/private/tmp/ReadRevs Research")

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

    @Test("Resumes the exact thread instead of the latest CLI session")
    func buildsResumeInvocation() {
        let workspace = URL(fileURLWithPath: "/private/tmp/research")

        let arguments = CodexCLICommand.arguments(
            for: .resume(workspace: workspace, threadID: "019f8bfe-df38-79f2-9907-53911c31bfb7"),
            modelID: "gpt-5.6-terra",
            reasoningEffort: .max
        )

        #expect(arguments.suffix(2) == [
            "019f8bfe-df38-79f2-9907-53911c31bfb7",
            "-",
        ])
        #expect(arguments.contains("resume"))
        #expect(arguments.contains(#"model_reasoning_effort="max""#))
        #expect(!arguments.contains("--last"))
    }

    @Test("Provides persistent reasoning choices with a balanced default")
    func resolvesReasoningPreferences() {
        #expect(CodexReasoningEffort.allCases.map(\.rawValue) == [
            "low", "medium", "high", "xhigh", "max", "ultra",
        ])
        #expect(CodexReasoningEffort.resolve(storedValue: nil) == .medium)
        #expect(CodexReasoningEffort.resolve(storedValue: "max") == .max)
        #expect(CodexReasoningEffort.resolve(storedValue: "unsupported") == .medium)
    }

    @Test("Loads exact Codex model names and capabilities from the local catalog")
    func decodesCodexModelCatalog() throws {
        let catalog = try CodexModelCatalog.decode(Data(Self.sampleModelCatalog.utf8))

        #expect(catalog.models.map(\.id) == ["gpt-5.6-sol", "gpt-5.6-terra"])
        #expect(catalog.models.map(\.displayName) == ["GPT-5.6-Sol", "GPT-5.6-Terra"])
        #expect(catalog.model(id: "hidden-model") == nil)
        #expect(catalog.model(id: "gpt-5.6-terra")?.supportedReasoningEfforts == [.low, .medium])
        #expect(catalog.model(id: "gpt-5.6-terra")?.defaultReasoningEffort == .medium)
    }

    @Test("Resolves persisted model and supported reasoning without marketing aliases")
    func resolvesCodexResearchPreferences() throws {
        let catalog = try CodexModelCatalog.decode(Data(Self.sampleModelCatalog.utf8))

        let defaults = CodexResearchPreferences.resolve(
            storedModelID: nil,
            storedReasoningEffort: nil,
            catalog: catalog
        )
        #expect(defaults.model == CodexModelConfiguration(
            modelID: "gpt-5.6-terra",
            displayName: "GPT-5.6-Terra"
        ))
        #expect(defaults.reasoningEffort == .medium)

        let persisted = CodexResearchPreferences.resolve(
            storedModelID: "gpt-5.6-sol",
            storedReasoningEffort: "high",
            catalog: catalog
        )
        #expect(persisted.model.displayName == "GPT-5.6-Sol")
        #expect(persisted.reasoningEffort == .high)

        let unsupported = CodexResearchPreferences.resolve(
            storedModelID: "gpt-5.6-terra",
            storedReasoningEffort: "ultra",
            catalog: catalog
        )
        #expect(unsupported.reasoningEffort == .medium)
    }

    @Test("Parses thread IDs and assistant messages from JSONL")
    func parsesConversationEvents() {
        #expect(
            CodexCLIEventParser.parse(
                #"{"type":"thread.started","thread_id":"thread-123"}"#
            ) == .threadStarted("thread-123")
        )
        #expect(
            CodexCLIEventParser.parse(
                #"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Research result"}}"#
            ) == .assistantMessage("Research result")
        )
        #expect(
            CodexCLIEventParser.parse(
                #"{"type":"item.started","item":{"id":"item_1","type":"command_execution"}}"#
            ) == .activity("command_execution")
        )
    }

    @Test("Surfaces failures and ignores unknown or non-JSON output")
    func parsesFailuresDefensively() {
        #expect(
            CodexCLIEventParser.parse(
                #"{"type":"turn.failed","error":{"message":"Authentication required"}}"#
            ) == .failure("Authentication required")
        )
        #expect(
            CodexCLIEventParser.parse(
                #"{"type":"error","message":"CLI unavailable"}"#
            ) == .failure("CLI unavailable")
        )
        #expect(CodexCLIEventParser.parse("warning written by the CLI") == .ignored)
        #expect(CodexCLIEventParser.parse(#"{"type":"future.event","value":42}"#) == .ignored)
    }

    private static let sampleModelCatalog = #"""
    {
      "models": [
        {
          "slug": "gpt-5.6-terra",
          "display_name": "GPT-5.6-Terra",
          "description": "Balanced agentic coding model for everyday work.",
          "default_reasoning_level": "medium",
          "supported_reasoning_levels": [
            { "effort": "low", "description": "Fast responses with lighter reasoning" },
            { "effort": "medium", "description": "Balances speed and reasoning depth" }
          ],
          "visibility": "list",
          "priority": 2
        },
        {
          "slug": "hidden-model",
          "display_name": "Hidden Model",
          "description": "Not shown by Codex.",
          "default_reasoning_level": "medium",
          "supported_reasoning_levels": [
            { "effort": "medium", "description": "Default" }
          ],
          "visibility": "hidden",
          "priority": 0
        },
        {
          "slug": "gpt-5.6-sol",
          "display_name": "GPT-5.6-Sol",
          "description": "Latest frontier agentic coding model.",
          "default_reasoning_level": "low",
          "supported_reasoning_levels": [
            { "effort": "low", "description": "Fast responses with lighter reasoning" },
            { "effort": "medium", "description": "Balanced" },
            { "effort": "high", "description": "Greater reasoning depth" }
          ],
          "visibility": "list",
          "priority": 1
        }
      ]
    }
    """#
}
