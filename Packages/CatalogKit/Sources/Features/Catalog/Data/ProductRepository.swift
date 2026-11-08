import Networking

/// Where catalog screens get products. The app uses `ProductRepository`; tests use a fake.
protocol ProductRepositoryProtocol: Sendable {
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
    /// Sets a product's stock and returns the stock the server confirmed.
    func updateStock(id: Int, stock: Int) async throws(APIError) -> Int
}

/// The catalog from the DummyJSON products API (https://dummyjson.com/docs/products) through `client`.
struct ProductRepository: ProductRepositoryProtocol {
    private let client: APIClient
    private let restockedStock = RestockedStock()

    init(client: APIClient) {
        self.client = client
    }

    func products(_ page: PageRequest, sortedBy sort: Product.Sort?) async throws(APIError) -> Page<Product.Summary> {
        try await restockedStock.applied(to: client.send(ProductEndpoint.products(page, sortedBy: sort)))
    }

    func products(
        inCategory slug: String,
        _ page: PageRequest,
        sortedBy sort: Product.Sort?
    ) async throws(APIError) -> Page<Product.Summary> {
        try await restockedStock.applied(
            to: client.send(ProductEndpoint.products(inCategory: slug, page, sortedBy: sort))
        )
    }

    func search(
        _ text: String,
        _ page: PageRequest,
        sortedBy sort: Product.Sort?
    ) async throws(APIError) -> Page<Product.Summary> {
        try await restockedStock.applied(to: client.send(ProductEndpoint.search(text, page, sortedBy: sort)))
    }

    func categories() async throws(APIError) -> [Product.Category] {
        try await client.send(ProductEndpoint.categories)
    }

    func product(id: Int) async throws(APIError) -> Product {
        try await restockedStock.applied(to: client.send(ProductEndpoint.product(id: id)))
    }

    func updateStock(id: Int, stock: Int) async throws(APIError) -> Int {
        let confirmed = try await client.send(ProductEndpoint.updateStock(id: id, stock: stock)).stock
        await restockedStock.remember(confirmed, for: id)
        return confirmed
    }
}

/// Stock the merchant set in this session. The server answers an update but never stores it, so every later
/// product and page still carries the old stock; and its answer has no status, so `restocked(to:)` sets one.
private actor RestockedStock {
    private var stockByID: [Int: Int] = [:]

    func remember(_ stock: Int, for id: Int) {
        stockByID[id] = stock
    }

    func applied(to product: Product) -> Product {
        stockByID[product.id].map(product.restocked(to:)) ?? product
    }

    func applied(to page: Page<Product.Summary>) -> Page<Product.Summary> {
        let items = page.items.map { summary in stockByID[summary.id].map(summary.restocked(to:)) ?? summary }
        return Page(items: items, total: page.total, skip: page.skip, limit: page.limit)
    }
}
