import ReadRevsCore
import SwiftUI

@MainActor
final class RankingScanController: ObservableObject {
    @Published var isRunning = false
    @Published var completed = 0
    @Published var total = 0
    @Published var failureCount = 0
    @Published var statusText: String?

    private var task: Task<Void, Never>?
    private let client = ITunesAppStoreClient()
    private var runID = UUID()
    private var activeProjectID: UUID?
    private var queuedCandidates = PrioritizedUniqueQueue<KeywordRecord, String>(key: rankingCandidateKey)
    private var activeCandidateKey: String?
    private var retryRequestedCandidates: [String: KeywordRecord] = [:]

    func start(
        project: ResearchProject,
        scanLimit: Int,
        storeFilter: String? = nil,
        includeSeeds: Bool = true,
        store: LibraryStore
    ) {
        let candidates = scanCandidates(
            project: project,
            storeFilter: storeFilter,
            includeSeeds: includeSeeds,
            limit: scanLimit
        )
        start(project: project, candidates: candidates, prioritize: false, store: store)
    }

    func start(
        project: ResearchProject,
        keywords: [String],
        storeCode: String,
        store: LibraryStore,
        prioritize: Bool = true
    ) {
        let normalizedStore = storeCode.lowercased()
        let language = project.targets.first(where: { $0.store == normalizedStore })?.language ?? "en"
        var seen: Set<String> = []
        let candidates = keywords.compactMap { value -> KeywordRecord? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ).lowercased()
            guard !trimmed.isEmpty, seen.insert(normalized).inserted else { return nil }
            return KeywordRecord(
                keyword: trimmed,
                language: language,
                store: normalizedStore,
                genre: "Manual",
                popularity: 0,
                source: .manual,
                isTracked: true
            )
        }
        start(project: project, candidates: candidates, prioritize: prioritize, store: store)
    }

    private func start(
        project: ResearchProject,
        candidates: [KeywordRecord],
        prioritize: Bool,
        store: LibraryStore
    ) {
        guard !candidates.isEmpty else { return }
        if isRunning, activeProjectID == project.id {
            enqueue(candidates, prioritize: prioritize)
            return
        }

        let currentRunID = begin()
        activeProjectID = project.id
        enqueue(candidates, prioritize: prioritize)

        task = Task { [weak self] in
            guard let self else { return }
            defer { finish(runID: currentRunID) }

            while let keyword = queuedCandidates.popFirst() {
                guard !Task.isCancelled, runID == currentRunID else { return }
                let currentCandidateKey = rankingCandidateKey(keyword)
                activeCandidateKey = currentCandidateKey
                let checkedAt = Date()
                var didSucceed = false
                do {
                    let results = try await client.search(term: keyword.keyword, country: keyword.store, limit: 100)
                    guard !Task.isCancelled, runID == currentRunID else { return }
                    let observations = RankingIndex.observations(
                        projectID: project.id,
                        keyword: keyword.keyword,
                        store: keyword.store,
                        results: results,
                        checkedAt: checkedAt
                    )
                    store.mergeRankingData(
                        observations: observations,
                        scan: RankingScan(
                            projectID: project.id,
                            keyword: keyword.keyword,
                            store: keyword.store,
                            checkedAt: checkedAt,
                            resultCount: results.count
                        ),
                        into: project.id
                    )
                    didSucceed = true
                } catch is CancellationError {
                    return
                } catch {
                    guard runID == currentRunID else { return }
                    failureCount += 1
                    statusText = error.localizedDescription
                }
                completed += 1
                activeCandidateKey = nil

                if let retry = retryRequestedCandidates.removeValue(forKey: currentCandidateKey), !didSucceed {
                    total += queuedCandidates.enqueue([retry], prioritize: true)
                }
            }

            guard runID == currentRunID else { return }
            if failureCount > 0 {
                statusText = "Completed with \(failureCount) failed search\(failureCount == 1 ? "" : "es")."
            } else {
                statusText = "Difficulty and ranking updated."
            }
        }
    }

    func cancel() {
        runID = UUID()
        task?.cancel()
        task = nil
        isRunning = false
        activeProjectID = nil
        queuedCandidates.removeAll()
        activeCandidateKey = nil
        retryRequestedCandidates.removeAll()
    }

    private func begin() -> UUID {
        cancel()
        let identifier = UUID()
        runID = identifier
        isRunning = true
        completed = 0
        total = 0
        failureCount = 0
        statusText = nil
        return identifier
    }

    private func finish(runID finishedRunID: UUID) {
        guard runID == finishedRunID else { return }
        isRunning = false
        task = nil
        activeProjectID = nil
        queuedCandidates.removeAll()
        activeCandidateKey = nil
        retryRequestedCandidates.removeAll()
    }

    private func enqueue(_ candidates: [KeywordRecord], prioritize: Bool) {
        var queueable: [KeywordRecord] = []
        for candidate in candidates {
            let key = rankingCandidateKey(candidate)
            if key == activeCandidateKey {
                if prioritize { retryRequestedCandidates[key] = candidate }
            } else {
                queueable.append(candidate)
            }
        }
        total += queuedCandidates.enqueue(queueable, prioritize: prioritize)
    }

    private func scanCandidates(
        project: ResearchProject,
        storeFilter: String?,
        includeSeeds: Bool,
        limit: Int
    ) -> [KeywordRecord] {
        let tracked = project.keywords.filter { record in
            guard record.isActivelyTracked else { return false }
            guard let storeFilter else { return true }
            return record.store.caseInsensitiveCompare(storeFilter) == .orderedSame
        }
        let targetStores = project.targets.filter { target in
            guard let storeFilter else { return true }
            return target.store.caseInsensitiveCompare(storeFilter) == .orderedSame
        }
        let seeds = includeSeeds ? targetStores.flatMap { target in
            project.seedKeywords.map { seed in
                KeywordRecord(
                    keyword: seed,
                    language: target.language,
                    store: target.store,
                    genre: "Seed",
                    popularity: 0,
                    source: .manual,
                    isTracked: true
                )
            }
        } : []
        let sorted = (tracked + seeds).sorted { lhs, rhs in
            let lhsIsSeed = lhs.genre == "Seed"
            let rhsIsSeed = rhs.genre == "Seed"
            if lhsIsSeed != rhsIsSeed { return lhsIsSeed }
            if lhs.opportunityScore != rhs.opportunityScore { return lhs.opportunityScore > rhs.opportunityScore }
            let lhsExact = lhs.hasPopularityMeasurement ? lhs.popularity : -1
            let rhsExact = rhs.hasPopularityMeasurement ? rhs.popularity : -1
            if lhsExact != rhsExact { return lhsExact > rhsExact }
            if lhs.effectiveSuggestionScore != rhs.effectiveSuggestionScore {
                return (lhs.effectiveSuggestionScore ?? -1)
                    > (rhs.effectiveSuggestionScore ?? -1)
            }
            return lhs.keyword < rhs.keyword
        }

        var seen: Set<String> = []
        return sorted.filter { record in
            seen.insert("\(record.keyword.lowercased())|\(record.store.lowercased())").inserted
        }.prefix(limit).map { $0 }
    }
}

