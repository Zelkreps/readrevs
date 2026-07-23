import SwiftUI

struct ReviewDashboardView: View {
    @Bindable var model: ReviewDashboardModel
    @State private var exportDocument: ReviewExportDocument?
    @State private var exportFormat: ReviewExportFormat = .json
    @State private var exportFilename = "reviews.json"
    @State private var isExporting = false
    @State private var operationErrorMessage: String?
    @State private var metricCardHeight: CGFloat = 0
    @State private var researchPresentation: CodexResearchPresentation?
    @AppStorage(CodexResearchPreferences.modelIDStorageKey)
    private var codexModelID = CodexResearchPreferences.defaultModelID
    @AppStorage(CodexReasoningEffort.storageKey)
    private var codexReasoningEffort = CodexReasoningEffort.defaultValue.rawValue

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let metadata = model.metadata {
                    AppHeaderView(app: metadata)
                }

                metrics
                ReviewFilterBar(model: model)
                SyncStatusView(
                    model: model,
                    onExport: beginExport
                )

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
                    .fixedSize()
                    .frame(width: ReviewDashboardActionLayout.width, alignment: .trailing)
                    .disabled(model.reviews.isEmpty || model.isRefreshing)
                    .help("Analyze every synced review in an embedded Codex CLI conversation")
                }

                reviewContent
            }
            .padding(24)
            .frame(maxWidth: 1_480, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.secondary.opacity(0.035))
        .navigationTitle(model.metadata?.name ?? "Reviews")
        .sheet(item: $researchPresentation) { presentation in
            CodexResearchChatView(
                bundle: presentation.bundle,
                appName: presentation.appName,
                reviewCount: presentation.reviewCount,
                storefrontCount: presentation.storefrontCount,
                codexModel: presentation.codexModel,
                reasoningEffort: presentation.reasoningEffort
            )
        }
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
            let service = try CodexResearchBundleService.live()
            let bundle = try service.prepare(
                app: app,
                reviews: model.reviews,
                completedStorefronts: model.completedStorefronts,
                failures: model.failures
            )
            let configuration = CodexResearchPreferences.resolve(
                storedModelID: codexModelID,
                storedReasoningEffort: codexReasoningEffort
            )
            researchPresentation = CodexResearchPresentation(
                bundle: bundle,
                appName: app.name,
                reviewCount: model.reviews.count,
                storefrontCount: model.collection.storefrontCount,
                codexModel: configuration.model,
                reasoningEffort: configuration.reasoningEffort
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

    @ViewBuilder
    private var metrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                RatingDistributionCard(
                    collection: model.collection,
                    minimumHeight: metricCardHeight,
                    reportsHeight: true
                )
                    .frame(maxWidth: .infinity)
                CoverageSummaryCard(
                    metadata: model.metadata,
                    collection: model.collection,
                    minimumHeight: metricCardHeight,
                    reportsHeight: true
                )
                    .frame(width: 350)
            }
            .onPreferenceChange(MetricCardHeightPreferenceKey.self) { height in
                guard height > 0, abs(metricCardHeight - height) > 0.5 else { return }
                metricCardHeight = height
            }

            VStack(spacing: 16) {
                RatingDistributionCard(collection: model.collection)
                CoverageSummaryCard(metadata: model.metadata, collection: model.collection)
            }
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        if model.isRefreshing, model.reviews.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Checking all \(Storefront.allCases.count) storefronts…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if let errorMessage = model.errorMessage, model.reviews.isEmpty {
            ContentUnavailableView {
                Label("Reviews unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            }
            .frame(maxWidth: .infinity, minHeight: 320, alignment: .center)
        } else if model.filteredReviews.isEmpty {
            ContentUnavailableView {
                Label(model.isFiltered ? "No matching reviews" : "No written reviews found", systemImage: "text.magnifyingglass")
            } description: {
                Text(model.isFiltered ? "Try clearing one or more filters." : "Apple returned no recent written reviews for the checked storefronts.")
            } actions: {
                if model.isFiltered {
                    Button("Clear Filters") { model.clearFilters() }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 320, alignment: .center)
        } else {
            ForEach(model.filteredReviews) { review in
                ReviewCard(review: review)
            }
        }
    }
}

private struct CodexResearchPresentation: Identifiable {
    let id = UUID()
    let bundle: CodexResearchBundle
    let appName: String
    let reviewCount: Int
    let storefrontCount: Int
    let codexModel: CodexModelConfiguration
    let reasoningEffort: CodexReasoningEffort
}

private struct AppHeaderView: View {
    let app: AppMetadata

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            AsyncImage(url: app.artworkURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "app.dashed")
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, height: 84)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 8) {
                Text(app.name)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(app.sellerName)
                    Text("·")
                    Text("ID: \(app.appID)")
                }
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

                HStack(spacing: 12) {
                    Label("v\(app.version)", systemImage: "shippingbox")
                    Label(app.primaryGenre, systemImage: "square.grid.2x2")
                    Label(app.primaryStorefront.displayName, systemImage: "globe")
                    if let date = app.currentVersionReleaseDate ?? app.releaseDate {
                        Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if let appStoreURL = app.appStoreURL {
                Link(destination: appStoreURL) {
                    Label("App Store", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct RatingDistributionCard: View {
    let collection: ReviewCollection
    var minimumHeight: CGFloat? = nil
    var reportsHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

                    RatingBar(
                        value: Double(count) / Double(max(collection.reviews.count, 1))
                    )

                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(rating) stars")
                .accessibilityValue("\(count) synced reviews")
            }

            Text("Apple's public feed exposes only recent written reviews, not all historical ratings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardStyle(minimumHeight: minimumHeight, reportsHeight: reportsHeight)
    }
}

private struct RatingBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(Color.yellow.gradient)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

private struct CoverageSummaryCard: View {
    let metadata: AppMetadata?
    let collection: ReviewCollection
    var minimumHeight: CGFloat? = nil
    var reportsHeight = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Coverage Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(collection.averageRating.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            RatingStars(rating: collection.averageRating ?? 0)

            Text("\(collection.reviews.count) synced reviews across \(collection.storefrontCount) storefronts")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            if let metadata {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(metadata.primaryStorefront.displayName) App Store")
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
        .cardStyle(minimumHeight: minimumHeight, reportsHeight: reportsHeight)
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

private extension View {
    func cardStyle(minimumHeight: CGFloat? = nil, reportsHeight: Bool = false) -> some View {
        padding(20)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .background {
                if reportsHeight {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MetricCardHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
            }
    }
}

private struct MetricCardHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
