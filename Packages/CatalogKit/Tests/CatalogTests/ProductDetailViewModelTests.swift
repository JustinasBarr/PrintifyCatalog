import Foundation
import Networking
import Testing

@testable import Catalog

/// Follows a merchant from the tap on a list row to the loaded page, through a lost connection and back.
@MainActor
struct ProductDetailViewModelTests {
    private typealias State = ProductDetailViewModel.State

    private let product: Product
    private let summary: Product.Summary

    init() throws {
        product = try Fixture.decode(Product.self, "product")
        summary = product.summary
    }

    // MARK: Loading

    /// The photo, name, price and stock draw in the first frame, from what the list already had.
    @Test func opensOnTheListSummary() {
        let viewModel = makeViewModel(answering: ScriptedProducts())
        #expect(viewModel.state == State(summary: summary, product: .loading))
    }

    @Test func loadFillsInTheFullProductByID() async {
        let products = ScriptedProducts(.success(product))
        let viewModel = makeViewModel(answering: products)
        await viewModel.load()
        #expect(viewModel.state == State(summary: summary, product: .loaded(product)))
        #expect(await products.requestedIDs == [product.id])
    }

    @Test func appearingAgainKeepsTheProductWithoutAskingAgain() async {
        let products = ScriptedProducts(.success(product))
        let viewModel = makeViewModel(answering: products)
        await viewModel.load()
        await viewModel.load()
        #expect(viewModel.state == State(summary: summary, product: .loaded(product)))
        #expect(await products.requestedIDs == [product.id])
    }

    // MARK: Failure and retry

    @Test(arguments: [APIError.offline, .unreachable, .server(status: 500), .decoding("price"), .transport("reset")])
    func failedLoadKeepsTheHeaderAndSaysWhatWentWrong(error: APIError) async {
        let viewModel = makeViewModel(answering: ScriptedProducts(.failure(error)))
        await viewModel.load()
        #expect(viewModel.state == State(summary: summary, product: .failed(error.message)))
    }

    @Test func retryAfterAFailureLoadsTheProduct() async {
        let products = ScriptedProducts(.failure(.offline), .success(product))
        let viewModel = makeViewModel(answering: products)
        await viewModel.load()
        await viewModel.retry()
        #expect(viewModel.state == State(summary: summary, product: .loaded(product)))
        #expect(await products.requestedIDs == [product.id, product.id])
    }

