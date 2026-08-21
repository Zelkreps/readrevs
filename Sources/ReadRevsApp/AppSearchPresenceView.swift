import ReadRevsCore
import SwiftUI

struct AppSearchPresenceView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject var controller: AppSearchPresenceController

    let app: TrackedApp

    @State private var query = ""
    @State private var sortOrder = [
        KeyPathComparator(\SearchPresenceRow.positionSortValue, order: .forward),
        KeyPathComparator(\SearchPresenceRow.keyword),
    ]

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            if let summary {
                summaryStrip(summary)
                Divider()
            }

            if rows.isEmpty {
                emptyState
            } else {
                resultsTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var controls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text(reviewFlagEmoji(app.primaryStore))
                    Text(reviewStoreTitle(app.primaryStore))
                        .lineLimit(1)
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter Search Terms", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear Filter")
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: 220, height: 28)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator.opacity(0.75))
                }

                Spacer(minLength: 12)

                if controller.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let status = controller.statusText {
                    Image(systemName: controller.failureCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(controller.failureCount == 0 ? .green : .orange)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Button {
                    controller.searchMore(app: app, store: store)
                } label: {
                    Label("Search More", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(controller.isRunning || store.isReadOnly || rows.isEmpty)
                .help("Expand from the strongest discovered terms and add another candidate batch")

                Button {
                    controller.refresh(app: app, store: store, force: true)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(controller.isRunning || store.isReadOnly)
                .help("Refresh candidate terms, popularity, difficulty, and observed positions")
            }

            Text("Suggestion Score is a discovery signal from Apple Ads; Popularity is available only from the weekly storefront-and-genre report. Position is observed iTunes Search API result order.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func summaryStrip(_ summary: SearchPresenceSummary) -> some View {
        HStack(spacing: 0) {
            SearchPresenceStat(label: "Candidates", value: summary.keywordCount.formatted())
            SearchPresenceStat(
                label: "Checked",
                value: "\(summary.checkedKeywordCount)/\(summary.keywordCount)"
            )
            SearchPresenceStat(label: "Ranked", value: summary.rankedKeywordCount.formatted())
            SearchPresenceStat(label: "Not Found", value: summary.notRankedKeywordCount.formatted())
            SearchPresenceStat(
                label: "Best Position",
                value: summary.bestPosition.map { "#\($0)" } ?? "—"
            )
            SearchPresenceStat(
                label: "Average",
                value: summary.averagePosition.map {
                    "#" + $0.formatted(.number.precision(.fractionLength(1)))
                } ?? "—"
            )

            Spacer(minLength: 8)

            if let lastCheckedAt = summary.lastCheckedAt {
                Text(lastCheckedAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 14)
            }
        }
        .frame(height: 48)
        .background(Color.primary.opacity(0.025))
    }

    private var resultsTable: some View {
        Table(filteredRows, sortOrder: $sortOrder) {
            TableColumn("Keyword", value: \.keyword) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.keyword)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(sourceLabel(row.source))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .width(min: 150, ideal: 205)

            TableColumn("Suggestion Score", value: \.suggestionScoreSortValue) { row in
                AppleAdsSuggestionScoreCell(value: row.suggestionScore)
            }
            .width(min: 96, ideal: 112)

            TableColumn("Popularity", value: \.popularitySortValue) { row in
                SearchPresenceMetricBar(
                    value: row.popularity,
                    kind: .popularity,
                    unavailableHelp: "Apple Ads returned no exact popularity for this term."
                )
            }
            .width(min: 92, ideal: 110)

            TableColumn("Difficulty", value: \.difficultySortValue) { row in
                SearchPresenceMetricBar(
                    value: row.difficulty,
                    kind: .difficulty,
                    unavailableHelp: "Difficulty requires completed iTunes search results."
                )
            }
            .width(min: 92, ideal: 110)

            TableColumn("Position", value: \.positionSortValue) { row in
                Text(row.focusAppPosition.map { "# \($0)" } ?? "# —")
                    .monospacedDigit()
                    .foregroundStyle(row.focusAppPosition == nil ? .secondary : .primary)
                    .help(positionHelp(for: row))
            }
            .width(min: 68, ideal: 76)

            TableColumn("Results", value: \.resultCountSortValue) { row in
                Text(row.resultCount?.formatted() ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(row.resultCount == nil ? .secondary : .primary)
            }
            .width(min: 60, ideal: 68)

            TableColumn("Apps in Ranking") { row in
                SearchPresenceAppsCell(apps: row.topApps)
            }
            .width(min: 124, ideal: 160)

            TableColumn("Checked", value: \.checkedSortValue) { row in
                if let checkedAt = row.checkedAt {
                    Text(checkedAt, format: .dateTime.day().month(.abbreviated))
                } else {
                    Text("Pending")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 76, ideal: 90)
        }
        .alternatingRowBackgrounds(.enabled)
        .onChange(of: sortOrder) { _, newValue in
            guard !newValue.isEmpty else { return }
        }
    }

    private var emptyState: some View {
        Group {
            if controller.isRunning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(progressText)
                        .font(.headline)
                    Text(controller.statusText ?? "Preparing search research...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView {
                    Label("No Search Presence Data", systemImage: "text.magnifyingglass")
                } description: {
                    Text("No candidate terms have been checked for this storefront yet.")
                } actions: {
                    Button("Start Research") {
                        controller.refresh(app: app, store: store, force: true)
                    }
                    .disabled(store.isReadOnly)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var rows: [SearchPresenceRow] {
        store.searchPresenceRows(for: app.adamID, store: app.primaryStore)
    }

    private var filteredRows: [SearchPresenceRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = trimmed.isEmpty ? rows : rows.filter {
            $0.keyword.localizedCaseInsensitiveContains(trimmed)
                || sourceLabel($0.source).localizedCaseInsensitiveContains(trimmed)
        }
        return matching.sorted(using: sortOrder)
    }

    private var summary: SearchPresenceSummary? {
        store.searchPresenceSummary(for: app.adamID, store: app.primaryStore)
    }

    private var progressText: String {
        guard controller.total > 0 else { return "Preparing Search Presence" }
        return "\(controller.completed)/\(controller.total)"
    }

    private func sourceLabel(_ source: KeywordSource?) -> String {
        switch source {
        case .appleSearchHints: "Apple Suggestion"
        case .legacyPopularity: "Legacy Popularity"
        case .csvImport: "CSV Import"
        case .appleAds: "Apple Ads"
        case .manual, nil: "App Metadata"
        }
    }

    private func positionHelp(for row: SearchPresenceRow) -> String {
        if let position = row.focusAppPosition {
            return "Observed at iTunes Search API result order \(position)."
        }
        if let resultCount = row.resultCount {
            return "The app was not found in the \(resultCount) returned iTunes Search API results."
        }
        return "This candidate has not been checked yet."
    }
}

private extension SearchPresenceRow {
    var suggestionScoreSortValue: Int { suggestionScore ?? -1 }
}

private struct SearchPresenceStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minWidth: 74, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

private enum SearchPresenceMetricKind {
    case popularity
    case difficulty
}

private struct SearchPresenceMetricBar: View {
    let value: Int?
    let kind: SearchPresenceMetricKind
    let unavailableHelp: String

    var body: some View {
        HStack(spacing: 7) {
            Text(value?.formatted() ?? "—")
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(value == nil ? .secondary : .primary)
                .frame(width: 30, alignment: .trailing)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    if let value {
                        Capsule()
                            .fill(metricColor(value))
                            .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 100)) / 100)
                    }
                }
            }
            .frame(width: 64, height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(value.map { "\($0) out of 100" } ?? unavailableHelp)
    }

    private func metricColor(_ value: Int) -> Color {
        switch kind {
        case .popularity:
            if value >= 70 { return .green }
            if value >= 45 { return .yellow }
            return .red
        case .difficulty:
            if value < 40 { return .green }
            if value < 70 { return .yellow }
            return .red
        }
    }
}

private struct SearchPresenceAppsCell: View {
    let apps: [RankingObservation]

    var body: some View {
        if apps.isEmpty {
            Text("—")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 3) {
                ForEach(Array(apps.prefix(6))) { app in
                    AsyncImage(url: app.artworkURL) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().scaledToFill()
                        default:
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                                .overlay {
                                    Text(app.position.formatted())
                                        .font(.caption2)
                                        .monospacedDigit()
                                }
                        }
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .help("#\(app.position) · \(app.appName)")
                }

                if apps.count > 6 {
                    Text("+\(apps.count - 6)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private extension SearchPresenceRow {
    var popularitySortValue: Int { popularity ?? Int.max }
    var difficultySortValue: Int { difficulty ?? Int.max }
    var positionSortValue: Int { focusAppPosition ?? Int.max }
    var resultCountSortValue: Int { resultCount ?? Int.max }
    var checkedSortValue: Date { checkedAt ?? .distantFuture }
}
