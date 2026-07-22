import SwiftUI

struct SyncStatusView: View {
    @Bindable var model: ReviewDashboardModel

    var body: some View {
        HStack(spacing: 10) {
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Checking \(Storefront.priority.count) priority storefronts…")
            } else {
                Image(systemName: model.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.failures.isEmpty ? .green : .orange)
                Text("\(model.completedStorefronts.count)/\(Storefront.priority.count) storefronts checked")
            }

            if !model.failures.isEmpty, !model.isRefreshing {
                Text("· \(model.failures.count) unavailable")
                    .foregroundStyle(.orange)
            }

            Spacer()

            if let lastUpdated = model.lastUpdated {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(relativeUpdateText(lastUpdated, relativeTo: context.date))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    private func relativeUpdateText(_ date: Date, relativeTo now: Date) -> String {
        let elapsed = max(Int(now.timeIntervalSince(date)), 0)
        switch elapsed {
        case ..<60:
            return "Updated just now"
        case ..<3_600:
            return "Updated \(elapsed / 60)m ago"
        case ..<86_400:
            return "Updated \(elapsed / 3_600)h ago"
        default:
            return "Updated \(elapsed / 86_400)d ago"
        }
    }
}
