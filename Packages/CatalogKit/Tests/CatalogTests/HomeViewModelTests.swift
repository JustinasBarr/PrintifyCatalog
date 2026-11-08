import Networking
import Testing

@testable import Catalog

@MainActor
struct HomeViewModelTests {
    private typealias State = HomeViewModel.State
    private typealias Attention = HomeViewModel.Attention

    @Test func loadShowsCategoriesWhatNeedsAttentionAndTheProductCount() async throws {
        let stockPage = try Fixture.decode(Page<Product.Summary>.self, "products-by-stock-page")
        var repository = homeRepository()
        repository.onProducts = { _, sort async throws(APIError) in
            // Only the lowest stock first can hold every product that needs attention.
            guard sort == .stockLowFirst else { throw APIError.invalidRequest }
            return stockPage
        }
        let viewModel = HomeViewModel(repository: repository)

        await viewModel.load()

        // The page's last two rows both have 7 left; the API calls one "Low Stock" and the other (id 58)
        // "In Stock", so only the status decides.
        let lowAndOut = stockPage.items.filter { $0.id != 58 }
        #expect(
            viewModel.state
                == State(
                    categories: .loaded([beauty, groceries]),
                    attention: .loaded(Attention(products: lowAndOut, mayHaveMore: false)),
                    productCount: 194
                )
        )
    }

    /// Every row checked needed attention, so the header shows a count with "+".
    @Test func attentionMayHaveMoreWhenEveryRowCheckedNeedsIt() async throws {
        let stockPage = try Fixture.decode(Page<Product.Summary>.self, "products-by-stock-page")
        let lowAndOut = Array(stockPage.items.prefix(13))
        var repository = homeRepository()
        repository.onProducts = { _, _ in Page(items: lowAndOut, total: 194, skip: 0, limit: 13) }
        let viewModel = HomeViewModel(repository: repository)

        await viewModel.load()

        #expect(viewModel.state == shownState(attention: Attention(products: lowAndOut, mayHaveMore: true)))
    }

    @Test func attentionIsEmptyWhenEverythingIsInStock() async {
        let viewModel = HomeViewModel(repository: homeRepository())

        await viewModel.load()

        #expect(viewModel.state == shownState(attention: Attention(products: [], mayHaveMore: false)))
    }

    /// A shelf asks for its first page only when it scrolls in, and only once.
    @Test func aShelfLoadsOnceWhenItAppears() async {
        let shelfCalls = CallCount()
        var repository = homeRepository()
        repository.onCategoryProducts = { _, _, _ in
            await shelfCalls.next()
            return beautyShelf
        }
        let viewModel = HomeViewModel(repository: repository)

        await viewModel.load()
        #expect(viewModel.state == shownState(shelves: [:]))
        #expect(await shelfCalls.value == 0)

        await viewModel.shelfAppeared(beauty)
        await viewModel.shelfAppeared(beauty)

        #expect(viewModel.state == shownState(shelves: ["beauty": .loaded(beautyShelf)]))
        #expect(await shelfCalls.value == 1)
    }

    @Test func oneShelfFailingLeavesTheOthers() async {
        var repository = homeRepository()
        repository.onCategoryProducts = { slug, _, _ async throws(APIError) in
            guard slug == beauty.slug else { throw APIError.server(status: 503) }
            return beautyShelf
        }
        let viewModel = HomeViewModel(repository: repository)
        await viewModel.load()

        await viewModel.shelfAppeared(beauty)
        await viewModel.shelfAppeared(groceries)

        #expect(
            viewModel.state
                == shownState(shelves: [
                    "beauty": .loaded(beautyShelf),
                    "groceries": .failed(APIError.server(status: 503).message),
                ])
        )
    }

    @Test func retryLoadsHomeAgainAfterItFailed() async {
        let categoryCalls = CallCount()
        var repository = homeRepository()
        repository.onCategories = { () async throws(APIError) in
            if await categoryCalls.next() == 0 { throw APIError.offline }
            return [beauty, groceries]
        }
        let viewModel = HomeViewModel(repository: repository)

        await viewModel.load()
        #expect(
            viewModel.state
                == State(
                    categories: .failed(APIError.offline.message),
                    attention: .loaded(Attention(products: [], mayHaveMore: false)),
                    productCount: 194
                )
        )

        await viewModel.retry()

        #expect(viewModel.state == shownState())
    }

    /// "Try again" keeps the failure on screen, its button saying "Trying…", until the answer: no skeleton flash.
    @Test func retryKeepsTheFailureWhileItAsksAgain() async {
        let categories = PendingAnswer<[Product.Category]>()
        var repository = homeRepository()
        repository.onCategories = { () async throws(APIError) in try await categories.value() }
        let viewModel = HomeViewModel(repository: repository)
        let firstLoad = Task { await viewModel.load() }
        await categories.asked()
        await categories.respond(.failure(.offline))
        await firstLoad.value
        var failed = State(
            categories: .failed(APIError.offline.message),
            attention: .loaded(Attention(products: [], mayHaveMore: false)),
            productCount: 194
        )
        #expect(viewModel.state == failed)

        let retry = Task { await viewModel.retry() }
        await categories.asked()
        failed.isRetrying = true
        #expect(viewModel.state == failed)
        await categories.respond(.success([beauty, groceries]))
        await retry.value
        #expect(viewModel.state == shownState())
    }

    @Test func retryShelfLoadsAFailedShelf() async {
        let shelfCalls = CallCount()
        var repository = homeRepository()
        repository.onCategoryProducts = { _, _, _ async throws(APIError) in
            if await shelfCalls.next() == 0 { throw APIError.unreachable }
            return beautyShelf
        }
        let viewModel = HomeViewModel(repository: repository)
        await viewModel.load()
        await viewModel.shelfAppeared(beauty)
        #expect(viewModel.state == shownState(shelves: ["beauty": .failed(APIError.unreachable.message)]))

        await viewModel.retryShelf(beauty)

        #expect(viewModel.state == shownState(shelves: ["beauty": .loaded(beautyShelf)]))
    }

    /// The attention page also carries the catalog's total, so a retried page fills in the search field's count.
    @Test func retryAttentionLoadsTheAttentionShelf() async {
        let attentionCalls = CallCount()
        var repository = homeRepository()
        repository.onProducts = { _, _ async throws(APIError) in
            if await attentionCalls.next() == 0 { throw APIError.offline }
            return samplePage(skip: 0, count: 48, total: 194)
        }
        let viewModel = HomeViewModel(repository: repository)
        await viewModel.load()
        #expect(
            viewModel.state
                == State(categories: .loaded([beauty, groceries]), attention: .failed(APIError.offline.message))
        )

        await viewModel.retryAttention()

        #expect(viewModel.state == shownState())
    }

    /// Leaving Home while it loads cancels the requests: the screen keeps loading, never shows an error.
    @Test func aCancelledFirstLoadIsNeverAFailure() async {
        var repository = FakeProductRepository()
        repository.onCategories = { () async throws(APIError) in throw APIError.cancelled }
        repository.onProducts = { _, _ async throws(APIError) in throw APIError.cancelled }
        let viewModel = HomeViewModel(repository: repository)

        await viewModel.load()

        #expect(viewModel.state == State())
    }

    /// A cancelled "Try again" brings the error and its button back, not a skeleton with no request behind it.
    @Test func aCancelledRetryRestoresTheFailure() async {
        let categoryCalls = CallCount()
        var repository = homeRepository()
        repository.onCategories = { () async throws(APIError) in
            let call = await categoryCalls.next()
            throw call == 0 ? APIError.offline : APIError.cancelled
        }
        let viewModel = HomeViewModel(repository: repository)
        let failed = State(
            categories: .failed(APIError.offline.message),
            attention: .loaded(Attention(products: [], mayHaveMore: false)),
            productCount: 194
        )
        await viewModel.load()
        #expect(viewModel.state == failed)

        await viewModel.retry()

        #expect(viewModel.state == failed)
    }

    /// Scrolling a shelf away cancels its request; it loads when it next scrolls in.
    @Test func aCancelledShelfLoadsWhenItNextAppears() async {
        let shelfCalls = CallCount()
        var repository = homeRepository()
        repository.onCategoryProducts = { _, _, _ async throws(APIError) in
            if await shelfCalls.next() == 0 { throw APIError.cancelled }
            return beautyShelf
        }
        let viewModel = HomeViewModel(repository: repository)
        await viewModel.load()

        await viewModel.shelfAppeared(beauty)
        #expect(viewModel.state == shownState(shelves: [:]))

        await viewModel.shelfAppeared(beauty)
        #expect(viewModel.state == shownState(shelves: ["beauty": .loaded(beautyShelf)]))
    }

    /// The shelf is still on screen, so it will not appear again: its error and "Try again" must come back.
    @Test func aCancelledShelfRetryRestoresItsFailure() async {
        let shelfCalls = CallCount()
        var repository = homeRepository()
        repository.onCategoryProducts = { _, _, _ async throws(APIError) in
            let call = await shelfCalls.next()
            throw call == 0 ? APIError.offline : APIError.cancelled
        }
        let viewModel = HomeViewModel(repository: repository)
        await viewModel.load()
        await viewModel.shelfAppeared(beauty)
        let failed = shownState(shelves: ["beauty": .failed(APIError.offline.message)])
        #expect(viewModel.state == failed)

        await viewModel.retryShelf(beauty)

        #expect(viewModel.state == failed)
    }

    /// The attention shelf's "Try again" cancelled: its error and button come back, not a skeleton forever.
    @Test func aCancelledAttentionRetryRestoresItsFailure() async {
        let attentionCalls = CallCount()
        var repository = homeRepository()
        repository.onProducts = { _, _ async throws(APIError) in
            let call = await attentionCalls.next()
            throw call == 0 ? APIError.offline : APIError.cancelled
        }
        let viewModel = HomeViewModel(repository: repository)
        let failed = State(categories: .loaded([beauty, groceries]), attention: .failed(APIError.offline.message))
        await viewModel.load()
        #expect(viewModel.state == failed)

        await viewModel.retryAttention()

        #expect(viewModel.state == failed)
    }

    /// Back online after a shelf failed: a pull to refresh loads that shelf too, not only the loaded ones.
    @Test func aRefreshRetriesAFailedShelf() async {
        let shelfCalls = CallCount()
        var repository = homeRepository()
        repository.onCategoryProducts = { _, _, _ async throws(APIError) in
            if await shelfCalls.next() == 0 { throw APIError.offline }
            return beautyShelf
        }
        let viewModel = HomeViewModel(repository: repository)
        await viewModel.load()
        await viewModel.shelfAppeared(beauty)
        #expect(viewModel.state == shownState(shelves: ["beauty": .failed(APIError.offline.message)]))

        await viewModel.refresh()

        #expect(viewModel.state == shownState(shelves: ["beauty": .loaded(beautyShelf)]))
    }

    /// Chips are toggles, and the chosen ones keep the chips' order whichever was tapped first.
    @Test func chosenCategoriesKeepTheChipOrder() async {
        let viewModel = HomeViewModel(repository: homeRepository())
        await viewModel.load()

        viewModel.toggleCategory(groceries)
        viewModel.toggleCategory(beauty)

        var expected = shownState()
        expected.selectedCategories = [beauty, groceries]
        #expect(viewModel.state == expected)
        #expect(viewModel.categoryList == nil)
    }

    /// One chosen chip shows that category's grid in place, paging from its first page.
    @Test func oneChosenCategoryShowsItsGrid() async {
        var repository = homeRepository()
        repository.onCategoryProducts = { slug, page, _ async throws(APIError) in
            guard slug == "groceries" else { throw APIError.invalidRequest }
            return samplePage(skip: page.skip, count: page.limit, total: 27)
        }
        let viewModel = HomeViewModel(repository: repository)
        await viewModel.load()

        viewModel.toggleCategory(groceries)
        await viewModel.categoryList?.load()

        var expected = shownState()
        expected.selectedCategories = [groceries]
        #expect(viewModel.state == expected)
        #expect(
            viewModel.categoryList?.state
                == ProductListViewModel.State(products: .loaded(samplePage(skip: 0, count: 12, total: 27).items))
        )
    }

    @Test func tappingAChosenChipAgainUnchoosesIt() async {
        let viewModel = HomeViewModel(repository: homeRepository())
        await viewModel.load()

        viewModel.toggleCategory(beauty)
        viewModel.toggleCategory(beauty)

        #expect(viewModel.state == shownState())
        #expect(viewModel.categoryList == nil)
    }

    /// The "All" chip.
    @Test func clearCategoriesShowsTheWholeCatalogAgain() async {
        let viewModel = HomeViewModel(repository: homeRepository())
        await viewModel.load()
        viewModel.toggleCategory(beauty)
        viewModel.toggleCategory(groceries)

        viewModel.clearCategories()

        #expect(viewModel.state == shownState())
        #expect(viewModel.categoryList == nil)
    }

    /// A pull to refresh on Home also reloads the chosen category's grid, which is what the merchant sees.
    @Test func refreshAlsoReloadsTheChosenCategoryGrid() async {
        let gridCalls = CallCount()
        var repository = homeRepository()
        repository.onCategoryProducts = { _, _, _ async throws(APIError) in
            await gridCalls.next() == 0
                ? samplePage(skip: 0, count: 12, total: 27) : samplePage(skip: 0, count: 5, total: 5)
        }
        let viewModel = HomeViewModel(repository: repository)
        await viewModel.load()
        viewModel.toggleCategory(groceries)
        await viewModel.categoryList?.load()

        await viewModel.refresh()

        var expected = shownState()
        expected.selectedCategories = [groceries]
        #expect(viewModel.state == expected)
        #expect(
            viewModel.categoryList?.state
                == ProductListViewModel.State(products: .loaded(samplePage(skip: 0, count: 5, total: 5).items))
        )
    }

    /// Home has one notice for a failed refresh, so the chosen grid failing on its own says so there too.
    @Test func aChosenGridThatFailsToRefreshSaysSo() async {
        let gridCalls = CallCount()
        var repository = homeRepository()
        repository.onCategoryProducts = { _, _, _ async throws(APIError) in
            if await gridCalls.next() > 0 { throw APIError.offline }
            return samplePage(skip: 0, count: 12, total: 27)
        }
        let viewModel = HomeViewModel(repository: repository)
        await viewModel.load()
        viewModel.toggleCategory(groceries)
        await viewModel.categoryList?.load()

        await viewModel.refresh()

        var expected = shownState(refreshFailure: APIError.offline.message)
        expected.selectedCategories = [groceries]
        #expect(viewModel.state == expected)
    }

    @Test func aFailedRefreshKeepsWhatWasShownAndSaysSo() async {
        let categoryCalls = CallCount()
        var repository = homeRepository()
        repository.onCategories = { () async throws(APIError) in
            if await categoryCalls.next() > 0 { throw APIError.offline }
            return [beauty, groceries]
        }
        repository.onCategoryProducts = { _, _, _ in beautyShelf }
        let viewModel = HomeViewModel(repository: repository)
        await viewModel.load()
        await viewModel.shelfAppeared(beauty)

        await viewModel.refresh()

        #expect(
            viewModel.state
                == shownState(shelves: ["beauty": .loaded(beautyShelf)], refreshFailure: APIError.offline.message)
        )
    }
}

