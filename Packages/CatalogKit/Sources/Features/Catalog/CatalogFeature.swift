import Networking

/// The catalog as the app sees it: built once with its services, shown with `CatalogRootView`. It builds every
/// screen's view model, so views never reach the repository themselves.
@MainActor
public final class CatalogFeature {
    let repository: any ProductRepository
    let router = CatalogRouter()

    /// The catalog from the products API through `client`.
    public convenience init(client: APIClient) {
        self.init(repository: LiveProductRepository(client: client))
    }

    init(repository: any ProductRepository) {
        self.repository = repository
    }

    func home() -> HomeViewModel {
        HomeViewModel(repository: repository) { [self] category in productList(.category(category)) }
    }

    func productList(_ route: CatalogRouter.Route) -> ProductListViewModel {
        switch route {
        case .category(let category):
            ProductListViewModel { [repository] page throws(APIError) in
                try await repository.products(inCategory: category.slug, page, sortedBy: nil)
            }
        case .attention:
            // The API cannot filter by availability: pages come sorted by stock and the list keeps the rows
            // that need attention.
            ProductListViewModel(keeping: \.needsAttention) { [repository] page throws(APIError) in
                try await repository.products(page, sortedBy: .stockLowFirst)
            }
        }
    }
}
