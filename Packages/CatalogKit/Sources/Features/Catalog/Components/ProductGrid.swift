import DesignSystem
import SwiftUI

/// A list's products as a 2-column grid that pages as it scrolls, with its loading, failed and empty states and the
/// paging footer. One column at accessibility text sizes, so names and prices stay readable. Drawn inside a scroll
/// view: the "See all" screen, Home's chosen category and Home's search.
struct ProductGrid<Products: PagedProducts>: View {
    let viewModel: Products
    /// The first part of every identifier, the screen: `<screen>-cell-<id>`, `<screen>-footer-loading`.
    let screen: String
    let retryIdentifier: String
    /// What the list says when it has no products.
    let empty: EmptyListView
    @Environment(CatalogRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var zoom

    var body: some View {
        VStack(spacing: Spacing.l) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.products {
        case .loading:
            grid { ForEach(0..<6, id: \.self) { _ in ProductCellSkeleton() } }
                .transition(.opacity)
        case .failed(let message):
            LoadFailedView(
                title: "Couldn't load products",
                message: message,
                retryIdentifier: retryIdentifier,
                isRetrying: viewModel.isRetrying
            ) {
                await viewModel.retry()
            }
            .containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
        case .loaded(let products) where products.isEmpty:
            empty.containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
        case .loaded(let products):
            grid { cells(products) }
                .transition(.opacity)
            footer
        }
    }

    private func grid(@ViewBuilder _ cells: () -> some View) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.l) { cells() }
            // Skeleton and cells have one size, so the swap is a cross-fade and nothing moves.
            .animation(.strongEaseOut, value: viewModel.products.value == nil)
    }

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.m, alignment: .top), count: count)
    }

    private func cells(_ products: [Product.Summary]) -> some View {
        ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
            Button {
                router.present(product, from: zoom)
            } label: {
                ProductCell(product: product)
            }
            .buttonStyle(.pressable)
            .zoomSource(id: product.id, in: zoom)
            .accessibilityIdentifier("\(screen)-cell-\(product.id)")
            // Not `.task`: scrolling past this cell must not cancel the page it started.
            .onAppear { Task { await viewModel.itemAppeared(at: index) } }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch viewModel.nextPage {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 64)
                .accessibilityLabel("Loading more products")
                .accessibilityIdentifier("\(screen)-footer-loading")
        case .failed(let message):
            VStack(spacing: Spacing.s) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await viewModel.retry() } }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Color.action)
                    .accessibilityIdentifier(retryIdentifier)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
    }
}
