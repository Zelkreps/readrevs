import SwiftUI

struct ReviewCard: View {
    let review: AppReview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                RatingStarsCompact(rating: review.rating)
                Spacer()
                Text(review.storefront.displayName)
                if let version = review.version, !version.isEmpty {
                    Text("·")
                    Text("v\(version)")
                }
                Text("·")
                Text(review.updatedAt.formatted(date: .abbreviated, time: .omitted))
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
                    Label("Share Review", systemImage: "square.and.arrow.up")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Share or copy this review")
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.075), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var shareText: String {
        "\(review.title)\n\n\(review.body)\n\n\(review.rating)/5 · \(review.storefront.displayName) · \(review.reviewerName)"
    }
}

private struct RatingStarsCompact: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
            }
        }
        .foregroundStyle(.yellow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating) out of 5 stars")
    }
}
