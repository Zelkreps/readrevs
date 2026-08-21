import ReadRevsCore
import SwiftUI
import UniformTypeIdentifiers

struct KeywordsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var isImporting = false

    let projectID: UUID

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Favorites", isOn: $favoritesOnly)
                    .toggleStyle(.checkbox)

                Spacer()

                Text("\(filteredKeywords.count) keywords")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Import CSV", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
                .help("Import ReadRevs CSV")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            Divider()

            if filteredKeywords.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                Table(filteredKeywords) {
                    TableColumn("") { keyword in
                        Button {
                            store.toggleFavorite(keywordID: keyword.id, projectID: projectID)
                        } label: {
                            Image(systemName: keyword.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(keyword.isFavorite ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(keyword.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                        .accessibilityLabel(keyword.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    }
                    .width(28)

                    TableColumn("Keyword", value: \.keyword)
                        .width(min: 170, ideal: 260)
                    TableColumn("Store", value: \.store)
                        .width(min: 55, ideal: 65)
                    TableColumn("Genre", value: \.genre)
                        .width(min: 100, ideal: 140)
                    TableColumn("Popularity") { keyword in
                        Text(keyword.hasPopularityMeasurement ? keyword.popularity.formatted() : "—")
                            .monospacedDigit()
                            .foregroundStyle(keyword.hasPopularityMeasurement ? .primary : .tertiary)
                    }
                    .width(min: 75, ideal: 90)
                    TableColumn("Suggestion Score") { keyword in
                        AppleAdsSuggestionScoreCell(value: keyword.effectiveSuggestionScore)
                    }
                    .width(min: 95, ideal: 110)
                    TableColumn("Opportunity") { keyword in
                        Text(keyword.opportunityScore, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                    }
                    .width(min: 80, ideal: 95)
                    TableColumn("Source") { keyword in
                        Text(sourceLabel(keyword.source))
                    }
                    .width(min: 80, ideal: 95)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Filter Keywords")
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                Task { await store.importKeywords(data, into: projectID) }
            } catch {
                store.showError(title: "CSV Could Not Be Imported", error: error)
            }
        }
    }

    private var filteredKeywords: [KeywordRecord] {
        guard let project = store.project(id: projectID) else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return project.keywords.filter { keyword in
            (!favoritesOnly || keyword.isFavorite)
                && (query.isEmpty
                    || keyword.keyword.localizedCaseInsensitiveContains(query)
                    || keyword.genre.localizedCaseInsensitiveContains(query)
                    || keyword.store.localizedCaseInsensitiveContains(query))
        }
    }

    private func sourceLabel(_ source: KeywordSource) -> String {
        switch source {
        case .legacyPopularity: "Legacy"
        case .csvImport: "CSV"
        case .appleAds: "Apple Ads"
        case .appleSearchHints: "Apple Suggestions"
        case .manual: "Manual"
        }
    }
}