private let beauty = Product.Category(slug: "beauty", name: "Beauty")
private let groceries = Product.Category(slug: "groceries", name: "Groceries")
/// A category's first page, whatever page size the shelf asks for.
private let beautyShelf = samplePage(skip: 0, count: 10, total: 40)

/// Home's two requests answered: two categories, and a stock-sorted page where everything is in stock.
private func homeRepository() -> FakeProductRepository {
    var repository = FakeProductRepository()
    repository.onCategories = { [beauty, groceries] }
    repository.onProducts = { _, _ in samplePage(skip: 0, count: 48, total: 194) }
    return repository
}

/// Home once `homeRepository()`'s answers are shown.
private func shownState(
    attention: HomeViewModel.Attention = HomeViewModel.Attention(products: [], mayHaveMore: false),
    shelves: [String: Loadable<Page<Product.Summary>>] = [:],
    refreshFailure: String? = nil
) -> HomeViewModel.State {
    HomeViewModel.State(
        categories: .loaded([beauty, groceries]),
        attention: .loaded(attention),
        shelves: shelves,
        productCount: 194,
        refreshFailure: refreshFailure
    )
}

/// Counts a fake's calls, so a test can answer the first call one way and later calls another.
private actor CallCount {
    private(set) var value = 0

    /// Counts this call and returns how many came before it.
    @discardableResult
    func next() -> Int {
        value += 1
        return value - 1
    }
}

extension HomeViewModel {
    /// Home whose chosen-category grid pages through the same repository, as `CatalogFeature` builds it.
    convenience init(repository: any ProductRepositoryProtocol) {
        self.init(repository: repository) { category in
            ProductListViewModel { page throws(APIError) in
                try await repository.products(inCategory: category.slug, page, sortedBy: nil)
            }
        }
    }
}
