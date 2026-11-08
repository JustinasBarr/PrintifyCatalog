import DesignSystem
import SwiftUI

/// What Home shows below the chips: with no chip chosen, what needs attention and a shelf per category; with one,
/// that category's grid; with more, only their shelves. The field and chips above stay put while this changes.
struct HomeSections: View {
    let viewModel: HomeViewModel
    @Environment(CatalogRouter.self) private var router

    var body: some View {
        // Old and new content overlap while one fades into the other, so nothing below the chips jumps. A fade has
        // no motion, so Reduce Motion gets the same one.
        ZStack(alignment: .top) {
            content
                .id(viewModel.state.selectedCategories)
                .transition(.opacity)
        }
        .animation(.strongEaseOut, value: viewModel.state.selectedCategories)
    }

    @ViewBuilder
    private var content: some View {
        let chosen = viewModel.state.selectedCategories
        if let list = viewModel.categoryList, let category = chosen.first {
            ChosenCategoryGrid(
                category: category,
                count: viewModel.state.shelves[category.slug]?.value?.total,
                list: list
            )
            // The count is the shelf's: it loads here when the shelf never scrolled in.
            .task { await viewModel.shelfAppeared(category) }
        } else if chosen.isEmpty {
            LazyVStack(alignment: .leading, spacing: 0) {
                attentionShelf
                    .padding(.top, Spacing.m)
                everyShelf
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                shelves(chosen)
            }
        }
    }

    private var attentionShelf: some View {
        ProductShelf(
            title: "Needs attention",
            count: attentionCount,
            products: viewModel.state.attention.map(\.products),
            emptyText: "Everything is in stock.",
            identifier: "home-shelf-attention",
            seeAllIdentifier: "home-button-seeAllAttention",
            retryIdentifier: "home-button-retryAttention",
            isRetrying: viewModel.state.isRetryingAttention,
            seeAll: { router.show(.attention) },
            retry: { await viewModel.retryAttention() }
        )
    }

    private var attentionCount: String? {
        guard let attention = viewModel.state.attention.value else { return nil }
        return attention.mayHaveMore ? "\(attention.products.count)+" : "\(attention.products.count)"
    }

    @ViewBuilder
    private var everyShelf: some View {
        switch viewModel.state.categories {
        case .loaded(let categories):
            shelves(categories)
        case .loading, .failed:
            ForEach(0..<2, id: \.self) { _ in
                ProductShelf.placeholder.padding(.top, Spacing.m)
            }
        }
    }

    private func shelves(_ categories: [Product.Category]) -> some View {
        ForEach(categories) { category in
            let shelf = viewModel.state.shelves[category.slug] ?? .loading
            ProductShelf(
                title: category.name,
                count: shelf.value.map { "\($0.total)" },
                products: shelf.map(\.items),
                emptyText: "No products yet.",
                identifier: "home-shelf-\(category.slug)",
                seeAllIdentifier: "home-button-seeAll-\(category.slug)",
                retryIdentifier: "home-button-retry-\(category.slug)",
                isRetrying: viewModel.state.retryingShelves.contains(category.slug),
                seeAll: { router.show(.category(category)) },
                retry: { await viewModel.retryShelf(category) }
            )
            .padding(.top, Spacing.m)
            .task { await viewModel.shelfAppeared(category) }
        }
    }
}

/// The one chosen category in place on Home: its name and product count, then the same grid as "See all".
private struct ChosenCategoryGrid: View {
    let category: Product.Category
    let count: Int?
    let list: ProductListViewModel

    var body: some View {
        // The shelves' header, so this title sits exactly where the shelf title it fades from sat; its 44 pt touch
        // height already spaces it from the cards.
        VStack(alignment: .leading, spacing: 0) {
            ProductShelf.Header(title: category.name, count: count.map { "\($0)" })
            ProductGrid(
                viewModel: list,
                screen: "home",
                retryIdentifier: "home-button-retryGrid",
                empty: EmptyListView(
                    title: "No products yet",
                    message: "This category has no products.",
                    systemImage: "shippingbox",
                    identifier: "home-text-empty"
                )
            )
            .padding(.horizontal, Spacing.l)
            .task { await list.load() }
        }
        .padding(.top, Spacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-grid-filtered")
    }
}

extension Loadable {
    fileprivate func map<New>(_ transform: (Value) -> New) -> Loadable<New> {
        switch self {
        case .loading: .loading
        case .loaded(let value): .loaded(transform(value))
        case .failed(let message): .failed(message)
        }
    }
}
