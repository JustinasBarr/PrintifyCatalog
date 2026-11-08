import Foundation
import Networking
import Observation

/// A paged grid of products: a category, or the products that need attention. Pages grow by `ListPagination`
/// and one page request runs at a time. The merchant can sort it and narrow it to what needs attention.
@MainActor
@Observable
final class ProductListViewModel {
    struct State: Equatable {
        var products: Loadable<[Product.Summary]> = .loading
        /// Only while products are shown: whether the page after them is loading or failed.
        var nextPage = NextPage.idle
        /// A pull to refresh failed; the products already shown stay.
        var refreshFailure: String?
        /// What the sort sheet picked.
        var sortFilter = SortFilter()
        /// "Try again" is asking for the first page again; the failure stays on screen until the answer.
        var isRetrying = false
    }

    /// What the sort sheet picked: an order for the server, and whether only low and out-of-stock products show.
    /// A nil order keeps the list's own order.
    struct SortFilter: Equatable, Sendable {
        var sort: Product.Sort?
        var needsAttentionOnly = false
    }

    typealias LoadPage = @Sendable (PageRequest) async throws(APIError) -> Page<Product.Summary>
    typealias LoadSortedPage = @Sendable (PageRequest, Product.Sort?) async throws(APIError) -> Page<Product.Summary>

    private(set) var state = State()
    private var pagination = ListPagination()
    /// The attention list keeps only low and out-of-stock rows whatever the sheet picks.
    private let alwaysNeedsAttention: Bool
    private let loadPage: LoadSortedPage

    /// A list in the server's order only: `loadPage` gets no order, so the sort sheet changes nothing.
    convenience init(loadPage: @escaping LoadPage) {
        self.init { page, _ throws(APIError) in try await loadPage(page) }
    }

    /// `alwaysNeedsAttention` makes the attention list: it keeps only the rows that need attention.
    init(alwaysNeedsAttention: Bool = false, loadPage: @escaping LoadSortedPage) {
        self.alwaysNeedsAttention = alwaysNeedsAttention
        self.loadPage = loadPage
    }

    /// The order the rows show in: the one picked, or lowest stock first while only rows that need attention show.
    var shownOrder: Product.Sort? {
        state.sortFilter.sort ?? (keepsOnlyNeedingAttention(state.sortFilter) ? .stockLowFirst : nil)
    }

    /// Whether the sort sheet changed the list from how it opened.
    var isSortedOrFiltered: Bool {
        state.sortFilter != SortFilter()
    }

    /// The screen appeared: loads the first page unless products are already shown. A cancelled request shows
    /// what was shown before.
    func load() async {
        guard state.products.value == nil else { return }
        let shown = state.products
        state.products = .loading
        await loadFirstPage()
        // Every answer but a cancelled one replaces the skeleton.
        if state.products == .loading { state.products = shown }
    }

    func refresh() async {
        await loadFirstPage()
    }

    /// Tries the request that failed again: the first page or the next page. A failed refresh has its own
    /// "Try again", which refreshes.
    func retry() async {
        if state.products.value == nil {
            await retryFirstPage()
        } else {
            await loadNextPage()
        }
    }

    /// The merchant picked an order: the list starts again from its first page in that order.
    func sort(by sort: Product.Sort) async {
        var sortFilter = state.sortFilter
        // Rows that need attention already show lowest stock first, so picking it is no change.
        sortFilter.sort = keepsOnlyNeedingAttention(sortFilter) && sort == .stockLowFirst ? nil : sort
        await show(sortFilter)
    }

    func showOnlyNeedingAttention(_ isOn: Bool) async {
        var sortFilter = state.sortFilter
        sortFilter.needsAttentionOnly = isOn
        await show(sortFilter)
    }

    func resetSortFilter() async {
        await show(SortFilter())
    }

    func itemAppeared(at index: Int) async {
        guard state.nextPage == .idle, pagination.shouldLoadNextPage(whenItemAppearsAt: index) else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        guard state.products.value != nil, state.nextPage != .loading, pagination.hasMore,
            !loadsEveryRowAtOnce(state.sortFilter)
        else { return }
        let request = pagination.nextPage
        let sortFilter = state.sortFilter
        state.nextPage = .loading
        let result = await page(request, sortedBy: serverOrder(sortFilter))
        // A refresh or another order started a new list meanwhile; this page answers the old one.
        guard pagination.nextPage == request, state.sortFilter == sortFilter else { return }
        switch result {
        case .success(let page):
            pagination.append(page, keeping: keeper(sortFilter))
            state.products = .loaded(pagination.items)
            state.nextPage = .idle
        case .failure(.cancelled):
            state.nextPage = .idle
        case .failure(let error):
            state.nextPage = .failed(error.message)
        }
    }

