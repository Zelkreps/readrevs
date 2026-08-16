import Foundation

enum CodexResearchPromptPreferences {
    static let storageKey = "codexResearchAnalysisPrompt"

    static let defaultAnalysisInstructions = """
    Identify evidence-backed strengths, weaknesses, recurring complaints, customer jobs, unmet needs, and product opportunities. Separate observed frequency from interpretation, and segment findings by rating, storefront, and version when useful.

    Return a concise report with an executive summary, opportunity clusters, quick wins, larger strategic bets, and dataset caveats. Use Markdown headings and bullet lists, never Markdown tables. Rank opportunities by likely user impact and implementation effort, ground frequency claims in the data, and do not treat a few vivid reviews as a trend.
    """

    static func prefilledMessage(
        appName: String,
        reviewCount: Int,
        instructions: String
    ) -> String {
        let reviewLabel = reviewCount == 1
            ? "1 synced review"
            : "\(reviewCount.formatted()) synced reviews"
        let introduction = "Analyze all \(reviewLabel) for \(appName)."
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstructions.isEmpty else { return introduction }
        return "\(introduction)\n\n\(trimmedInstructions)"
    }
}
