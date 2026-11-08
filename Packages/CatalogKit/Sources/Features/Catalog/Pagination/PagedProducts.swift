/// Products that arrive a page at a time, as `ProductGrid` draws them: a category, the products that need
/// attention, or what a search matches.
@MainActor
protocol PagedProducts: AnyObject {
    var products: Loadable<[Product.Summary]> { get }
    /// Only while products are shown: whether the page after them is loading or failed.
    var nextPage: NextPage { get }
    /// Tries the request that failed again: the first page or the next one.
    func retry() async
    func itemAppeared(at index: Int) async
}

enum NextPage: Equatable {
    case idle
    case loading
    case failed(String)
}
