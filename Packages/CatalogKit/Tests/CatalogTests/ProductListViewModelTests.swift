import Foundation
import Networking
import Testing

@testable import Catalog

@MainActor
struct ProductListViewModelTests {
    private typealias State = ProductListViewModel.State

    @Test func loadShowsTheFirstPage() async {
        let requests = Requests()
        let viewModel = ProductListViewModel(loadPage: catalog(total: 194, recordingIn: requests))

        await viewModel.load()

        #expect(viewModel.state == State(products: .loaded(samples(0..<12))))
        #expect(await requests.pages == [PageRequest(limit: 12, skip: 0)])
    }

    @Test func aFailedFirstPageShowsItsMessageAndRetryLoadsIt() async {
        let requests = Requests()
        let viewModel = ProductListViewModel { page async throws(APIError) in
            if await requests.record(page) == 0 { throw APIError.offline }
            return samplePage(skip: page.skip, count: page.limit, total: 194)
        }

        await viewModel.load()
        #expect(viewModel.state == State(products: .failed(APIError.offline.message)))

        await viewModel.retry()
        #expect(viewModel.state == State(products: .loaded(samples(0..<12))))
    }

    /// A two-column grid shows about six cells, so the next page starts while six are still unseen.
    @Test func theNextPageStartsAScreenBeforeTheEnd() async {
        let requests = Requests()
        let viewModel = ProductListViewModel(loadPage: catalog(total: 194, recordingIn: requests))
        await viewModel.load()

        await viewModel.itemAppeared(at: 5)
        #expect(await requests.pages == [PageRequest(limit: 12, skip: 0)])

        await viewModel.itemAppeared(at: 6)
        #expect(viewModel.state == State(products: .loaded(samples(0..<36))))
        #expect(await requests.pages == [PageRequest(limit: 12, skip: 0), PageRequest(limit: 24, skip: 12)])
    }

    /// Offset paging repeats rows when products are added between two requests; each row shows once.
    @Test func rowsAlreadyShownAreDropped() async {
        let viewModel = ProductListViewModel { page in
            // Two products were added at the top after the first page, so the second starts two rows early.
            let shifted = page.skip == 0 ? 0 : page.skip - 2
            return samplePage(skip: shifted, count: page.limit, total: 196)
        }
        await viewModel.load()

        await viewModel.loadNextPage()

        #expect(viewModel.state == State(products: .loaded(samples(0..<34))))
    }

    @Test func aFailedNextPageKeepsTheLoadedProducts() async {
        let requests = Requests()
        let viewModel = ProductListViewModel { page async throws(APIError) in
            if await requests.record(page) == 1 { throw APIError.timedOut }
            return samplePage(skip: page.skip, count: page.limit, total: 194)
        }
        await viewModel.load()

        await viewModel.loadNextPage()
        #expect(
            viewModel.state
                == State(products: .loaded(samples(0..<12)), nextPage: .failed(APIError.timedOut.message))
        )

        // Scrolling on does not retry by itself; the inline "Try again" does.
        await viewModel.itemAppeared(at: 11)
        #expect(await requests.pages.count == 2)