    /// "Try again" keeps the failure on screen, its button saying "Trying…", until the answer: no placeholder flash.
    @Test func retryKeepsTheFailureWhileItAsksAgain() async {
        let request = PendingAnswer<Product>()
        let viewModel = makeViewModel { _ throws(APIError) in try await request.value() }
        let firstLoad = Task { await viewModel.load() }
        await request.asked()
        await request.respond(.failure(.offline))
        await firstLoad.value

        let retry = Task { await viewModel.retry() }
        await request.asked()
        #expect(
            viewModel.state == State(summary: summary, product: .failed(APIError.offline.message), isRetrying: true)
        )
        await request.respond(.success(product))
        await retry.value
        #expect(viewModel.state == State(summary: summary, product: .loaded(product)))
    }

    // MARK: Cancellation

    /// Leaving the screen cancels its load; that is not a failure, and coming back loads again.
    @Test func cancelledLoadStaysLoadingAndLoadsOnReturn() async {
        let products = ScriptedProducts(.failure(.cancelled), .success(product))
        let viewModel = makeViewModel(answering: products)
        await viewModel.load()
        #expect(viewModel.state == State(summary: summary, product: .loading))
        await viewModel.load()
        #expect(viewModel.state == State(summary: summary, product: .loaded(product)))
    }

    @Test func cancelledRetryKeepsTheFailureOnScreen() async {
        let viewModel = makeViewModel(answering: ScriptedProducts(.failure(.offline), .failure(.cancelled)))
        await viewModel.load()
        await viewModel.retry()
        #expect(viewModel.state == State(summary: summary, product: .failed(APIError.offline.message)))
    }

    // MARK: What the page draws

    /// The list row can be minutes old; once the product arrives, its stock is the one a merchant acts on.
    @Test func headerIsTheListRowUntilTheFullProductArrives() {
        let listRow = Product.Summary.sample(id: product.id)
        #expect(State(summary: listRow, product: .loading).header == listRow)
        #expect(State(summary: listRow, product: .failed(APIError.offline.message)).header == listRow)
        #expect(State(summary: listRow, product: .loaded(product)).header == product.summary)
    }

    @Test func photosAreTheListThumbnailUntilTheProductBringsItsOwn() {
        let listRow = Product.Summary.sample(id: product.id)
        let photos = [
            URL(string: "https://cdn.example.com/1/1.webp")!, URL(string: "https://cdn.example.com/1/2.webp")!,
        ]
        #expect(State(summary: listRow, product: .loading).photos == [listRow.thumbnail])
        #expect(State(summary: listRow, product: .failed(APIError.offline.message)).photos == [listRow.thumbnail])
        #expect(State(summary: listRow, product: .loaded(product.with(images: photos))).photos == photos)
        #expect(State(summary: listRow, product: .loaded(product.with(images: []))).photos == [listRow.thumbnail])
    }

    @Test func reviewsAreNewestFirst() {
        let lastMonth = review(daysAgo: 30)
        let yesterday = review(daysAgo: 1)
        let lastYear = review(daysAgo: 365)
        let state = State(summary: summary, product: .loaded(product.with(reviews: [lastMonth, yesterday, lastYear])))
        #expect(state.reviews == [yesterday, lastMonth, lastYear])
    }

    /// The API gives every review of a product the same date, so the API's own order is what a merchant sees.
    @Test func reviewsFromTheSameMomentKeepTheAPIsOrder() {
        #expect(State(summary: summary, product: .loaded(product)).reviews == product.reviews)
    }

    @Test func noReviewsUntilTheProductArrives() {
        #expect(State(summary: summary, product: .loading).reviews == [])
        #expect(State(summary: summary, product: .failed(APIError.offline.message)).reviews == [])
    }

    // MARK: Restock

    @Test func restockOpensOnTheStockOnScreenWithTen() async {
        let viewModel = await loadedViewModel()
        viewModel.startRestock()
        #expect(
            viewModel.state
                == State(summary: summary, product: .loaded(product), restock: Restock(stock: 99, quantity: 10))
        )
    }

    /// The list row's stock is on screen before the product arrives, so a restock can start from it.
    @Test func restockBeforeTheProductArrivesStartsFromTheListRow() {
        let viewModel = makeViewModel(answering: ScriptedProducts())
        viewModel.startRestock()
        #expect(viewModel.state == State(summary: summary, product: .loading, restock: Restock(stock: 99)))
    }

    @Test(arguments: [(0, 1), (1, 1), (25, 25), (999, 999), (1000, 999)])
    func quantityStaysBetweenOneAnd999(asked: Int, kept: Int) async {
        let viewModel = await loadedViewModel()
        viewModel.startRestock()
        viewModel.changeRestockQuantity(to: asked)
        #expect(
            viewModel.state
                == State(summary: summary, product: .loaded(product), restock: Restock(stock: 99, quantity: kept))
        )
    }

    @Test func confirmSendsTheNewStockAndClosesTheSheet() async {
        let stock = ScriptedStock(.success(124))
        let viewModel = await loadedViewModel(stock: stock)
        viewModel.startRestock()
        viewModel.changeRestockQuantity(to: 25)
        await viewModel.confirmRestock()
        #expect(viewModel.state == State(summary: summary, product: .loaded(product), restockedStock: 124))
        #expect(await stock.requests == [.init(id: product.id, stock: 124)])
    }

    /// Confirm shows progress and cannot be sent twice while the server answers.
    @Test func confirmIsSendingUntilTheServerAnswers() async {
        let request = PendingAnswer<Int>()
        let viewModel = await loadedViewModel { _, _ throws(APIError) in try await request.value() }
        viewModel.startRestock()
        let confirm = Task { await viewModel.confirmRestock() }
        await request.asked()
        #expect(
            viewModel.state
                == State(summary: summary, product: .loaded(product), restock: Restock(stock: 99, status: .sending))
        )
        await request.respond(.success(109))
        await confirm.value
        #expect(viewModel.state == State(summary: summary, product: .loaded(product), restockedStock: 109))
    }

    @Test func failedRestockKeepsTheSheetOpenAndSaysWhy() async {
        let viewModel = await loadedViewModel(stock: ScriptedStock(.failure(.offline)))
        viewModel.startRestock()
        await viewModel.confirmRestock()
        let failed = Restock(stock: 99, status: .failed(APIError.offline.message))
        #expect(viewModel.state == State(summary: summary, product: .loaded(product), restock: failed))
    }

    @Test func confirmingAgainAfterAFailureRestocks() async {
        let stock = ScriptedStock(.failure(.offline), .success(109))
        let viewModel = await loadedViewModel(stock: stock)
        viewModel.startRestock()
        await viewModel.confirmRestock()
        await viewModel.confirmRestock()
        #expect(viewModel.state == State(summary: summary, product: .loaded(product), restockedStock: 109))
        #expect(await stock.requests == [.init(id: product.id, stock: 109), .init(id: product.id, stock: 109)])
    }

    /// A cancelled request is the screen going away, not a failure: the sheet stays as it was.
    @Test func cancelledRestockRequestLeavesTheSheetAsItWas() async {
        let viewModel = await loadedViewModel(stock: ScriptedStock(.failure(.cancelled)))
        viewModel.startRestock()
        await viewModel.confirmRestock()
        #expect(viewModel.state == State(summary: summary, product: .loaded(product), restock: Restock(stock: 99)))
    }

    @Test func cancelClosesTheSheetWithoutSending() async {
        let stock = ScriptedStock()
        let viewModel = await loadedViewModel(stock: stock)
        viewModel.startRestock()
        viewModel.changeRestockQuantity(to: 25)
        viewModel.cancelRestock()
        #expect(viewModel.state == State(summary: summary, product: .loaded(product)))
        #expect(await stock.requests == [])
    }

    @Test func aSecondRestockStartsFromTheRestockedStock() async {
        let viewModel = await loadedViewModel(stock: ScriptedStock(.success(109)))
        viewModel.startRestock()
        await viewModel.confirmRestock()
        viewModel.startRestock()
        #expect(
            viewModel.state
                == State(
                    summary: summary,
                    product: .loaded(product),
                    restockedStock: 109,
                    restock: Restock(stock: 109)
                )
        )
    }

    /// The chip shows the new count and the status that goes with it, before and after the product arrives.
    @Test func headerShowsTheRestockedStockAndItsStatus() {
        let lowRow = Product.Summary.sample(id: product.id, stock: 5, availabilityStatus: "Low Stock")
        #expect(
            State(summary: lowRow, product: .loading, restockedStock: 15).header
                == .sample(id: product.id, stock: 15, availabilityStatus: "In Stock")
        )
        let loaded = State(summary: summary, product: .loaded(product), restockedStock: 3).header
        #expect(loaded.stock == 3)
        #expect(loaded.availabilityStatus == "Low Stock")
        #expect(loaded.title == product.title)
    }

    // MARK: Helpers

    private typealias Restock = ProductDetailViewModel.Restock

    /// Built the way the app builds it: through the feature, over a repository.
    private func makeViewModel(
        answering answer: @escaping @Sendable (Int) async throws(APIError) -> Product,
        updatingStock updateStock: @escaping @Sendable (Int, Int) async throws(APIError) -> Int = {
            _,
            _ throws(APIError) in throw APIError.offline
        }
    ) -> ProductDetailViewModel {
        var repository = FakeProductRepository()
        repository.onProduct = answer
        repository.onUpdateStock = updateStock
        return CatalogFeature(repository: repository).makeProductDetail(for: summary)
    }

    private func makeViewModel(answering products: ScriptedProducts) -> ProductDetailViewModel {
        makeViewModel { id throws(APIError) in try await products.answer(id) }
    }

    /// The screen with the recorded product on it, whose stock changes answer `updateStock`.
    private func loadedViewModel(
        updatingStock updateStock: @escaping @Sendable (Int, Int) async throws(APIError) -> Int
    ) async -> ProductDetailViewModel {
        let viewModel = makeViewModel(
            answering: { [product] _ throws(APIError) in product },
            updatingStock: updateStock
        )
        await viewModel.load()
        return viewModel
    }

    private func loadedViewModel(stock: ScriptedStock = ScriptedStock()) async -> ProductDetailViewModel {
        await loadedViewModel { id, new throws(APIError) in try await stock.answer(id: id, stock: new) }
    }

    private func review(daysAgo days: Int) -> Product.Review {
        let reviewed = Date(timeIntervalSince1970: 1_760_000_000).addingTimeInterval(-Double(days) * 86_400)
        return Product.Review(rating: 4, comment: "\(days) days ago", date: reviewed, reviewerName: "Reviewer \(days)")
    }
}

