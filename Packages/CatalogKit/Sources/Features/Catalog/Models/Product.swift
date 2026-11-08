import Foundation

/// The full product from `GET /products/{id}`, decoded with the API's own names.
struct Product: Identifiable, Hashable, Codable, Sendable, Product.PriceAndStock {
    let id: Int
    let title: String
    let description: String
    let category: String
    /// Before the discount; `discountedPrice` is what a customer pays.
    let price: Decimal
    let discountPercentage: Double
    let rating: Double
    let stock: Int
    let tags: [String]
    /// Missing on about half the catalog (groceries, furniture); screens show the category instead.
    let brand: String?
    let sku: String
    /// The API gives no unit, so none is shown.
    let weight: Double
    let dimensions: Dimensions
    let warrantyInformation: String
    let shippingInformation: String
    let availabilityStatus: String
    let reviews: [Review]
    let returnPolicy: String
    let minimumOrderQuantity: Int
    let meta: Meta
    let images: [URL]
    let thumbnail: URL

    /// The list row for this product, so a detail opened from anywhere says what the list says.
    var summary: Summary {
        Summary(
            id: id,
            title: title,
            price: price,
            discountPercentage: discountPercentage,
            rating: rating,
            stock: stock,
            availabilityStatus: availabilityStatus,
            brand: brand,
            category: category,
            thumbnail: thumbnail
        )
    }
}

extension Product {
    /// What a list row shows. Its coding keys are also the list request's `select=`, so a new row field is
    /// one property and one case here.
    struct Summary: Identifiable, Hashable, Codable, Sendable, PriceAndStock {
        let id: Int
        let title: String
        let price: Decimal
        let discountPercentage: Double
        let rating: Double
        let stock: Int
        let availabilityStatus: String
        let brand: String?
        let category: String
        let thumbnail: URL

        enum CodingKeys: String, CodingKey, CaseIterable {
            case id, title, price, discountPercentage, rating, stock, availabilityStatus, brand, category, thumbnail
        }
    }

    struct Category: Identifiable, Hashable, Codable, Sendable {
        let slug: String
        let name: String

        var id: String { slug }
    }

    enum Availability: Hashable, Sendable {
        case inStock
        case lowStock
        case outOfStock
    }

    /// The reviewer's email is in the API too; it is not decoded, so no screen can show it.
    struct Review: Hashable, Codable, Sendable {
        let rating: Int
        let comment: String
        let date: Date
        let reviewerName: String
    }

    /// The API gives no unit, so none is shown.
    struct Dimensions: Hashable, Codable, Sendable {
        let width: Double
        let height: Double
        let depth: Double
    }

    struct Meta: Hashable, Codable, Sendable {
        let createdAt: Date
        let updatedAt: Date
        let barcode: String
        let qrCode: URL
    }

    /// What `Product` and `Summary` share, so price and stock read the same in the list and the detail.
    protocol PriceAndStock {
        var price: Decimal { get }
        var discountPercentage: Double { get }
        var stock: Int { get }
        var availabilityStatus: String { get }
    }
}

extension Product.PriceAndStock {
    /// From the API's own status, not a stock threshold: the API calls 7 left "Low Stock" on one product and
    /// "In Stock" on another. A status it adds later falls back to the count.
    var availability: Product.Availability {
        switch availabilityStatus {
        case "In Stock": .inStock
        case "Low Stock": .lowStock
        case "Out of Stock": .outOfStock
        default: stock > 0 ? .inStock : .outOfStock
        }
    }

    /// Low or out of stock: what a merchant acts on first.
    var needsAttention: Bool { availability != .inStock }

    /// What a customer pays, to the cent. The API's carts charge `price × (1 − discountPercentage / 100)`.
    var discountedPrice: Decimal {
        // `description` is the shortest text that reads back as this Double: the API's own digits, without the
        // binary error that would make 2.50 at 7 % (exactly 2.325) round down a cent.
        let percent = Decimal(string: discountPercentage.description) ?? Decimal(discountPercentage)
        var exact = price * (100 - percent) / 100
        var cents = Decimal()
        NSDecimalRound(&cents, &exact, 2, .plain)
        return cents
    }
}
