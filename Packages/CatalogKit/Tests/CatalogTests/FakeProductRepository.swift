import Networking

@testable import Catalog

/// A repository whose answers each test sets. Every call fails as offline unless the test says otherwise, so a
/// test states only the calls it expects.
struct FakeProductRepository: ProductRepositoryProtocol {
    var onProducts: @Sendable (PageRequest, Product.Sort?) async throws(APIError) -> Page<Product.Summary> = {
        _,
        _ throws(APIError) in throw APIError.offline
    }
    var onCategoryProducts:
        @Sendable (String, PageRequest, Product.Sort?) async throws(APIError) -> Page<Product.Summary> = {
            _,
            _,
            _ throws(APIError) in throw APIError.offline
        }
    var onSearch: @Sendable (String, PageRequest, Product.Sort?) async throws(APIError) -> Page<Product.Summary> = {
        _,
        _,
        _ throws(APIError) in throw APIError.offline
    }
    var onCategories: @Sendable () async throws(APIError) -> [Product.Category] = { () throws(APIError) in
        throw APIError.offline
    }
    var onProduct: @Sendable (Int) async throws(APIError) -> Product = { _ throws(APIError) in throw APIError.offline }
    var onUpdateStock: @Sendable (Int, Int) async throws(APIError) -> Int = { _, _ throws(APIError) in
        throw APIError.offline
    }

    func products(_ page: PageRequest, sortedBy sort: Product.Sort?) async throws(APIError) -> Page<Product.Summary> {
        try await onProducts(page, sort)
    }

    func products(
        inCategory slug: String,
        _ page: PageRequest,
        sortedBy sort: Product.Sort?
    ) async throws(APIError) -> Page<Product.Summary> {
        try await onCategoryProducts(slug, page, sort)
    }

    func search(
        _ text: String,
        _ page: PageRequest,
        sortedBy sort: Product.Sort?
    ) async throws(APIError) -> Page<Product.Summary> {
        try await onSearch(text, page, sort)
    }

    func categories() async throws(APIError) -> [Product.Category] {
        try await onCategories()
    }

    func product(id: Int) async throws(APIError) -> Product {
        try await onProduct(id)
    }

    func updateStock(id: Int, stock: Int) async throws(APIError) -> Int {
        try await onUpdateStock(id, stock)
    }
}
