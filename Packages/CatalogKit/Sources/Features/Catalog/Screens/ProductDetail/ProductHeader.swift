import DesignSystem
import SwiftUI

/// Everything the list already knew, so it draws in the first frame: maker, name, price, rating and stock.
struct ProductHeader: View {
    let summary: Product.Summary
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(maker)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink2)
            Text(summary.title)
                .font(.productTitle)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("detail-text-title")
            price
                .padding(.top, Spacing.xs)
            ratingAndStock
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The brand is missing on about half the catalog; the category takes its line, so it is never empty.
    private var maker: String {
        summary.brand ?? summary.category.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private var price: some View {
        stacking(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.s)) {
            Text(summary.discountedPrice, format: .currency(code: "USD"))
                .font(.title.weight(.bold))
                .foregroundStyle(Color.ink)
            if hasDiscount {
                Text(summary.price, format: .currency(code: "USD"))
                    .font(.callout)
                    .strikethrough()
                    .foregroundStyle(Color.ink3)
                DiscountTag(percent: roundedDiscount)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenPrice)
    }

    private var ratingAndStock: some View {
        stacking(HStackLayout(alignment: .center, spacing: Spacing.m)) {
            Label {
                Text(summary.rating, format: .number.precision(.fractionLength(1)))
                    .foregroundStyle(Color.ink)
            } icon: {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.rating)
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rated \(summary.rating.formatted(.number.precision(.fractionLength(1)))) out of 5")
            StockChip(availability: summary.availability, stock: summary.stock)
        }
    }

    /// A row that wraps into a column at accessibility text sizes, where it no longer fits one line.
    private func stacking(_ row: HStackLayout, @ViewBuilder content: () -> some View) -> some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs)) : AnyLayout(row)
        return layout(content)
    }

    private var roundedDiscount: Int { Int(summary.discountPercentage.rounded()) }

    /// A discount under half a percent rounds to "0%": not worth striking a price through.
    private var hasDiscount: Bool { roundedDiscount > 0 }

    private var spokenPrice: String {
        let now = summary.discountedPrice.formatted(.currency(code: "USD"))
        guard hasDiscount else { return "Price \(now)" }
        return "Price \(now), was \(summary.price.formatted(.currency(code: "USD"))), \(roundedDiscount) percent off"
    }
}

private struct DiscountTag: View {
    let percent: Int

    var body: some View {
        Text("−\(percent)%")
            .font(.label)
            .foregroundStyle(Color.onAction)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(Color.action, in: .capsule)
    }
}
