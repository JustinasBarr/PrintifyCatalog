import DesignSystem
import SwiftUI

/// One row of Home: a serif title with its count and "See all", then products side by side. Loading, failed
/// and empty keep the row's height, so the shelves below never move.
struct ProductShelf: View {
    /// Nil draws a redacted title, for the shelves shown before the categories arrive.
    let title: String?
    let count: String?
    let products: Loadable<[Product.Summary]>
    let emptyText: String
    let identifier: String
    let seeAllIdentifier: String
    let retryIdentifier: String
    let seeAll: () -> Void
    let retry: () async -> Void
    @Environment(CatalogRouter.self) private var router
    @Namespace private var zoom

    /// A shelf while the categories load.
    static let placeholder = ProductShelf(
        title: nil,
        count: nil,
        products: .loading,
        emptyText: "",
        identifier: "home-shelf-placeholder",
        seeAllIdentifier: "",
        retryIdentifier: "",
        seeAll: {},
        retry: {}
    )

    var body: some View {
        // The header's 44 pt touch height already spaces it from the cards.
        VStack(alignment: .leading, spacing: 0) {
            header
            row
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var header: some View {
        Header(
            title: title,
            count: count,
            seeAllIdentifier: seeAllIdentifier,
            seeAll: title == nil ? nil : seeAll
        )
    }

    private var row: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Spacing.m) {
                cards
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Spacing.l, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollDisabled(products.value?.isEmpty != false)
        .overlay { message }
        // Skeleton and cards have one size, so the swap is a cross-fade and nothing moves.
        .animation(.strongEaseOut, value: products.value == nil)
    }

    @ViewBuilder
    private var cards: some View {
        switch products {
        case .loaded(let products) where !products.isEmpty:
            ForEach(products) { product in
                Button {
                    router.present(product, from: zoom)
                } label: {
                    ProductCell(product: product, layout: .shelf)
                        .shelfCardWidth()
                }
                .buttonStyle(.pressable)
                .zoomSource(id: product.id, in: zoom)
                .accessibilityIdentifier("home-cell-\(product.id)")
            }
            .transition(.opacity)
        case .loading:
            skeletons.transition(.opacity)
        case .loaded, .failed:
            // Holds the row's height under the message.
            skeletons.hidden()
        }
    }

    private var skeletons: some View {
        ForEach(0..<3, id: \.self) { _ in
            ProductCellSkeleton(layout: .shelf).shelfCardWidth()
        }
    }

    @ViewBuilder
    private var message: some View {
        switch products {
        case .failed(let message):
            VStack(spacing: Spacing.s) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await retry() } }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Color.action)
                    .accessibilityIdentifier(retryIdentifier)
            }
            .padding(.horizontal, Spacing.xl)
        case .loaded(let products) where products.isEmpty:
            Label(emptyText, systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(Color.ink2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, Spacing.l)
        default:
            EmptyView()
        }
    }
}

extension ProductShelf {
    /// A shelf's serif title, its count and "See all", also above Home's one chosen category.
    struct Header: View {
        /// Nil draws a redacted title, for the shelves shown before the categories arrive.
        let title: String?
        let count: String?
        var seeAllIdentifier = ""
        var seeAll: (() -> Void)?
        @Environment(\.dynamicTypeSize) private var typeSize

        var body: some View {
            layout {
                Text(title ?? "Category name")
                    .font(.shelfTitle)
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                    .redacted(reason: title == nil ? .placeholder : [])
                    .shimmering(title == nil)
                    // Without it the row beside it, which holds a spacer, takes half the width and the title wraps.
                    .layoutPriority(1)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    if let count {
                        Text(count)
                            .font(.footnote.weight(.medium).monospacedDigit())
                            .foregroundStyle(Color.ink3)
                            .accessibilityLabel(countLabel(count))
                    }
                    Spacer(minLength: Spacing.s)
                    // The title lines up with this button's text, so without an action its place stays empty
                    // and every title sits at the same height.
                    if let seeAll {
                        seeAllButton(seeAll)
                    } else {
                        seeAllButton {}.hidden()
                    }
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, Spacing.l)
            .animation(.strongEaseOut, value: count)
        }

        /// The title, then its count and "See all" on the same line; at accessibility text sizes the title takes
        /// its own full-width line so it wraps between words, not inside them.
        private var layout: AnyLayout {
            typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.s))
        }

        private func seeAllButton(_ action: @escaping () -> Void) -> some View {
            Button("See all", action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.action)
                .frame(minHeight: 44)
                .contentShape(.rect)
                .accessibilityIdentifier(seeAllIdentifier)
        }

        private func countLabel(_ count: String) -> String {
            count.hasSuffix("+") ? "\(count.dropLast()) or more products" : "\(count) products"
        }
    }
}

extension View {
    /// 150 pt, so two cards and the edge of a third show; at accessibility text sizes a card takes most of the
    /// row so its text has room.
    fileprivate func shelfCardWidth() -> some View {
        modifier(ShelfCardWidth())
    }
}

private struct ShelfCardWidth: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content.containerRelativeFrame(.horizontal) { width, _ in width * 0.8 }
        } else {
            content.frame(width: 150)
        }
    }
}
