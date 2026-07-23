import SwiftUI

struct ReviewFilterBar: View {
    @Bindable var model: ReviewDashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Full-text search", systemImage: "text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Text("Searches titles, review text, authors, and versions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField(
                    "Search every synced review…",
                    text: $model.filters.searchText,
                    prompt: Text("Try “crash”, “subscription”, or a version number")
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)

                if !model.filters.searchText.isEmpty {
                    Button {
                        model.filters.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear full-text search")
                    .accessibilityLabel("Clear full-text search")
                }
            }

            HStack(spacing: 10) {
                Picker("Country", selection: $model.filters.storefront) {
                    Text("All Countries").tag(Storefront?.none)
                    ForEach(sortedStorefronts) { storefront in
                        Text("\(storefront.flagEmoji) \(storefront.displayName)")
                            .tag(Storefront?.some(storefront))
                    }
                }

                Picker("Rating", selection: $model.filters.rating) {
                    Text("All Ratings").tag(Int?.none)
                    ForEach((1...5).reversed(), id: \.self) { rating in
                        Text("\(rating) Stars").tag(Int?.some(rating))
                    }
                }

                Picker("Version", selection: $model.filters.version) {
                    Text("All Versions").tag(String?.none)
                    ForEach(model.collection.versions, id: \.self) { version in
                        Text("Version \(version)").tag(String?.some(version))
                    }
                }

                Picker("Sort", selection: $model.filters.sortOrder) {
                    ForEach(ReviewSortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }

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
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var sortedStorefronts: [Storefront] {
        Storefront.allCases.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