/// Answers each product request with the next scripted result and remembers which ids were asked for.
private actor ScriptedProducts {
    private var results: [Result<Product, APIError>]
    private(set) var requestedIDs: [Int] = []

    init(_ results: Result<Product, APIError>...) {
        self.results = results
    }

    func answer(_ id: Int) throws(APIError) -> Product {
        requestedIDs.append(id)
        guard !results.isEmpty else { throw .transport("No scripted answer for request \(requestedIDs.count)") }
        return try results.removeFirst().get()
    }
}

/// Answers stock updates in order and remembers what was sent.
private actor ScriptedStock {
    struct Request: Equatable {
        let id: Int
        let stock: Int
    }

    private var results: [Result<Int, APIError>]
    private(set) var requests: [Request] = []

    init(_ results: Result<Int, APIError>...) {
        self.results = results
    }

    func answer(id: Int, stock: Int) throws(APIError) -> Int {
        requests.append(Request(id: id, stock: stock))
        guard !results.isEmpty else { throw .transport("No scripted answer for update \(requests.count)") }
        return try results.removeFirst().get()
    }
}

extension Product {
    /// The recorded product with other reviews or photos, for cases the recorded answer doesn't have.
    fileprivate func with(reviews: [Review]? = nil, images: [URL]? = nil) -> Product {
        Product(
            id: id,
            title: title,
            description: description,
            category: category,
            price: price,
            discountPercentage: discountPercentage,
            rating: rating,
            stock: stock,
            tags: tags,
            brand: brand,
            sku: sku,
            weight: weight,
            dimensions: dimensions,
            warrantyInformation: warrantyInformation,
            shippingInformation: shippingInformation,
            availabilityStatus: availabilityStatus,
            reviews: reviews ?? self.reviews,
            returnPolicy: returnPolicy,
            minimumOrderQuantity: minimumOrderQuantity,
            meta: meta,
            images: images ?? self.images,
            thumbnail: thumbnail
        )
    }
}
