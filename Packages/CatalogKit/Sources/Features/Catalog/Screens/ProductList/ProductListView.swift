import DesignSystem
import SwiftUI

/// "See all": a category, or the products that need attention, as a grid that pages as it scrolls.
struct ProductListView: View {
    let list: CatalogRouter.Route
    @State private var viewModel: ProductListViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(list: CatalogRouter.Route, viewModel: ProductListViewModel) {
        self.list = list
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                if let failure = viewModel.state.refreshFailure {
                    RefreshFailedNotice(message: failure, retryIdentifier: "list-button-retryRefresh") {
                        await viewModel.retry()
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                ProductGrid(list: list, viewModel: viewModel, screen: "list", retryIdentifier: "list-button-retry")
            }
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

    private var title: String {
        switch list {
        case .category(let category): category.name
        case .attention: "Needs attention"
        }
    }
}
