import Foundation

/// One page of a list, as the API sends it: `{ products, total, skip, limit }`.
struct Page<Item: Hashable & Codable & Sendable>: Hashable, Codable, Sendable {
    let items: [Item]
    /// Every item the list has on the server, across all pages.
    let total: Int
    let skip: Int
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case items = "products", total, skip, limit
    }
}

/// Which slice of a list to ask for.
struct PageRequest: Hashable, Sendable {
    let limit: Int
    let skip: Int

    var query: [URLQueryItem] {
        [URLQueryItem(name: "limit", value: "\(limit)"), URLQueryItem(name: "skip", value: "\(skip)")]
    }
}
