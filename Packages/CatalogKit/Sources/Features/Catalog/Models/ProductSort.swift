extension Product {
    /// The orders a list can ask the server for. A new order is a case plus its `sortBy` and `order`.
    enum Sort: CaseIterable, Sendable {
        case stockLowFirst
        case priceLowToHigh
        case priceHighToLow
        case ratingHighFirst
        case nameAToZ

        /// The API field to sort on.
        var sortBy: String {
            switch self {
            case .stockLowFirst: "stock"
            case .priceLowToHigh, .priceHighToLow: "price"
            case .ratingHighFirst: "rating"
            case .nameAToZ: "title"
            }
        }

        var order: String {
            switch self {
            case .stockLowFirst, .priceLowToHigh, .nameAToZ: "asc"
            case .priceHighToLow, .ratingHighFirst: "desc"
            }
        }
    }
}
