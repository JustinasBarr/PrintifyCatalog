import Foundation
import Networking

/// Every request the catalog makes. Lists ask only for the row's fields (`select=`), so a page of 48 is a
/// few kilobytes instead of every review and image.
enum ProductEndpoint {
    static let categories = Endpoint<[Product.Category]>(path: "products/categories")

    static func products(_ page: PageRequest, sortedBy sort: Product.Sort?) -> Endpoint<Page<Product.Summary>> {
        Endpoint(path: "products", query: listQuery(page, sort))
    }

    static func products(
        inCategory slug: String,
        _ page: PageRequest,
        sortedBy sort: Product.Sort?
    ) -> Endpoint<Page<Product.Summary>> {
        Endpoint(path: "products/category/\(slug)", query: listQuery(page, sort))
    }

    /// Matches product names; the API cannot search SKUs.
    static func search(
        _ text: String,
        _ page: PageRequest,
        sortedBy sort: Product.Sort?
    ) -> Endpoint<Page<Product.Summary>> {
        Endpoint(path: "products/search", query: [URLQueryItem(name: "q", value: text)] + listQuery(page, sort))
    }

    static func product(id: Int) -> Endpoint<Product> {
        Endpoint(path: "products/\(id)")
    }

    /// Sends only the new stock. The answer is the product without its status, reviews or SKU, so only the stock
    /// is read back.
    static func updateStock(id: Int, stock: Int) -> Endpoint<StockUpdate> {
        Endpoint(path: "products/\(id)", method: .put, body: try? JSONEncoder().encode(StockUpdate(stock: stock)))
    }

    struct StockUpdate: Codable, Sendable {
        let stock: Int
    }
}

/// Paging, then the optional order, then the row's fields.
private func listQuery(_ page: PageRequest, _ sort: Product.Sort?) -> [URLQueryItem] {
    var query = page.query
    if let sort {
        query += [URLQueryItem(name: "sortBy", value: sort.sortBy), URLQueryItem(name: "order", value: sort.order)]
    }
    return query + [rowFields]
}

private let rowFields = URLQueryItem(
    name: "select",
    value: Product.Summary.CodingKeys.allCases.map(\.rawValue).joined(separator: ",")
)