    /// Asks again under the failure, so no skeleton flashes before the answer. A cancelled request leaves the failure.
    private func retryFirstPage() async {
        state.isRetrying = true
        await loadFirstPage()
        state.isRetrying = false
    }

    /// Starts the list again in a new order or filter, from a skeleton. A cancelled request shows what was shown.
    private func show(_ sortFilter: SortFilter) async {
        guard sortFilter != state.sortFilter else { return }
        let shown = state
        state = State(sortFilter: sortFilter)
        await loadFirstPage()
        if state.products == .loading, state.sortFilter == sortFilter { state = shown }
    }

    /// Starts the list again from its first page. A failure over shown products keeps them. An answer for an
    /// order the merchant has changed since is dropped: the newer order shows its own.
    private func loadFirstPage() async {
        let sortFilter = state.sortFilter
        let result = loadsEveryRowAtOnce(sortFilter) ? await everyRowNeedingAttention() : await firstPage(sortFilter)
        guard state.sortFilter == sortFilter else { return }
        switch result {
        case .success(let fresh):
            pagination = fresh
            state = State(products: .loaded(ordered(fresh.items, by: sortFilter)), sortFilter: sortFilter)
        case .failure(.cancelled):
            break
        case .failure(let error) where state.products.value != nil:
            state.refreshFailure = error.message
        case .failure(let error):
            state.products = .failed(error.message)
        }
    }

    private func firstPage(_ sortFilter: SortFilter) async -> Result<ListPagination, APIError> {
        var fresh = ListPagination()
        return await page(fresh.nextPage, sortedBy: serverOrder(sortFilter)).map { page in
            fresh.append(page, keeping: keeper(sortFilter))
            return fresh
        }
    }

    /// Pages sorted by stock bring every product that needs attention first, so pages are asked for until one
    /// has none: every row after it has more stock.
    private func everyRowNeedingAttention() async -> Result<ListPagination, APIError> {
        var fresh = ListPagination()
        while fresh.hasMore {
            let keptBefore = fresh.items.count
            switch await page(fresh.nextPage, sortedBy: .stockLowFirst) {
            case .success(let page):
                fresh.append(page, keeping: \.needsAttention)
                if fresh.items.count == keptBefore { return .success(fresh) }
            case .failure(let error):
                return .failure(error)
            }
        }
        return .success(fresh)
    }

    private func keepsOnlyNeedingAttention(_ sortFilter: SortFilter) -> Bool {
        alwaysNeedsAttention || sortFilter.needsAttentionOnly
    }

    /// The API cannot filter by availability: rows that need attention come from pages sorted by stock, where
    /// they come first.
    private func serverOrder(_ sortFilter: SortFilter) -> Product.Sort? {
        keepsOnlyNeedingAttention(sortFilter) ? .stockLowFirst : sortFilter.sort
    }

    private func keeper(_ sortFilter: SortFilter) -> (Product.Summary) -> Bool {
        keepsOnlyNeedingAttention(sortFilter) ? { $0.needsAttention } : { _ in true }
    }

    /// Rows that need attention in another order than stock are all loaded at once and sorted here, so no page
    /// follows them.
    private func loadsEveryRowAtOnce(_ sortFilter: SortFilter) -> Bool {
        keepsOnlyNeedingAttention(sortFilter) && sortFilter.sort != nil
    }

    private func ordered(_ rows: [Product.Summary], by sortFilter: SortFilter) -> [Product.Summary] {
        guard loadsEveryRowAtOnce(sortFilter), let sort = sortFilter.sort else { return rows }
        return rows.sorted(by: sort.areInOrder)
    }

    private func page(
        _ request: PageRequest,
        sortedBy sort: Product.Sort?
    ) async -> Result<Page<Product.Summary>, APIError> {
        do throws(APIError) {
            return .success(try await loadPage(request, sort))
        } catch {
            return .failure(error)
        }
    }
}

extension ProductListViewModel: PagedProducts {
    var products: Loadable<[Product.Summary]> { state.products }
    var nextPage: NextPage { state.nextPage }
    var isRetrying: Bool { state.isRetrying }
}

extension Product.Sort {
    /// Whether `first` comes before `second` in this order, compared as the server compares them.
    fileprivate func areInOrder(_ first: Product.Summary, _ second: Product.Summary) -> Bool {
        switch self {
        case .stockLowFirst: first.stock < second.stock
        case .priceLowToHigh: first.price < second.price
        case .priceHighToLow: first.price > second.price
        case .ratingHighFirst: first.rating > second.rating
        case .nameAToZ: first.title.localizedStandardCompare(second.title) == .orderedAscending
        }
    }
}
