import Foundation
import Testing

@testable import Catalog
@testable import Networking

/// Each endpoint's full URL, exactly as the client sends it.
struct ProductEndpointTests {
    /// The list row's fields; the summary fixtures were recorded with this same list.
    private let rowFields =
        "select=id,title,price,discountPercentage,rating,stock,availabilityStatus,brand,category,thumbnail"
    private let firstPage = PageRequest(limit: 12, skip: 0)

    @Test func productsPage() {
        #expect(
            url(ProductEndpoint.products(PageRequest(limit: 24, skip: 12), sortedBy: nil))
                == "https://dummyjson.com/products?limit=24&skip=12&\(rowFields)"
        )
    }

    @Test(arguments: [
        (Product.Sort.stockLowFirst, "sortBy=stock&order=asc"),
        (.priceLowToHigh, "sortBy=price&order=asc"),
        (.priceHighToLow, "sortBy=price&order=desc"),
        (.ratingHighFirst, "sortBy=rating&order=desc"),
        (.nameAToZ, "sortBy=title&order=asc"),
    ])
    func everySortGoesToTheServer(sort: Product.Sort, query: String) {
        #expect(
            url(ProductEndpoint.products(firstPage, sortedBy: sort))
                == "https://dummyjson.com/products?limit=12&skip=0&\(query)&\(rowFields)"
        )
    }

    @Test func categoryPage() {
        #expect(
            url(ProductEndpoint.products(inCategory: "smartphones", firstPage, sortedBy: .priceHighToLow))
                == "https://dummyjson.com/products/category/smartphones?limit=12&skip=0&sortBy=price&order=desc&\(rowFields)"
        )
    }

    @Test func searchEncodesTheText() {
        #expect(
            url(ProductEndpoint.search("red & black", firstPage, sortedBy: .nameAToZ))
                == "https://dummyjson.com/products/search?q=red%20%26%20black&limit=12&skip=0&sortBy=title&order=asc&\(rowFields)"
        )
    }

    /// Logs name the endpoint by its path, so what a merchant searched for never reaches them.
    @Test func searchTextStaysOutOfTheLogName() {
        #expect(ProductEndpoint.search("red & black", firstPage, sortedBy: nil).name == "products/search")
    }

    @Test func categories() {
        #expect(url(ProductEndpoint.categories) == "https://dummyjson.com/products/categories")
    }

    @Test func productByID() {
        #expect(url(ProductEndpoint.product(id: 7)) == "https://dummyjson.com/products/7")
    }

    private func url<Response>(_ endpoint: Endpoint<Response>) -> String? {
        endpoint.url(relativeTo: URL(string: "https://dummyjson.com")!)?.absoluteString
    }
}
