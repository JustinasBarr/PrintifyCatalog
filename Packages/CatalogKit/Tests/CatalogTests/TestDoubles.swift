import Foundation
import Networking
import Testing

@testable import Catalog

/// Answers recorded from the live API on 2026-11-08 with curl; nothing in them is hand-edited.
enum Fixture {
    static func decode<Value: Decodable>(_ type: Value.Type, _ name: String) throws -> Value {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return try decoder.decode(Value.self, from: Data(contentsOf: url))
    }
}

extension Product.Summary {
    static func sample(
        id: Int,
        price: Decimal = 10,
        discountPercentage: Double = 0,
        stock: Int = 20,
        availabilityStatus: String = "In Stock"
    ) -> Product.Summary {
        Product.Summary(
            id: id,
            title: "Product \(id)",
            price: price,
            discountPercentage: discountPercentage,
            rating: 4,
            stock: stock,
            availabilityStatus: availabilityStatus,
            brand: nil,
            category: "beauty",
            thumbnail: URL(string: "https://cdn.example.com/\(id).webp")!
        )
    }
}

/// A page of samples with ids `skip..<skip + count`, out of `total`.
func samplePage(skip: Int, count: Int, total: Int) -> Page<Product.Summary> {
    Page(items: (skip..<skip + count).map { Product.Summary.sample(id: $0) }, total: total, skip: skip, limit: count)
}

/// A request that waits until the test answers it, so a test can look at the page mid-request.
actor PendingAnswer<Value: Sendable> {
    private var answer: CheckedContinuation<Result<Value, APIError>, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    func value() async throws(APIError) -> Value {
        let result = await withCheckedContinuation { continuation in
            answer = continuation
            arrival?.resume()
            arrival = nil
        }
        return try result.get()
    }

    /// Returns once the page has sent the request.
    func asked() async {
        guard answer == nil else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func respond(_ result: Result<Value, APIError>) {
        answer?.resume(returning: result)
        answer = nil
    }
}
