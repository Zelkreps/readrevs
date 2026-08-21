import SwiftUI

struct AppleAdsSuggestionScoreCell: View {
    let value: Int?

    var body: some View {
        Text(value?.formatted() ?? "—")
            .monospacedDigit()
            .foregroundStyle(value == nil ? .tertiary : .secondary)
            .help(helpText)
            .accessibilityLabel(accessibilityText)
    }

    private var helpText: String {
        value.map {
            "Apple Ads keyword suggestion score \($0). This discovery signal is not storefront popularity."
        } ?? "No Apple Ads keyword suggestion score is available."
    }

    private var accessibilityText: String {
        value.map {
            "Suggestion score \($0). Not storefront popularity."
        } ?? "Suggestion score unavailable"
    }
}
