import ReadRevsCore
import SwiftUI

struct ReviewDashboardView: View {
    @Environment(CodexResearchSessionManager.self) private var researchManager
    @ObservedObject var model: ReviewDashboardController
    @State private var exportDocument: ReviewExportDocument?
    @State private var exportFormat: ReviewExportFormat = .json
    @State private var exportFilename = "reviews.json"
    @State private var isExporting = false
    @State private var operationErrorMessage: String?
    @AppStorage(CodexResearchPreferences.modelIDStorageKey)
    private var codexModelID = CodexResearchPreferences.defaultModelID
    @AppStorage(CodexReasoningEffort.storageKey)
    private var codexReasoningEffort = CodexReasoningEffort.defaultValue.rawValue
    @AppStorage(CodexResearchPromptPreferences.storageKey)
    private var codexAnalysisPrompt = CodexResearchPromptPreferences.defaultAnalysisInstructions

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                metrics
                ReviewFilterBar(model: model)
                ReviewSyncStatus(model: model, onExport: beginExport)

                HStack(alignment: .firstTextBaseline) {
                    Text("Reviews")
                        .font(.title2.weight(.semibold))
                    Text("\(model.filteredReviews.count) shown · \(model.reviews.count) synced")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()

                    Button(action: beginCodexResearch) {
                        Label("Analyze in Codex", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.reviews.isEmpty || model.isRefreshing)
                    .help("Analyze every synced review in a read-only Codex workspace")
                }

                reviewContent
            }
            .padding(20)
            .frame(maxWidth: 1_480, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.secondary.opacity(0.025))
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: exportFormat.contentType,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result {
                operationErrorMessage = error.localizedDescription
            }
        }
        .alert(
            "ReadRevs",
            isPresented: Binding(
                get: { operationErrorMessage != nil },
                set: { if !$0 { operationErrorMessage = nil } }
            )
        ) {
            Button("OK") { operationErrorMessage = nil }
        } message: {
            Text(operationErrorMessage ?? "The operation could not be completed.")
        }
    }

    private func beginExport(_ format: ReviewExportFormat) {
        guard let app = model.metadata else { return }
        do {
            let data = try ReviewExportService.data(
                format: format,
                app: app,
                reviews: model.reviews,
                completedStorefronts: model.completedStorefronts,
                failures: model.failures
            )
            exportFormat = format
            exportFilename = "\(safeFilename(app.name))-reviews.\(format.filenameExtension)"
            exportDocument = ReviewExportDocument(data: data)
            isExporting = true
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func beginCodexResearch() {
        guard let app = model.metadata else { return }
        do {
            let bundle = try CodexResearchBundleService.live().prepare(
                app: app,
                reviews: model.reviews,
                completedStorefronts: model.completedStorefronts,
                failures: model.failures
            )
            let configuration = CodexResearchPreferences.resolve(
                storedModelID: codexModelID,
                storedReasoningEffort: codexReasoningEffort
            )
            try researchManager.presentNewSession(
                CodexResearchSessionRequest(
                    bundle: bundle,
                    appID: app.adamID,
                    appName: app.name,
                    reviewCount: model.reviews.count,
                    storefrontCount: model.collection.storefrontCount,
                    codexModel: configuration.model,
                    reasoningEffort: configuration.reasoningEffort,
                    initialDraft: CodexResearchPromptPreferences.prefilledMessage(
                        appName: app.name,
                        reviewCount: model.reviews.count,
                        instructions: codexAnalysisPrompt
                    )
                )
            )
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        return result.isEmpty ? "app" : result
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: 14) {
            RatingDistributionCard(collection: model.collection)
                .frame(maxWidth: .infinity)
            CoverageSummaryCard(metadata: model.metadata, collection: model.collection)
                .frame(minWidth: 280, idealWidth: 310, maxWidth: 330)
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        if model.isRefreshing, model.reviews.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Checking all \(model.totalStorefrontCount) storefronts…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if let errorMessage = model.errorMessage, model.reviews.isEmpty {
            ContentUnavailableView {
                Label("Reviews Unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else if model.filteredReviews.isEmpty {
            ContentUnavailableView {
                Label(
                    model.isFiltered ? "No Matching Reviews" : "No Written Reviews Found",
                    systemImage: "text.magnifyingglass"
                )
            } description: {
                Text(
                    model.isFiltered
                        ? "Try clearing one or more filters."
                        : "Apple returned no recent written reviews for the checked storefronts."
                )
            } actions: {
                if model.isFiltered {
                    Button("Clear Filters", action: model.clearFilters)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            ForEach(model.filteredReviews) { review in
                ReviewCard(review: review)
            }
        }
    }
}

private struct RatingDistributionCard: View {
    let collection: ReviewCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Synced Rating Distribution")
                    .font(.headline)
                Spacer()
                Text("Latest \(collection.reviews.count) written reviews")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach((1...5).reversed(), id: \.self) { rating in
                let count = collection.count(for: rating)
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Text("\(rating)")
                            .monospacedDigit()
                            .frame(width: 12, alignment: .trailing)
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    .frame(width: 42, alignment: .trailing)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.09))
                            Capsule()
                                .fill(Color.yellow)
                                .frame(
                                    width: proxy.size.width
                                        * CGFloat(count) / CGFloat(max(collection.reviews.count, 1))
                                )
                        }
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)

                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(rating) stars")
                .accessibilityValue("\(count) synced reviews")
            }

            Text("Apple's public feed exposes recent written reviews, not every historical rating.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .reviewPanelStyle(minHeight: 224)
    }
}

private struct CoverageSummaryCard: View {
    let metadata: TrackedApp?
    let collection: ReviewCollection

    var body: some View {
        VStack(spacing: 10) {
            Text("Coverage Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(collection.averageRating.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            RatingStars(rating: collection.averageRating ?? 0)

            Text("\(collection.reviews.count) synced reviews across \(collection.storefrontCount) storefronts")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            if let metadata {
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(reviewStoreTitle(metadata.primaryStore)) App Store")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LabeledContent("All-time rating") {
                        Text(metadata.averageRating?.formatted(.number.precision(.fractionLength(1))) ?? "—")
                            .monospacedDigit()
                    }
                    LabeledContent("Ratings") {
                        Text(metadata.ratingCount?.formatted() ?? "—")
                            .monospacedDigit()
                    }
                }
            }
        }
        .reviewPanelStyle(minHeight: 224)
    }
}

private struct RatingStars: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: Double(star) <= rating.rounded() ? "star.fill" : "star")
            }
        }
        .font(.title3)
        .foregroundStyle(.yellow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Average rating")
        .accessibilityValue("\(rating.formatted(.number.precision(.fractionLength(1)))) out of 5")
    }
}

