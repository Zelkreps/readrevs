import SwiftUI

struct ReviewFilterBar: View {
    @Bindable var model: ReviewDashboardModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search title, review, or author", text: $model.filters.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Picker("Country", selection: $model.filters.storefront) {
                    Text("All Countries").tag(Storefront?.none)
                    ForEach(Storefront.priority) { storefront in
                        Text(storefront.displayName).tag(Storefront?.some(storefront))
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

                if model.isFiltered {
                    Button("Clear", action: model.clearFilters)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}
