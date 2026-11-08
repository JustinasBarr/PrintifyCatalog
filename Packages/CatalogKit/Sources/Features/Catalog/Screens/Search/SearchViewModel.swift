import Networking
import Observation

/// Search on Home: asks the server once typing pauses for 300 ms and shows only the answer for the latest words.
/// The matches page like any list.
@MainActor
@Observable
final class SearchViewModel {
    struct State: Equatable {
        /// The field's text, as typed.
        var text = ""
        /// The matches for the latest words searched; nil while the field has no words, so Home shows instead.
        /// Older matches stay while newer words wait for their answer, so the grid never blanks between keys.
        var results: Loadable<Results>?
        /// Only while matches are shown: whether the page after them is loading or failed.
        var nextPage = NextPage.idle
    }

    struct Results: Equatable, Sendable {
        /// The words these products match.
        let query: String
        let products: [Product.Summary]
        /// Every match on the server, across all pages.
        let total: Int
    }

    typealias Search = @Sendable (String, PageRequest) async throws(APIError) -> Page<Product.Summary>
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private(set) var state = State()
    private var pagination = ListPagination()
    private let typingPause = Duration.milliseconds(300)
    private let sleep: Sleep
    private let search: Search

    /// `sleep` waits out the pause in typing; a test passes one that returns at once.
    init(sleep: @escaping Sleep = { try await Task.sleep(for: $0) }, search: @escaping Search) {
        self.sleep = sleep
        self.search = search
    }

    /// The field changed. A first search shows a skeleton at once; a newer one keeps the older matches.
    func textChanged(_ text: String) {
        state.text = text
        if words.isEmpty {
            showHome()
        } else if state.results?.value == nil {
            state.results = .loading
        }
    }

    /// Runs after every change of the field: waits for typing to pause, then searches the latest words. The
    /// next change cancels this one, during the wait or the request.
    func search() async {
        guard !words.isEmpty, words != state.results?.value?.query else { return }
        do {
            try await sleep(typingPause)
        } catch {
            return
        }
        await showFirstPage()
    }

    /// Tries the request that failed again: the first page or the next one.
    func retry() async {
        switch state.results {
        case .failed:
            state.results = .loading
            await showFirstPage()
        case .loaded:
            await loadNextPage()
        case .loading, nil:
            return
        }
    }

    func itemAppeared(at index: Int) async {
        guard state.nextPage == .idle, pagination.shouldLoadNextPage(whenItemAppearsAt: index) else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        guard let shown = state.results?.value, state.nextPage != .loading, pagination.hasMore else { return }
        let request = pagination.nextPage
        state.nextPage = .loading
        let result = await page(of: shown.query, request)
        // Newer words were searched meanwhile: this page belongs to the old matches.
        guard state.results?.value?.query == shown.query, pagination.nextPage == request else { return }
        switch result {
        case .success(let page):
            pagination.append(page)
            state.results = .loaded(Results(query: shown.query, products: pagination.items, total: page.total))
            state.nextPage = .idle
        case .failure(.cancelled):
            state.nextPage = .idle
        case .failure(let error):
            state.nextPage = .failed(error.message)
        }
    }

    /// Search was closed: Home shows again, and the next search starts from an empty field.
    func close() {
        state.text = ""
        showHome()
    }

    /// The field's words without the spaces around them: "red " searches what "red" does.
    private var words: String {
        state.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func showHome() {
        pagination = ListPagination()
        state.results = nil
        state.nextPage = .idle
    }

    /// Searches the latest words from their first page. A cancelled search changes nothing: the newer words
    /// that cancelled it show their own answer.
    private func showFirstPage() async {
        let query = words
        var fresh = ListPagination()
        let result = await page(of: query, fresh.nextPage)
        // The field changed while the server answered.
        guard query == words else { return }
        switch result {
        case .success(let page):
            fresh.append(page)
            pagination = fresh
            state.results = .loaded(Results(query: query, products: fresh.items, total: page.total))
            state.nextPage = .idle
        case .failure(.cancelled):
            break
        case .failure(let error):
            state.results = .failed(error.message)
            state.nextPage = .idle
        }
    }

    private func page(of query: String, _ request: PageRequest) async -> Result<Page<Product.Summary>, APIError> {
        do throws(APIError) {
            return .success(try await search(query, request))
        } catch {
            return .failure(error)
        }
    }
}

extension SearchViewModel: PagedProducts {
    /// The matches as the grid draws them; the grid shows only while the field has words.
    var products: Loadable<[Product.Summary]> {
        switch state.results {
        case .loaded(let results): .loaded(results.products)
        case .failed(let message): .failed(message)
        case .loading, nil: .loading
        }
    }

    var nextPage: NextPage { state.nextPage }
    /// A search's "Try again" starts again from placeholders, like a new search.
    var isRetrying: Bool { false }
}
