import DesignSystem
import SwiftUI

/// What customers said, newest first: stars, their words, their name and the day. The reviewer's email is never
/// decoded, so it cannot appear here.
struct ProductReviews: View {
    /// `nil` while the product loads: placeholder reviews hold the section's shape.
    let reviews: [Product.Review]?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            heading
            if let reviews {
                if reviews.isEmpty {
                    Text("No reviews yet")
                        .font(.subheadline)
                        .foregroundStyle(Color.ink3)
                } else {
                    // Two customers can leave the same words on the same day, so a review's values are no identity;
                    // the list is only ever replaced whole, so its place is.
                    ForEach(Array(reviews.enumerated()), id: \.offset) { _, review in
                        ReviewRow(review: review, isLoading: false)
                    }
                }
            } else {
                ForEach(0..<3, id: \.self) { _ in
                    ReviewRow(review: placeholder, isLoading: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail-list-reviews")
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text("Reviews")
                .font(.sectionTitle)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            if let reviews, !reviews.isEmpty {
                Text("\(reviews.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.ink3)
                    .accessibilityHidden(true)
            }
        }
    }

    private var placeholder: Product.Review {
        Product.Review(
            rating: 5,
            comment: "A customer's few words",
            date: Date(timeIntervalSince1970: 0),
            reviewerName: "Customer name"
        )
    }
}

private struct ReviewRow: View {
    let review: Product.Review
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                RatingStars(rating: review.rating)
                Spacer(minLength: Spacing.s)
                Text(review.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
            }
            Text(review.comment)
                .font(.body)
                .foregroundStyle(Color.ink)
            Text(review.reviewerName)
                .font(.footnote)
                .foregroundStyle(Color.ink2)
        }
        .redacted(reason: isLoading ? .placeholder : [])
        .shimmering(isLoading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoading ? "Loading review" : spokenReview)
    }

    private var spokenReview: String {
        let day = review.date.formatted(date: .long, time: .omitted)
        return "\(review.rating) out of 5 stars. \(review.comment) \(review.reviewerName), \(day)"
    }
}

private struct RatingStars: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: "star.fill")
                    .foregroundStyle(star <= rating ? Color.rating : Color.ink.opacity(0.14))
            }
        }
        .font(.caption)
    }
}