        await viewModel.retry()
        #expect(viewModel.state == State(products: .loaded(samples(0..<36))))
    }

    @Test func refreshReplacesTheListAndPagesFromItsStart() async {
        let requests = Requests()
        let viewModel = ProductListViewModel { page in
            // The catalog changed after the first two pages: from then on its rows start at id 100.
            let firstID = await requests.record(page) < 2 ? 0 : 100
            let ids = firstID + page.skip..<firstID + page.skip + page.limit
            return Page(items: samples(ids), total: 194, skip: page.skip, limit: page.limit)
        }
        await viewModel.load()
        await viewModel.loadNextPage()

        await viewModel.refresh()
        #expect(viewModel.state == State(products: .loaded(samples(100..<112))))

        await viewModel.loadNextPage()
        #expect(viewModel.state == State(products: .loaded(samples(100..<136))))
        #expect(
            await requests.pages == [
                PageRequest(limit: 12, skip: 0), PageRequest(limit: 24, skip: 12),
                PageRequest(limit: 12, skip: 0), PageRequest(limit: 24, skip: 12),
            ]
        )
    }

    @Test func aFailedRefreshKeepsTheProductsAndSaysSo() async {
        let requests = Requests()
        let viewModel = ProductListViewModel { page async throws(APIError) in
            if await requests.record(page) > 0 { throw APIError.offline }
            return samplePage(skip: page.skip, count: page.limit, total: 194)
        }
        await viewModel.load()

        await viewModel.refresh()

        #expect(
            viewModel.state == State(products: .loaded(samples(0..<12)), refreshFailure: APIError.offline.message)
        )
    }

    @Test func theEndOfTheListStopsPaging() async {
        let requests = Requests()
        let viewModel = ProductListViewModel(loadPage: catalog(total: 20, recordingIn: requests))
        await viewModel.load()
        await viewModel.loadNextPage()

        await viewModel.loadNextPage()
        await viewModel.itemAppeared(at: 19)

        #expect(viewModel.state == State(products: .loaded(samples(0..<20))))
        #expect(await requests.pages == [PageRequest(limit: 12, skip: 0), PageRequest(limit: 24, skip: 12)])
    }

    /// Leaving the grid while a page loads cancels it: the footer goes quiet, never shows an error.
    @Test func aCancelledNextPageIsNeverAFailure() async {
        let requests = Requests()
        let viewModel = ProductListViewModel { page async throws(APIError) in
            if await requests.record(page) == 1 { throw APIError.cancelled }
            return samplePage(skip: page.skip, count: page.limit, total: 194)
        }
        await viewModel.load()

        await viewModel.loadNextPage()

        #expect(viewModel.state == State(products: .loaded(samples(0..<12)), nextPage: .idle))
    }

    /// A cancelled "Try again" brings the error and its button back, not a skeleton with no request behind it.
    @Test func aCancelledRetryRestoresTheFirstPageFailure() async {
        let requests = Requests()
        let viewModel = ProductListViewModel { page async throws(APIError) in
            let call = await requests.record(page)
            throw call == 0 ? APIError.offline : APIError.cancelled
        }
        await viewModel.load()
        #expect(viewModel.state == State(products: .failed(APIError.offline.message)))

        await viewModel.retry()

        #expect(viewModel.state == State(products: .failed(APIError.offline.message)))
    }

    /// The attention list keeps low and out of stock by the API's status, while the next page still starts after
    /// every row the server sent, hidden ones included.
    @Test func theAttentionListKeepsLowAndOutOfStockAndPagesPastHiddenRows() async {
        let requests = Requests()
        let rows = (0..<30).map(row)
        var repository = FakeProductRepository()
        repository.onProducts = { page, sort async throws(APIError) in
            guard sort == .stockLowFirst else { throw APIError.invalidRequest }
            await requests.record(page)
            let start = min(page.skip, rows.count)
            let end = min(page.skip + page.limit, rows.count)
            return Page(items: Array(rows[start..<end]), total: rows.count, skip: page.skip, limit: page.limit)
        }
        let viewModel = CatalogFeature(repository: repository).productList(.attention)

        await viewModel.load()
        await viewModel.loadNextPage()

        let lowAndOut = rows.filter { !$0.id.isMultiple(of: 3) }
        #expect(viewModel.state == State(products: .loaded(lowAndOut)))
        #expect(await requests.pages == [PageRequest(limit: 12, skip: 0), PageRequest(limit: 24, skip: 12)])
    }
}

/// Samples with these ids, as `samplePage` makes them.
private func samples(_ ids: Range<Int>) -> [Product.Summary] {
    ids.map { Product.Summary.sample(id: $0) }
}

/// A list of `total` sample rows that records every page it is asked for.
private func catalog(total: Int, recordingIn requests: Requests) -> ProductListViewModel.LoadPage {
    { page in
        await requests.record(page)
        let count = max(0, min(page.limit, total - page.skip))
        return samplePage(skip: page.skip, count: count, total: total)
    }
}

/// Every third row is in stock with 7 left; the others are low with the same 7 left, or out of stock.
private func row(_ id: Int) -> Product.Summary {
    let (status, stock) = [("In Stock", 7), ("Low Stock", 7), ("Out of Stock", 0)][id % 3]
    return Product.Summary(
        id: id,
        title: "Product \(id)",
        price: 10,
        discountPercentage: 0,
        rating: 4,
        stock: stock,
        availabilityStatus: status,
        brand: nil,
        category: "beauty",
        thumbnail: URL(string: "https://cdn.example.com/\(id).webp")!
    )
}

/// Every page a list asked for, in order.
private actor Requests {
    private(set) var pages: [PageRequest] = []

    /// Records `page` and returns how many requests came before it, so a test can answer each one differently.
    @discardableResult
    func record(_ page: PageRequest) -> Int {
        pages.append(page)
        return pages.count - 1
    }
}
