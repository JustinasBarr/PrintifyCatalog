import Networking

/// The catalog as the app sees it: built once with its services. Screens come next; for now it holds the
/// repository every screen will read through.
@MainActor
public final class CatalogFeature {
    let repository: any ProductRepository

    /// The catalog from the products API through `client`.
    public convenience init(client: APIClient) {
        self.init(repository: LiveProductRepository(client: client))
    }

    init(repository: any ProductRepository) {
        self.repository = repository
    }
}
