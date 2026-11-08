import Networking

/// The catalog as the app sees it: built once with its services, shown with `CatalogRootView`. It builds every
/// screen's view model, so views never reach the repository themselves.
@MainActor
public final class CatalogFeature {
    private let repository: any ProductRepositoryProtocol
    let router = CatalogRouter()

    /// The catalog from the products API through `client`.
    public convenience init(client: APIClient) {
        self.init(repository: ProductRepository(client: client))
    }

    init(repository: any ProductRepositoryProtocol) {
        self.repository = repository
    }

    func home() -> HomeViewModel {
        HomeViewModel(repository: repository) { [self] category in productList(.category(category)) }
    }

    func productList(_ route: CatalogRouter.Route) -> ProductListViewModel {
        switch route {
        case .category(let category):
            ProductListViewModel { [repository] page, sort throws(APIError) in
                try await repository.products(inCategory: category.slug, page, sortedBy: sort)
            }
        case .attention:
            ProductListViewModel(alwaysNeedsAttention: true) { [repository] page, sort throws(APIError) in
                try await repository.products(page, sortedBy: sort)
            }
        }
    }

    /// The detail for a product the list shows: it opens on the list's summary and loads the rest by id.
    func makeProductDetail(for summary: Product.Summary) -> ProductDetailViewModel {
        ProductDetailViewModel(
            summary: summary,
            loadProduct: { [repository] id throws(APIError) in try await repository.product(id: id) },
            updateStock: { [repository] id, stock throws(APIError) in
                try await repository.updateStock(id: id, stock: stock)
            }
        )
    }

    func search() -> SearchViewModel {
        SearchViewModel { [repository] text, page throws(APIError) in
            try await repository.search(text, page, sortedBy: nil)
        }
    }
}
