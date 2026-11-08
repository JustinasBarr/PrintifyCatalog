/// How a list grows. The first page is small so rows appear fast; later pages are bigger so fast scrolling
/// needs few requests. The next page starts while about a screen of rows is still unseen.
struct ListPagination: Equatable, Sendable {
    private(set) var items: [Product.Summary] = []
    /// Unknown until the first page arrives.
    private(set) var total: Int?
    /// Rows the server has sent, duplicates included: the next page starts after them.
    private var received = 0
    private var pagesReceived = 0
    private var reachedEnd = false

    private let pageSizes = [12, 24, 48]
    /// A two-column grid shows about six cells.
    private let prefetchDistance = 6

    var nextPage: PageRequest {
        PageRequest(limit: pageSizes[min(pagesReceived, pageSizes.count - 1)], skip: received)
    }

    var hasMore: Bool {
        guard let total else { return true }
        return !reachedEnd && received < total
    }

    func shouldLoadNextPage(whenItemAppearsAt index: Int) -> Bool {
        hasMore && index >= items.count - prefetchDistance
    }

    /// Adds a page's new rows. Offset paging repeats a row when the catalog changes between two requests,
    /// so a row already shown is dropped; an empty page ends the list even if `total` says otherwise.
    mutating func append(_ page: Page<Product.Summary>) {
        let shown = Set(items.map(\.id))
        items += page.items.filter { !shown.contains($0.id) }
        received += page.items.count
        pagesReceived += 1
        total = page.total
        reachedEnd = page.items.isEmpty
    }
}
