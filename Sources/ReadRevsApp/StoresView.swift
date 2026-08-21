import ReadRevsCore
import SwiftUI

private struct StoreSummaryRow: Identifiable {
    var id: String { store }
    let store: String
    let languages: String
    let keywordCount: Int
    let topPopularity: Int?
    let scannedTerms: Int
    let observedApps: Int
}

struct StoresView: View {
    @EnvironmentObject private var store: LibraryStore
    let projectID: UUID

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView("No Stores", systemImage: "globe")
        } else {
            Table(rows) {
                TableColumn("Store", value: \.store)
                    .width(min: 65, ideal: 80)
                TableColumn("Languages", value: \.languages)
                TableColumn("Keywords") { row in
                    Text(row.keywordCount.formatted()).monospacedDigit()
                }
                TableColumn("Top Popularity") { row in
                    Text(row.topPopularity?.formatted() ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(row.topPopularity == nil ? .tertiary : .primary)
                }
                TableColumn("Scanned Terms") { row in
                    Text(row.scannedTerms.formatted()).monospacedDigit()
                }
                TableColumn("Observed Apps") { row in
                    Text(row.observedApps.formatted()).monospacedDigit()
                }
            }
        }
    }

    private var rows: [StoreSummaryRow] {
        guard let project = store.project(id: projectID) else { return [] }
        return Dictionary(grouping: project.targets, by: \.store).map { storeCode, targets in
            let keywords = project.keywords.filter { $0.store == storeCode }
            let scans = project.rankingScans.filter { $0.store == storeCode }
            let observations = project.rankingObservations.filter { $0.store == storeCode }
            return StoreSummaryRow(
                store: storeCode.uppercased(),
                languages: Array(Set(targets.map { $0.language.uppercased() })).sorted().joined(separator: ", "),
                keywordCount: keywords.count,
                topPopularity: keywords.filter(\.hasPopularityMeasurement).map(\.popularity).max(),
                scannedTerms: scans.count,
                observedApps: Set(observations.map(\.adamID)).count
            )
        }.sorted { $0.store < $1.store }
    }
}
