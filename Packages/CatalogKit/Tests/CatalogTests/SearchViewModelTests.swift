import Networking
import Testing

@testable import Catalog

@MainActor
struct SearchViewModelTests {
    private typealias State = SearchViewModel.State
    private typealias Results = SearchViewModel.Results

    @Test func wordsShowASkeletonThenTheirMatchesOnceTypingPauses() async {
        let searches = Searches()
        let pauses = Pauses()
        let viewModel = SearchViewModel(sleep: pauses.record, search: matches(total: 18, recordingIn: searches))

        viewModel.textChanged("red")
        #expect(viewModel.state == State(text: "red", results: .loading))

        await viewModel.search()

        #expect(
            viewModel.state
                == State(text: "red", results: .loaded(Results(query: "red", products: samples(0..<12), total: 18)))
        )
        #expect(await pauses.durations == [.milliseconds(300)])
        #expect(await searches.asked == [Search(text: "red", page: PageRequest(limit: 12, skip: 0))])
    }

    /// The next key cancels the wait, so only the words typed last reach the server.
    @Test func aKeyDuringThePauseSendsNothing() async {
        let searches = Searches()
        let viewModel = SearchViewModel(
            sleep: { _ in throw CancellationError() },
            search: matches(total: 18, recordingIn: searches)
        )
        viewModel.textChanged("re")

        await viewModel.search()

        #expect(viewModel.state == State(text: "re", results: .loading))
        #expect(await searches.asked.isEmpty)
    }

    @Test func spacesAroundTheWordsSearchTheWordsAlone() async {
        let searches = Searches()
        let viewModel = SearchViewModel(sleep: { _ in }, search: matches(total: 18, recordingIn: searches))
        viewModel.textChanged(" red ")

        await viewModel.search()

        #expect(
            viewModel.state
                == State(text: " red ", results: .loaded(Results(query: "red", products: samples(0..<12), total: 18)))
        )
        #expect(await searches.asked == [Search(text: "red", page: PageRequest(limit: 12, skip: 0))])
    }

    /// The grid never blanks between keys: the older matches stay until the newer words have their own.
    @Test func newerWordsKeepTheOlderMatchesUntilTheirAnswer() async {
        let viewModel = SearchViewModel(sleep: { _ in }, search: matches(total: 18, recordingIn: Searches()))
        viewModel.textChanged("red")
        await viewModel.search()
        let red = Results(query: "red", products: samples(0..<12), total: 18)

        viewModel.textChanged("red l")

        #expect(viewModel.state == State(text: "red l", results: .loaded(red)))
    }

    /// The field changed while the server answered: that answer is for words no longer there.
    @Test func anAnswerForOlderWordsIsDropped() async {
        let typist = Typist()
        let viewModel = SearchViewModel(
            sleep: { _ in },
            search: { text, page async throws(APIError) in
                if text == "re" { await typist.type("red") }
                return samplePage(skip: page.skip, count: page.limit, total: 18)
            }
        )
        typist.viewModel = viewModel
        viewModel.textChanged("re")

        await viewModel.search()

        #expect(viewModel.state == State(text: "red", results: .loading))
    }

    /// Newer words cancelled the request: what was shown stays, never an error.
    @Test func aCancelledSearchKeepsWhatWasShown() async {
        let viewModel = SearchViewModel(
            sleep: { _ in },
            search: { text, page async throws(APIError) in
                if text == "redx" { throw APIError.cancelled }
                return samplePage(skip: page.skip, count: page.limit, total: 18)
            }
        )
        viewModel.textChanged("red")
        await viewModel.search()
        let red = Results(query: "red", products: samples(0..<12), total: 18)

        viewModel.textChanged("redx")
        await viewModel.search()

        #expect(viewModel.state == State(text: "redx", results: .loaded(red)))
    }

    @Test func aFailedSearchSaysSoAndRetryAsksAgain() async {
        let searches = Searches()
        let viewModel = SearchViewModel(
            sleep: { _ in },
            search: { text, page async throws(APIError) in
                if await searches.record(text, page) == 0 { throw APIError.offline }
                return samplePage(skip: page.skip, count: page.limit, total: 18)
            }
        )
        viewModel.textChanged("red")

        await viewModel.search()
        #expect(viewModel.state == State(text: "red", results: .failed(APIError.offline.message)))

        await viewModel.retry()
        #expect(
            viewModel.state
                == State(text: "red", results: .loaded(Results(query: "red", products: samples(0..<12), total: 18)))
        )
    }

    @Test func noMatchIsAnEmptyAnswerNotAFailure() async {
        let viewModel = SearchViewModel(
            sleep: { _ in },
            search: { _, page async throws(APIError) in
                Page(items: [], total: 0, skip: page.skip, limit: page.limit)
            }
        )
        viewModel.textChanged("qwerty")

        await viewModel.search()

        #expect(
            viewModel.state == State(text: "qwerty", results: .loaded(Results(query: "qwerty", products: [], total: 0)))
        )
    }

    @Test func theMatchesPageLikeAList() async {
        let searches = Searches()
        let viewModel = SearchViewModel(sleep: { _ in }, search: matches(total: 30, recordingIn: searches))
        viewModel.textChanged("red")
        await viewModel.search()

        await viewModel.itemAppeared(at: 5)
        await viewModel.itemAppeared(at: 6)

        #expect(
            viewModel.state
                == State(text: "red", results: .loaded(Results(query: "red", products: samples(0..<30), total: 30)))
        )
        #expect(
            await searches.asked == [
                Search(text: "red", page: PageRequest(limit: 12, skip: 0)),
                Search(text: "red", page: PageRequest(limit: 24, skip: 12)),
            ]
        )
    }

    @Test func aFailedNextPageKeepsTheMatchesAndRetryAsksForThatPage() async {
        let searches = Searches()
        let viewModel = SearchViewModel(
            sleep: { _ in },
            search: { text, page async throws(APIError) in
                if await searches.record(text, page) == 1 { throw APIError.unreachable }
                return samplePage(skip: page.skip, count: min(page.limit, 30 - page.skip), total: 30)
            }
        )
        viewModel.textChanged("red")
        await viewModel.search()

        await viewModel.loadNextPage()
        let red = Results(query: "red", products: samples(0..<12), total: 30)
        #expect(
            viewModel.state
                == State(text: "red", results: .loaded(red), nextPage: .failed(APIError.unreachable.message))
        )

        await viewModel.retry()
        #expect(
            viewModel.state
                == State(text: "red", results: .loaded(Results(query: "red", products: samples(0..<30), total: 30)))
        )
    }

    /// Clearing the words or closing search brings Home back, and the next search starts from its first page.
    @Test func noWordsShowHome() async {
        let searches = Searches()
        let viewModel = SearchViewModel(sleep: { _ in }, search: matches(total: 18, recordingIn: searches))
        viewModel.textChanged("red")
        await viewModel.search()

        viewModel.textChanged("  ")
        await viewModel.search()
        #expect(viewModel.state == State(text: "  ", results: nil))

        viewModel.textChanged("red")
        viewModel.close()
        #expect(viewModel.state == State())
        #expect(await searches.asked == [Search(text: "red", page: PageRequest(limit: 12, skip: 0))])
    }
}

