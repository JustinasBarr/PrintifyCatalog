import Foundation
import Networking
import Testing

@testable import Catalog

/// Models decode straight from recorded API answers; there is no mapping layer to test separately.
struct ProductDecodingTests {
    @Test func summaryPageDecodes() throws {
        let page = try Fixture.decode(Page<Product.Summary>.self, "products-summary-page")
        #expect(page.total == 194)
        #expect(page.skip == 0)
        #expect(page.limit == 3)
        #expect(page.items.map(\.id) == [1, 2, 3])
        #expect(
            page.items.first
                == Product.Summary(
                    id: 1,
                    title: "Essence Mascara Lash Princess",
                    price: Decimal(string: "9.99")!,
                    discountPercentage: 10.48,
                    rating: 2.56,
                    stock: 99,
                    availabilityStatus: "In Stock",
                    brand: "Essence",
                    category: "beauty",
                    thumbnail: URL(
                        string:
                            "https://cdn.dummyjson.com/product-images/beauty/essence-mascara-lash-princess/thumbnail.webp"
                    )!
                )
        )
    }

    @Test func fullProductDecodes() throws {
        let product = try Fixture.decode(Product.self, "product")
        #expect(product.id == 1)
        #expect(product.sku == "BEA-ESS-ESS-001")
        #expect(product.price == Decimal(string: "9.99"))
        #expect(product.stock == 99)
        #expect(product.availability == .inStock)
        #expect(product.tags == ["beauty", "mascara"])
        #expect(product.brand == "Essence")
        #expect(product.weight == 4)
        #expect(product.dimensions == Product.Dimensions(width: 15.14, height: 13.08, depth: 22.99))
        #expect(product.warrantyInformation == "1 week warranty")
        #expect(product.shippingInformation == "Ships in 3-5 business days")
        #expect(product.returnPolicy == "No return policy")
        #expect(product.minimumOrderQuantity == 48)
        #expect(product.meta.barcode == "5784719087687")
        #expect(product.meta.qrCode == URL(string: "https://cdn.dummyjson.com/public/qr-code.png"))
        #expect(product.images.count == 1)
        #expect(product.reviews.count == 3)
        #expect(product.reviews.first?.reviewerName == "Eleanor Collins")
        #expect(product.reviews.first?.rating == 3)
    }

    @Test func datesKeepTheirMilliseconds() throws {
        let product = try Fixture.decode(Product.self, "product")
        #expect(milliseconds(product.meta.createdAt) == 1_760_021_221_588)
        #expect(milliseconds(product.meta.updatedAt) == 1_779_535_661_868)
        #expect(product.reviews.first.map { milliseconds($0.date) } == 1_746_006_062_053)
    }

    @Test func datesWithoutMillisecondsDecodeToo() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        let date = try decoder.decode([Date].self, from: Data(#"["2025-10-09T14:47:01Z"]"#.utf8))
        #expect(date.map(milliseconds) == [1_760_021_221_000])
    }

    @Test func textThatIsNotADateFails() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        #expect(throws: DecodingError.self) {
            try decoder.decode([Date].self, from: Data(#"["yesterday"]"#.utf8))
        }
    }

    /// The list opens the detail on its own row, so both must say the same thing about a product.
    @Test func fullProductMakesTheSameSummaryAsTheList() throws {
        let product = try Fixture.decode(Product.self, "product")
        let page = try Fixture.decode(Page<Product.Summary>.self, "products-summary-page")
        #expect(product.summary == page.items.first)
    }

    @Test func productWithoutBrandDecodes() throws {
        let product = try Fixture.decode(Product.self, "product-without-brand")
        #expect(product.title == "Apple")
        #expect(product.category == "groceries")
        #expect(product.brand == nil)
        #expect(product.summary.brand == nil)
    }

    @Test func categoriesDecode() throws {
        let categories = try Fixture.decode([Product.Category].self, "categories")
        #expect(categories.count == 24)
        #expect(categories.first == Product.Category(slug: "beauty", name: "Beauty"))
    }

    @Test func searchPageDecodes() throws {
        let page = try Fixture.decode(Page<Product.Summary>.self, "search-page")
        #expect(page.total == 23)
        #expect(
            page.items.map(\.title) == [
                "Apple AirPods Max Silver", "Apple iPhone Charger", "Apple MagSafe Battery Pack",
            ]
        )
    }

    @Test func stockSortedPageHasEveryAvailability() throws {
        let page = try Fixture.decode(Page<Product.Summary>.self, "products-by-stock-page")
        #expect(page.items.map(\.stock) == page.items.map(\.stock).sorted())
        #expect(Set(page.items.map(\.availability)) == [.outOfStock, .lowStock, .inStock])
        #expect(page.items.filter(\.needsAttention).count == 13)
    }

    /// Stock 7 is "Low Stock" on one product and "In Stock" on another, so no stock threshold can be right.
    @Test func availabilityComesFromTheStatusNotAThreshold() throws {
        let page = try Fixture.decode(Page<Product.Summary>.self, "products-by-stock-page")
        let sevenLeft = page.items.filter { $0.stock == 7 }
        #expect(Set(sevenLeft.map(\.availability)) == [.lowStock, .inStock])
    }

    @Test(arguments: [
        (status: "In Stock", stock: 7, expected: Product.Availability.inStock),
        (status: "Low Stock", stock: 7, expected: .lowStock),
        (status: "Out of Stock", stock: 0, expected: .outOfStock),
        (status: "Backordered", stock: 0, expected: .outOfStock),
        (status: "", stock: 12, expected: .inStock),
    ])
    func availabilityFromStatus(status: String, stock: Int, expected: Product.Availability) throws {
        let json = #"""
            {"id":5,"title":"Mug","price":4.5,"discountPercentage":0,"rating":4,"stock":\#(stock),
            "availabilityStatus":"\#(status)","category":"kitchen-accessories","thumbnail":"https://cdn.example.com/5.webp"}
            """#
        let summary = try JSONDecoder().decode(Product.Summary.self, from: Data(json.utf8))
        #expect(summary.availability == expected)
        #expect(summary.needsAttention == (expected != .inStock))
    }

    /// The API's `price` is before the discount: its own carts charge `price × (1 − discountPercentage / 100)`.
    /// 2.50 at 7 % is exactly 2.325; worked out through a `Double` it is 2.3249… and loses a cent.
    @Test(arguments: [
        (price: "9.99", discount: 10.48, expected: "8.94"),
        (price: "100", discount: 25, expected: "75"),
        (price: "19.99", discount: 0, expected: "19.99"),
        (price: "9.99", discount: 0.04, expected: "9.99"),
        (price: "2.50", discount: 7, expected: "2.33"),
    ])
    func discountedPriceIsWhatTheCustomerPays(price: String, discount: Double, expected: String) {
        let summary = Product.Summary.sample(id: 1, price: Decimal(string: price)!, discountPercentage: discount)
        #expect(summary.discountedPrice == Decimal(string: expected))
    }

    private func milliseconds(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }
}
