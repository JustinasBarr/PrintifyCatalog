import DesignSystem
import SwiftUI

/// A product as a merchant scans it: the photo with its discount, the name, what a customer pays with the
/// rating, and the stock. VoiceOver reads it as one element in that order.
struct ProductCell: View {
    let product: Product.Summary
    var layout = Layout.grid
    @Environment(\.dynamicTypeSize) private var typeSize

    enum Layout {
        /// A column of the grid; the photo keeps a 6:5 shape.
        case grid
        /// A card in a Home shelf; the photo keeps a fixed height, and a 6:5 shape on the wider card of
        /// accessibility text sizes.
        case shelf
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo
            Text(product.title)
                .font(.cardTitle)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .padding(.top, Spacing.s)
            PriceAndRating(product: product)
                .padding(.top, 2)
            StockChip(availability: product.availability, stock: product.stock)
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var photo: some View {
        Color.tile
            .overlay {
                RemoteImage(url: product.thumbnail, inset: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
            .overlay(alignment: .topLeading) {
                DiscountBadge(percent: product.discountPercentage).padding(Spacing.s)
            }
            .photoShape(layout, isAccessibilitySize: typeSize.isAccessibilitySize)
            .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
    }
}

/// Loading stand-in: the real cell with placeholder values, redacted, so every line has the height the loaded
/// cell will have and nothing moves when products arrive. Grey, so it promises no stock state.
struct ProductCellSkeleton: View {
    var layout = ProductCell.Layout.grid

    var body: some View {
        ProductCell(product: .placeholder, layout: layout)
            .redacted(reason: .placeholder)
            .saturation(0)
            .shimmering()
            .accessibilityHidden(true)
    }
}

extension Product.Summary {
    fileprivate static let placeholder = Product.Summary(
        id: 0,
        title: "Product name here",
        price: 10,
        discountPercentage: 0,
        rating: 4.5,
        stock: 50,
        availabilityStatus: "In Stock",
        brand: nil,
        category: "",
        thumbnail: URL(filePath: "/")
    )
}

extension View {
    /// A fixed 128 pt photo in a shelf, 6:5 in the grid and on the shelf's wider card at accessibility text
    /// sizes, where a 128 pt strip would leave the photo smaller than its badge. A colour has no size of its
    /// own, so each layout gets one explicit rule.
    @ViewBuilder
    fileprivate func photoShape(_ layout: ProductCell.Layout, isAccessibilitySize: Bool) -> some View {
        switch layout {
        case .shelf where !isAccessibilitySize: frame(height: 128)
        case .shelf, .grid: aspectRatio(6 / 5, contentMode: .fit)
        }
    }
}

/// What a customer pays (the API's price less its discount) and the rating. The price before the discount is
/// left to the badge and to VoiceOver: written in full for the locale ("US$1 737,16") it fits beside the rest in
/// only some cells of a two-column grid, and a grid where some cells show it and some don't reads as ragged.
private struct PriceAndRating: View {
    let product: Product.Summary
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        layout {
            Text(product.discountedPrice, format: .currency(code: "USD"))
                .font(.cardPrice)
                .foregroundStyle(Color.ink)
                // A price with a digit cut off is wrong, so it shrinks to fit instead.
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(spokenPrice)
            Rating(value: product.rating)
        }
        .lineLimit(1)
    }

    /// Side by side; stacked at accessibility text sizes so the price has the card's full width.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.xs))
    }

    private var hasDiscount: Bool { product.discountedPrice < product.price }

    /// The discount is read here, after the price, so the badge on the photo stays out of VoiceOver's way.
    private var spokenPrice: String {
        let paid = product.discountedPrice.formatted(.currency(code: "USD"))
        guard hasDiscount else { return paid }
        let before = product.price.formatted(.currency(code: "USD"))
        return "\(paid), \(Int(product.discountPercentage.rounded())) percent off \(before)"
    }
}

private struct Rating: View {
    let value: Double

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .imageScale(.small)
                .foregroundStyle(Color.rating)
            Text(value, format: .number.precision(.fractionLength(1)))
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(Color.ink2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(value.formatted(.number.precision(.fractionLength(1)))) of 5")
    }
}

private struct DiscountBadge: View {
    let percent: Double

    var body: some View {
        let rounded = Int(percent.rounded())
        if rounded > 0 {
            Text("−\(rounded)%")
                .font(.caption2.bold().monospacedDigit())
                // VoiceOver reads the discount with the price, so a larger badge would only cover the photo.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Color.onAction)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, 3)
                .background(Color.action, in: .capsule)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(spacing: Spacing.m), GridItem()], spacing: Spacing.l) {
            ProductCellSkeleton()
            ProductCellSkeleton()
        }
        .padding(Spacing.l)
    }
}
