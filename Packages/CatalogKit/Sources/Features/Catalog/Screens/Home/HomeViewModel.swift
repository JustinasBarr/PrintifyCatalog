import Networking
import Observation

/// Home: what needs attention first, then a shelf per category. Opening the app costs two requests (the
/// categories and one stock-sorted page); each shelf loads its first page only when it scrolls in.
@MainActor
@Observable
final class HomeViewModel {
    struct State: Equatable {
        var categories: Loadable<[Product.Category]> = .loading
        var attention: Loadable<Attention> = .loading
        /// Each category's first page, by slug; a shelf that has not scrolled in has none.
        var shelves: [String: Loadable<Page<Product.Summary>>] = [:]
        /// Every product in the catalog, for the search prompt; nil until known.
        var productCount: Int?
        /// A pull to refresh failed; what was shown stays.
        var refreshFailure: String?
        /// The chosen category chips, in chip order. None shows the whole catalog, one shows that category's grid
        /// in place, more show only their shelves.
        var selectedCategories: [Product.Category] = []
        /// "Try again" is asking again; the failure stays on screen until the answer.
        var isRetrying = false
    }

    /// The products that are low or out of stock, lowest stock first.
    struct Attention: Equatable, Sendable {
        var products: [Product.Summary]
        /// Every row checked needed attention, so more may follow after them.
        var mayHaveMore: Bool
    }

    private(set) var state = State()
    /// The grid of the one chosen category; nil unless exactly one chip is chosen.
    private(set) var categoryList: ProductListViewModel?
    private let repository: any ProductRepository
    private let makeCategoryList: (Product.Category) -> ProductListViewModel
    /// The API cannot filter by availability, so Home checks the 48 lowest-stock products.
    private let attentionCheck = PageRequest(limit: 48, skip: 0)
    private let shelfPage = PageRequest(limit: 10, skip: 0)

    init(
        repository: any ProductRepository,
        categoryList makeCategoryList: @escaping (Product.Category) -> ProductListViewModel
    ) {
        self.repository = repository
        self.makeCategoryList = makeCategoryList
    }

    /// The screen appeared: loads unless the categories are already shown. A cancelled request shows what was
    /// shown before.
    func load() async {
        guard state.categories.value == nil else { return }
        let shown = state
        state = State()
        async let categories = categoriesResult()
        async let attention = attentionResult()
        show(await categories, await attention, over: shown)
    }

    /// Asks again under the failure, so no skeleton flashes before the answer. A cancelled request leaves the failure.
    func retry() async {
        state.isRetrying = true
        async let categories = categoriesResult()
        async let attention = attentionResult()
        show(await categories, await attention, over: state)
        state.isRetrying = false
    }

    /// Reloads the categories, the attention shelf, every shelf that loaded or failed and the chosen category's
    /// grid. A failure keeps what was shown and says so above it.
    func refresh() async {
        let chosenList = categoryList
        async let categories = categoriesResult()
        async let attention = attentionResult()
        async let shelves = reloadedShelves()
        async let chosenListRefreshed: Void? = chosenList?.refresh()
        let (newCategories, newAttention, newShelves, _) = await (categories, attention, shelves, chosenListRefreshed)
        let failures = show(newCategories, newAttention, over: state) + showShelves(newShelves)
        state.refreshFailure =
            failures.first(where: { $0 != .cancelled })?.message ?? chosenList?.state.refreshFailure
    }

    func retryAttention() async {
        let shown = state.attention
        state.attention = .loading
        showAttention(await attentionResult(), over: shown)
    }

    func toggleCategory(_ category: Product.Category) {
        let chosen = state.selectedCategories
        let chips = state.categories.value ?? []
        state.selectedCategories = chips.filter { chip in
            chip == category ? !chosen.contains(chip) : chosen.contains(chip)
        }
        showCategoryList()
    }

    /// The "All" chip.
    func clearCategories() {
        state.selectedCategories = []
        showCategoryList()
    }

    func shelfAppeared(_ category: Product.Category) async {
        switch state.shelves[category.slug] {
        case .loading, .loaded: return
        case .failed, nil: await loadShelf(category)
        }
    }

