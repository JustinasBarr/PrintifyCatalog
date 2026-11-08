import Networking

/// Where catalog screens get products. The app uses `LiveProductRepository`; tests use a fake.
protocol ProductRepository: Sendable {
    func products(_ page: PageRequest, sortedBy sort: Product.Sort?) async throws(APIError) -> Page<Product.Summary>
    func products(
        inCategory slug: String,
        _ page: PageRequest,
        sortedBy sort: Product.Sort?
    ) async throws(APIError) -> Page<Product.Summary>
    func search(
        _ text: String,
        _ page: PageRequest,
        sortedBy sort: Product.Sort?
    ) async throws(APIError) -> Page<Product.Summary>
    func categories() async throws(APIError) -> [Product.Category]
    func product(id: Int) async throws(APIError) -> Product
}

/// The catalog from the DummyJSON products API (https://dummyjson.com/docs/products) through `client`.
struct LiveProductRepository: ProductRepository {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func products(_ page: PageRequest, sortedBy sort: Product.Sort?) async throws(APIError) -> Page<Product.Summary> {
        try await client.send(ProductEndpoint.products(page, sortedBy: sort))
    }

    func products(
        inCategory slug: String,
        _ page: PageRequest,
        sortedBy sort: Product.Sort?
    ) async throws(APIError) -> Page<Product.Summary> {
        try await client.send(ProductEndpoint.products(inCategory: slug, page, sortedBy: sort))
    }

    func search(
        _ text: String,
        _ page: PageRequest,
        sortedBy sort: Product.Sort?
    ) async throws(APIError) -> Page<Product.Summary> {
        try await client.send(ProductEndpoint.search(text, page, sortedBy: sort))
    }

    func categories() async throws(APIError) -> [Product.Category] {
        try await client.send(ProductEndpoint.categories)
    }

    func product(id: Int) async throws(APIError) -> Product {
        try await client.send(ProductEndpoint.product(id: id))
    }
}
