import SwiftUI

/// The catalog's navigation: Home at the root, a pushed grid for each chip or "See all", and the tapped
/// product presented over them, zooming out of its cell.
public struct CatalogRootView: View {
    private let feature: CatalogFeature
    @State private var home: HomeViewModel
    @State private var search: SearchViewModel

    public init(feature: CatalogFeature) {
        self.feature = feature
        // SwiftUI keeps the first value, so Home and its search keep their state for the app's life.
        _home = State(initialValue: feature.home())
        _search = State(initialValue: feature.search())
    }

    public var body: some View {
        @Bindable var router = feature.router
        NavigationStack(path: $router.path) {
            HomeView(viewModel: home, search: search)
                .navigationDestination(for: CatalogRouter.Route.self) { route in
                    ProductListView(list: route, viewModel: feature.productList(route))
                }
        }
        .fullScreenCover(item: $router.presented) { presented in
            ProductDetailView(
                viewModel: feature.makeProductDetail(for: presented.product),
                zoomNamespace: presented.source
            )
        }
        .environment(feature.router)
    }
}