private func rankingCandidateKey(_ record: KeywordRecord) -> String {
    let keyword = record.keyword.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: .current
    ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return "\(keyword)|\(record.store.lowercased())"
}

struct RankingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var controller = RankingScanController()
    @State private var scanLimit = 10

    let projectID: UUID

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 18)
                .padding(.vertical, 10)

            Divider()

            if summaries.isEmpty {
                ContentUnavailableView("No Observed Apps", systemImage: "list.number")
            } else {
                Table(summaries) {
                    TableColumn("") { summary in
                        if store.app(adamID: summary.adamID) == nil {
                            Button {
                                store.addCompetitor(summary, store: summary.store)
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Track as Competitor")
                            .accessibilityLabel("Track \(summary.name) as Competitor")
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Already Tracked")
                        }
                    }
                    .width(28)

                    TableColumn("App", value: \.name)
                        .width(min: 170, ideal: 250)
                    TableColumn("Genre", value: \.primaryGenre)
                        .width(min: 90, ideal: 130)
                    TableColumn("Store") { summary in
                        Text(summary.store.uppercased())
                    }
                    .width(min: 52, ideal: 62)
                    TableColumn("Keywords") { summary in
                        Text(summary.keywordCount.formatted())
                            .monospacedDigit()
                    }
                    .width(min: 65, ideal: 75)
                    TableColumn("Best API Order") { summary in
                        Text(summary.bestPosition.formatted())
                            .monospacedDigit()
                    }
                    .width(min: 105, ideal: 120)
                    TableColumn("Average") { summary in
                        Text(summary.averagePosition, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                    }
                    .width(min: 70, ideal: 80)
                    TableColumn("Observed For") { summary in
                        Text(summary.keywords.joined(separator: ", "))
                            .lineLimit(1)
                            .help(summary.keywords.joined(separator: ", "))
                    }
                    .width(min: 180, ideal: 300)
                }
            }
        }
        .onDisappear { controller.cancel() }
    }

    private var controls: some View {
        VStack(spacing: 9) {
            HStack {
                Stepper("Scan \(scanLimit) keywords", value: $scanLimit, in: 1...20)
                    .frame(width: 175, alignment: .leading)

                Text("iTunes Search API response order, not guaranteed organic rank")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if controller.isRunning {
                    Button("Cancel", systemImage: "xmark.circle") {
                        controller.cancel()
                    }
                } else {
                    Button("Update Search Presence", systemImage: "magnifyingglass") {
                        guard let project = store.project(id: projectID) else { return }
                        controller.start(project: project, scanLimit: scanLimit, store: store)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasScanCandidates || store.isReadOnly)
                }
            }

            if controller.isRunning {
                ProgressView(value: Double(controller.completed), total: Double(max(controller.total, 1))) {
                    Text("\(controller.completed) of \(controller.total) searches")
                }
            } else if let statusText = controller.statusText {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(controller.failureCount > 0 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var summaries: [AppRankingSummary] {
        guard let project = store.project(id: projectID) else { return [] }
        return RankingIndex.summaries(from: project.rankingObservations)
    }

    private var hasScanCandidates: Bool {
        guard let project = store.project(id: projectID) else { return false }
        return project.keywords.contains(where: \.isActivelyTracked) || !project.seedKeywords.isEmpty
    }
}
