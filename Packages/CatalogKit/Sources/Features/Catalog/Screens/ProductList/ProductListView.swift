import DesignSystem
import SwiftUI

/// "See all": a category, or the products that need attention, as a grid that pages as it scrolls. The toolbar's
/// button sorts and filters it.
struct ProductListView: View {
    let list: CatalogRouter.Route
    @State private var viewModel: ProductListViewModel
    @State private var isSortFilterShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let top = "top"

    init(list: CatalogRouter.Route, viewModel: ProductListViewModel) {
        self.list = list
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollViewReader { scroller in
            scrollingProducts
                // A new order starts at its first row.
                .onChange(of: viewModel.state.sortFilter) { scroller.scrollTo(top, anchor: .top) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { sortFilterButton }
        }
        .sheet(isPresented: $isSortFilterShown) {
            SortFilterSheet(viewModel: viewModel, offersAttentionFilter: list != .attention)
        }
    }

    private var scrollingProducts: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                if let failure = viewModel.state.refreshFailure {
                    RefreshFailedNotice(message: failure, retryIdentifier: "list-button-retryRefresh") {
                        await viewModel.refresh()
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                ProductGrid(viewModel: viewModel, screen: "list", retryIdentifier: "list-button-retry", empty: empty)
                    .task { await viewModel.load() }
            }
            .id(top)
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xl)
            .animation(.strongEaseOut, value: viewModel.state.refreshFailure)
        }
        .background(Color.ground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("list-grid-products")
        .refreshable { await viewModel.refresh() }
    }

    /// Filled while the list is sorted or filtered differently from how it opened.
    private var sortFilterButton: some View {
        Button {
            isSortFilterShown = true
        } label: {
            Image(
                systemName: viewModel.isSortedOrFiltered
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityLabel("Sort and filter")
        .accessibilityValue(viewModel.isSortedOrFiltered ? "On" : "")
        .accessibilityIdentifier("list-button-sortFilter")
    }

    private var title: String {
        switch list {
        case .category(let category): category.name
        case .attention: "Needs attention"
        }
    }

    private var empty: EmptyListView {
        switch list {
        case .category where viewModel.state.sortFilter.needsAttentionOnly:
            EmptyListView(
                title: "Nothing needs attention",
                message: "Every product in this category is in stock.",
                systemImage: "checkmark.circle",
                identifier: "list-text-empty"
            )
        case .category:
            EmptyListView(
                title: "No products yet",
                message: "This category has no products.",
                systemImage: "shippingbox",
                identifier: "list-text-empty"
            )
        case .attention:
            EmptyListView(
                title: "Nothing needs attention",
                message: "Every product is in stock.",
                systemImage: "checkmark.circle",
                identifier: "list-text-empty"
            )
        }
    }
}
