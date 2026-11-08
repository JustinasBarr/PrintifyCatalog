import Networking
import Observation

/// A paged grid of products: a category, or the products that need attention. Pages grow by `ListPagination`
/// and one page request runs at a time.
@MainActor
@Observable
final class ProductListViewModel {
    struct State: Equatable {
        var products: Loadable<[Product.Summary]> = .loading
        /// Only while products are shown: whether the page after them is loading or failed.
        var nextPage = NextPage.idle
        /// A pull to refresh failed; the products already shown stay.
        var refreshFailure: String?

        enum NextPage: Equatable {
            case idle
            case loading
            case failed(String)
        }
    }

    typealias LoadPage = @Sendable (PageRequest) async throws(APIError) -> Page<Product.Summary>

    private(set) var state = State()
    private var pagination = ListPagination()
    private let isShown: (Product.Summary) -> Bool
    private let loadPage: LoadPage

    /// `isShown` keeps only some rows of each page, such as the ones that need attention.
    init(keeping isShown: @escaping (Product.Summary) -> Bool = { _ in true }, loadPage: @escaping LoadPage) {
        self.isShown = isShown
        self.loadPage = loadPage
    }

    /// The screen appeared: loads the first page unless products are already shown. A cancelled request shows
    /// what was shown before, so a cancelled "Try again" brings the error and its button back.
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

    /// Tries the request that failed again: the first page, the next page or the refresh.
    func retry() async {
        if state.refreshFailure != nil {
            await refresh()
        } else if state.products.value == nil {
            await load()
        } else {
            await loadNextPage()
        }
    }

    func itemAppeared(at index: Int) async {
        guard state.nextPage == .idle, pagination.shouldLoadNextPage(whenItemAppearsAt: index) else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        guard state.products.value != nil, state.nextPage != .loading, pagination.hasMore else { return }
        let request = pagination.nextPage
        state.nextPage = .loading
        let result = await page(request)
        // A refresh that finished meanwhile started a new list; this page answers the old one.
        guard pagination.nextPage == request else { return }
        switch result {
        case .success(let page):
            pagination.append(page, keeping: isShown)
            state.products = .loaded(pagination.items)
            state.nextPage = .idle
        case .failure(.cancelled):
            state.nextPage = .idle
        case .failure(let error):
            state.nextPage = .failed(error.message)
        }
    }

    /// Starts the list again from its first page. A failure over shown products keeps them.
    private func loadFirstPage() async {
        var fresh = ListPagination()
        switch await page(fresh.nextPage) {
        case .success(let page):
            fresh.append(page, keeping: isShown)
            pagination = fresh
            state = State(products: .loaded(fresh.items))
        case .failure(.cancelled):
            break
        case .failure(let error) where state.products.value != nil:
            state.refreshFailure = error.message
        case .failure(let error):
            state.products = .failed(error.message)
        }
    }

    private func page(_ request: PageRequest) async -> Result<Page<Product.Summary>, APIError> {
        do throws(APIError) {
            return .success(try await loadPage(request))
        } catch {
            return .failure(error)
        }
    }
}
