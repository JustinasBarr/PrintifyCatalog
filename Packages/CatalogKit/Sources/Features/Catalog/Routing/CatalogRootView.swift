import DesignSystem
import SwiftUI

/// The catalog's navigation: Home at the root, a pushed grid for each chip or "See all", and the tapped
/// product presented over them, zooming out of its cell.
public struct CatalogRootView: View {
    private let feature: CatalogFeature
    @State private var home: HomeViewModel

    public init(feature: CatalogFeature) {
        self.feature = feature
        // SwiftUI keeps the first value, so Home keeps its state for the app's life.
        _home = State(initialValue: feature.home())
    }

    public var body: some View {
        @Bindable var router = feature.router
        NavigationStack(path: $router.path) {
            HomeView(viewModel: home)
                .navigationDestination(for: CatalogRouter.Route.self) { route in
                    ProductListView(list: route, viewModel: feature.productList(route))
                }
        }
        .fullScreenCover(item: $router.presented) { presented in
            ProductDetailPlaceholder(product: presented.product)
                .zoomDestination(id: presented.product.id, in: presented.source)
        }
        .environment(feature.router)
    }
}

/// Stands in for the product detail, which is built separately: the tapped product's photo and title.
private struct ProductDetailPlaceholder: View {
    let product: Product.Summary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Color.tile
                        .overlay {
                            RemoteImage(
                                url: product.thumbnail,
                                inset: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
                            )
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
                    Text(product.title)
                        .font(.system(.title, design: .serif, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("detail-text-title")
                    StockChip(availability: product.availability, stock: product.stock)
                }
                .padding(Spacing.l)
            }
            .background(Color.ground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("detail-button-close")
                }
            }
        }
    }
}