    func retryShelf(_ category: Product.Category) async {
        await loadShelf(category)
    }

    /// One chosen category shows as a grid; any other choice shows shelves.
    private func showCategoryList() {
        guard let only = state.selectedCategories.first, state.selectedCategories.count == 1 else {
            categoryList = nil
            return
        }
        categoryList = makeCategoryList(only)
    }

    private func loadShelf(_ category: Product.Category) async {
        let shown = state.shelves[category.slug]
        state.shelves[category.slug] = .loading
        switch await shelfResult(category.slug) {
        case .success(let page): state.shelves[category.slug] = .loaded(page)
        // A shelf scrolled away before it loaded has none and loads when it next scrolls in. A retried shelf is
        // still on screen and will not appear again, so its error and "Try again" come back.
        case .failure(.cancelled): state.shelves[category.slug] = shown
        case .failure(let error): state.shelves[category.slug] = .failed(error.message)
        }
    }

    /// Shows the two Home requests over what `shown` showed and returns their failures.
    @discardableResult
    private func show(
        _ categories: Result<[Product.Category], APIError>,
        _ attentionPage: Result<Page<Product.Summary>, APIError>,
        over shown: State
    ) -> [APIError] {
        state.categories = updated(shown.categories, with: categories)
        showAttention(attentionPage, over: shown.attention)
        return [categories.failure, attentionPage.failure].compactMap { $0 }
    }

    /// The attention page also carries the catalog's total, for the search field.
    private func showAttention(_ page: Result<Page<Product.Summary>, APIError>, over shown: Loadable<Attention>) {
        state.attention = updated(shown, with: page.map(Attention.init(checking:)))
        if case .success(let page) = page { state.productCount = page.total }
    }

    private func showShelves(_ results: [String: Result<Page<Product.Summary>, APIError>]) -> [APIError] {
        for (slug, result) in results {
            state.shelves[slug] = updated(state.shelves[slug] ?? .loading, with: result)
        }
        return results.values.compactMap(\.failure)
    }

    /// A section after its request. A failure over loaded content, or a cancelled request, keeps what it showed.
    private func updated<Value>(_ current: Loadable<Value>, with result: Result<Value, APIError>) -> Loadable<Value> {
        switch result {
        case .success(let value): .loaded(value)
        case .failure(let error) where current.value == nil && error != .cancelled: .failed(error.message)
        case .failure: current
        }
    }

    private func reloadedShelves() async -> [String: Result<Page<Product.Summary>, APIError>] {
        // A loading shelf already has its request running.
        let shown = state.shelves.compactMap { slug, shelf in shelf == .loading ? nil : slug }
        return await withTaskGroup(of: (String, Result<Page<Product.Summary>, APIError>).self) { group in
            for slug in shown {
                group.addTask { (slug, await self.shelfResult(slug)) }
            }
            var results: [String: Result<Page<Product.Summary>, APIError>] = [:]
            for await (slug, result) in group {
                results[slug] = result
            }
            return results
        }
    }

    private func categoriesResult() async -> Result<[Product.Category], APIError> {
        do throws(APIError) {
            return .success(try await repository.categories())
        } catch {
            return .failure(error)
        }
    }

    private func attentionResult() async -> Result<Page<Product.Summary>, APIError> {
        do throws(APIError) {
            return .success(try await repository.products(attentionCheck, sortedBy: .stockLowFirst))
        } catch {
            return .failure(error)
        }
    }

    private func shelfResult(_ slug: String) async -> Result<Page<Product.Summary>, APIError> {
        do throws(APIError) {
            return .success(try await repository.products(inCategory: slug, shelfPage, sortedBy: nil))
        } catch {
            return .failure(error)
        }
    }
}

extension HomeViewModel.Attention {
    /// The rows of a stock-sorted page that need attention. When every row does, more may follow after them.
    init(checking page: Page<Product.Summary>) {
        products = page.items.filter(\.needsAttention)
        mayHaveMore = !products.isEmpty && products.count == page.items.count && page.total > page.items.count
    }
}

extension Result {
    fileprivate var failure: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
