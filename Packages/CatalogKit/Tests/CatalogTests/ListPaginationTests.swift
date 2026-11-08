import Testing

@testable import Catalog

struct ListPaginationTests {
    /// The first screen arrives fast; later pages are bigger so fast scrolling needs few requests.
    @Test func pagesGrowFrom12To24To48ThenStay() {
        var pagination = ListPagination()
        var limits: [Int] = []
        for _ in 0..<5 {
            let request = pagination.nextPage
            limits.append(request.limit)
            pagination.append(samplePage(skip: request.skip, count: request.limit, total: 1000))
        }
        #expect(limits == [12, 24, 48, 48, 48])
    }

    @Test func skipIsEverythingReceivedSoFar() {
        var pagination = ListPagination()
        #expect(pagination.nextPage == PageRequest(limit: 12, skip: 0))
        pagination.append(samplePage(skip: 0, count: 12, total: 194))
        #expect(pagination.nextPage == PageRequest(limit: 24, skip: 12))
        pagination.append(samplePage(skip: 12, count: 24, total: 194))
        #expect(pagination.nextPage == PageRequest(limit: 48, skip: 36))
    }

    /// A two-column grid shows about six cells, so the next page starts while a screen is still unseen.
    @Test(arguments: [(index: 0, expected: false), (index: 5, expected: false), (index: 6, expected: true), (11, true)])
    func nextPageStartsAScreenBeforeTheEnd(index: Int, expected: Bool) {
        var pagination = ListPagination()
        pagination.append(samplePage(skip: 0, count: 12, total: 194))
        #expect(pagination.shouldLoadNextPage(whenItemAppearsAt: index) == expected)
    }

    /// Offset paging repeats rows when products are added between two requests.
    @Test func rowsAlreadyShownAreDropped() {
        var pagination = ListPagination()
        pagination.append(samplePage(skip: 0, count: 12, total: 194))
        let shifted = samplePage(skip: 10, count: 24, total: 194).items
        pagination.append(Page(items: shifted, total: 194, skip: 12, limit: 24))
        #expect(pagination.items.map(\.id) == Array(0..<34))
        #expect(pagination.nextPage.skip == 36)
    }

    @Test func endsWhenTheTotalIsReached() {
        var pagination = ListPagination()
        pagination.append(samplePage(skip: 0, count: 12, total: 20))
        #expect(pagination.hasMore)
        pagination.append(samplePage(skip: 12, count: 8, total: 20))
        #expect(!pagination.hasMore)
        #expect(!pagination.shouldLoadNextPage(whenItemAppearsAt: 19))
        #expect(pagination.total == 20)
    }

    /// The total can be stale when products are removed; an empty page is the real end.
    @Test func anEmptyPageEndsTheList() {
        var pagination = ListPagination()
        pagination.append(samplePage(skip: 0, count: 12, total: 30))
        pagination.append(samplePage(skip: 12, count: 0, total: 30))
        #expect(!pagination.hasMore)
    }

    @Test func beforeTheFirstPageThereIsMore() {
        let pagination = ListPagination()
        #expect(pagination.hasMore)
        #expect(pagination.items.isEmpty)
        #expect(pagination.total == nil)
    }
}
