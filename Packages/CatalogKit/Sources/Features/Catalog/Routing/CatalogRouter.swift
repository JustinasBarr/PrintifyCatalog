import Observation
import SwiftUI

/// Where the catalog is: the pushed lists and the presented product. Views ask the router to move;
/// `CatalogRootView` builds the screens.
@MainActor
@Observable
final class CatalogRouter {
    var path: [Route] = []
    var presented: Presented?

    func show(_ route: Route) {
        path.append(route)
    }

    /// `source` is the namespace of the shelf or grid that owns the tapped cell, so the detail zooms back into
    /// that cell even when the same product also sits on another shelf.
    func present(_ product: Product.Summary, from source: Namespace.ID) {
        presented = Presented(product: product, source: source)
    }

    enum Route: Hashable, Sendable {
        case category(Product.Category)
        /// Low and out of stock, lowest stock first.
        case attention
    }

    struct Presented: Identifiable {
        let product: Product.Summary
        let source: Namespace.ID

        var id: Int { product.id }
    }
}
