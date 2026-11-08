import Foundation
import Networking
import Observation

/// One product, as a merchant checks it. It opens on the list's summary, so the photo, name, price and stock
/// draw at once, and the full product fills in by id.
@MainActor
@Observable
final class ProductDetailViewModel {
    struct State: Equatable {
        /// What the list showed.
        let summary: Product.Summary
        var product: Loadable<Product> = .loading
        /// The stock the merchant set on this screen, once the server has confirmed it.
        var restockedStock: Int?
        /// The restock sheet, while it is open.
        var restock: Restock?

        /// The full product's once it arrives (its stock may have moved since the list loaded), else the list's,
        /// with the stock the merchant set on top.
        var header: Product.Summary {
            let header = product.value?.summary ?? summary
            return restockedStock.map(header.restocked(to:)) ?? header
        }

        /// The list's thumbnail until the full product brings its photos.
        var photos: [URL] {
            guard let images = product.value?.images, !images.isEmpty else { return [summary.thumbnail] }
            return images
        }

        /// Newest first: what customers say now matters more than what they said a year ago.
        var reviews: [Product.Review] {
            product.value?.reviews.sorted { $0.date > $1.date } ?? []
        }
    }

    /// The quantity the merchant adds to the stock on screen.
    struct Restock: Equatable {
        enum Status: Equatable {
            case ready
            case sending
            case failed(String)
        }

        static let quantities = 1...999

        /// The stock on screen when the sheet opened.
        let stock: Int
        var quantity = 10
        var status = Status.ready

        var newStock: Int { stock + quantity }
    }

    typealias LoadProduct = @Sendable (Int) async throws(APIError) -> Product
    typealias UpdateStock = @Sendable (_ id: Int, _ stock: Int) async throws(APIError) -> Int

    private(set) var state: State
    private let loadProduct: LoadProduct
    private let updateStock: UpdateStock

    init(summary: Product.Summary, loadProduct: @escaping LoadProduct, updateStock: @escaping UpdateStock) {
        self.loadProduct = loadProduct
        self.updateStock = updateStock
        state = State(summary: summary)
    }

    /// Fetches the full product. A screen that appears again keeps the product it already has.
    func load() async {
        guard state.product.value == nil else { return }
        await fetchProduct()
    }

    func retry() async {
        await fetchProduct()
    }

    func startRestock() {
        state.restock = Restock(stock: state.header.stock)
    }

    func changeRestockQuantity(to quantity: Int) {
        state.restock?.quantity = min(max(quantity, Restock.quantities.lowerBound), Restock.quantities.upperBound)
    }

    func cancelRestock() {
        state.restock = nil
    }

    /// Sends the new stock. A failure keeps the sheet open with the reason; a cancelled request leaves it as it was.
    func confirmRestock() async {
        guard let restock = state.restock, restock.status != .sending else { return }
        state.restock?.status = .sending
        do throws(APIError) {
            state.restockedStock = try await updateStock(state.summary.id, restock.newStock)
            state.restock = nil
        } catch .cancelled {
            state.restock?.status = restock.status
        } catch {
            state.restock?.status = .failed(error.message)
        }
    }

    private func fetchProduct() async {
        let previous = state.product
        state.product = .loading
        do throws(APIError) {
            state.product = .loaded(try await loadProduct(state.summary.id))
        } catch .cancelled {
            state.product = previous
        } catch {
            state.product = .failed(error.message)
        }
    }
}