private struct ReviewFilterBar: View {
    @ObservedObject var model: ReviewDashboardController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search reviews", text: $model.filters.searchText)
                        .textFieldStyle(.plain)

                    if !model.filters.searchText.isEmpty {
                        Button {
                            model.filters.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear Search")
                        .accessibilityLabel("Clear Search")
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(.separator.opacity(0.8))
                }

            }

            HStack(spacing: 10) {
                Picker("Country", selection: $model.filters.storefront) {
                    Text("All Countries").tag(String?.none)
                    ForEach(availableStorefronts, id: \.self) { code in
                        Text("\(reviewFlagEmoji(code)) \(reviewStoreTitle(code))")
                            .tag(String?.some(code))
                    }
                }
                .frame(width: 190)

                Picker("Rating", selection: $model.filters.rating) {
                    Text("All Ratings").tag(Int?.none)
                    ForEach((1...5).reversed(), id: \.self) { rating in
                        Text("\(rating) Stars").tag(Int?.some(rating))
                    }
                }
                .frame(width: 145)

                Picker("Version", selection: $model.filters.version) {
                    Text("All Versions").tag(String?.none)
                    ForEach(model.collection.versions, id: \.self) { version in
                        Text("Version \(version)").tag(String?.some(version))
                    }
                }
                .frame(width: 170)

                Picker("Sort", selection: $model.filters.sortOrder) {
                    ForEach(ReviewSortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .frame(width: 165)

                Spacer()

                Text("\(model.filteredReviews.count) matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if model.isFiltered {
                    Button("Clear", action: model.clearFilters)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.07))
        }
    }

    private var availableStorefronts: [String] {
        Set(model.reviews.map(\.storefront)).sorted {
            reviewStoreTitle($0).localizedCaseInsensitiveCompare(reviewStoreTitle($1)) == .orderedAscending
        }
    }
}

private struct ReviewSyncStatus: View {
    @ObservedObject var model: ReviewDashboardController
    let onExport: (ReviewExportFormat) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if model.isRefreshing {
                ProgressView().controlSize(.small)
                Text("Checking all \(model.totalStorefrontCount) storefronts…")
            } else {
                Image(systemName: model.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.failures.isEmpty ? .green : .orange)
                Text("\(checkedStorefrontCount)/\(model.totalStorefrontCount) storefronts checked")
                if !model.failures.isEmpty {
                    Text("· \(model.failures.count) unavailable")
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Menu {
                ForEach(ReviewExportFormat.allCases, id: \.self) { format in
                    Button(format.displayName) { onExport(format) }
                }
            } label: {
                Label("Export All", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.reviews.isEmpty || model.isRefreshing)
            .help("Export every synced review, ignoring the current filters")

            if let lastUpdated = model.lastUpdated {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(relativeUpdateText(lastUpdated, relativeTo: context.date))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }

    private var checkedStorefrontCount: Int {
        model.completedStorefronts.count + model.failures.count
    }

    private func relativeUpdateText(_ date: Date, relativeTo now: Date) -> String {
        let elapsed = max(Int(now.timeIntervalSince(date)), 0)
        return switch elapsed {
        case ..<60: "Updated just now"
        case ..<3_600: "Updated \(elapsed / 60)m ago"
        case ..<86_400: "Updated \(elapsed / 3_600)h ago"
        default: "Updated \(elapsed / 86_400)d ago"
        }
    }
}

private struct ReviewCard: View {
    let review: AppReview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= review.rating ? "star.fill" : "star")
                    }
                }
                .foregroundStyle(.yellow)
                .accessibilityLabel("\(review.rating) out of 5 stars")

                Spacer()
                Text(reviewStoreTitle(review.storefront))
                if let version = review.version, !version.isEmpty {
                    Text("· v\(version)")
                }
                Text("· \(review.updatedAt.formatted(date: .abbreviated, time: .omitted))")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Text(review.title)
                .font(.headline)
                .textSelection(.enabled)
            Text(review.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Divider()

            HStack {
                Text("by \(review.reviewerName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Spacer()
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("Share Review")
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.075))
        }
    }

    private var shareText: String {
        "\(review.title)\n\n\(review.body)\n\n\(review.rating)/5 · \(reviewStoreTitle(review.storefront)) · \(review.reviewerName)"
    }
}

private extension View {
    func reviewPanelStyle(minHeight: CGFloat) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08))
            }
    }
}

func reviewStoreTitle(_ code: String) -> String {
    ResearchPresets.storeTitles[code.lowercased()]
        ?? Locale(identifier: "en_US").localizedString(forRegionCode: code.uppercased())
        ?? code.uppercased()
}

func reviewFlagEmoji(_ code: String) -> String {
    let scalars = code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }
    return String(String.UnicodeScalarView(scalars))
}