/// Samples with these ids, as `samplePage` makes them.
private func samples(_ ids: Range<Int>) -> [Product.Summary] {
    ids.map { Product.Summary.sample(id: $0) }
}

/// `total` matches for any words, recording every page asked for.
private func matches(total: Int, recordingIn searches: Searches) -> SearchViewModel.Search {
    { text, page in
        await searches.record(text, page)
        return samplePage(skip: page.skip, count: max(0, min(page.limit, total - page.skip)), total: total)
    }
}

private struct Search: Equatable {
    let text: String
    let page: PageRequest
}

/// Every search the server was asked for, in order.
private actor Searches {
    private(set) var asked: [Search] = []

    /// Records the search and returns how many came before it, so a test can answer each one differently.
    @discardableResult
    func record(_ text: String, _ page: PageRequest) -> Int {
        asked.append(Search(text: text, page: page))
        return asked.count - 1
    }
}

/// Every pause in typing the view model waited for; each returns at once.
private actor Pauses {
    private(set) var durations: [Duration] = []

    nonisolated var record: SearchViewModel.Sleep {
        { duration in await self.append(duration) }
    }

    private func append(_ duration: Duration) {
        durations.append(duration)
    }
}

/// Types into the field while a search is on its way, as a merchant would.
@MainActor
private final class Typist {
    var viewModel: SearchViewModel?

    func type(_ text: String) {
        viewModel?.textChanged(text)
    }
}
