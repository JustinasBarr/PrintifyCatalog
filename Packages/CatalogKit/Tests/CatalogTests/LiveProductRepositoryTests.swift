import Foundation
import Networking
import Testing

@testable import Catalog

/// The live repository over the real client, with the server replaced by recorded answers. `.serialized` because the
/// recorded server is shared between tests.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LiveProductRepositoryTests {
    private let repository: LiveProductRepository = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordedServer.self]
        return LiveProductRepository(client: APIClient(configuration: configuration))
    }()

    private let firstPage = PageRequest(limit: 3, skip: 0)

    init() {
        RecordedServer.isOffline = false
        RecordedServer.lastUpdate = nil
    }

    @Test func updateStockReadsTheStockFromTheAnswer() async throws {
        #expect(try await repository.updateStock(id: 1, stock: 15) == 15)
        #expect(RecordedServer.lastUpdate == RecordedServer.Update(path: "/products/1", body: #"{"stock":15}"#))
    }

    /// The server echoes an update but never stores it, so the product it sends next still has the old stock.
    @Test func restockedStockAppliesToTheProductAfterwards() async throws {
        _ = try await repository.updateStock(id: 1, stock: 5)
        let product = try await repository.product(id: 1)
        #expect(product.stock == 5)
        #expect(product.availabilityStatus == "Low Stock")
    }

    @Test func restockedStockAppliesToLaterPages() async throws {
        _ = try await repository.updateStock(id: 2, stock: 0)
        let page = try await repository.products(firstPage, sortedBy: nil)
        #expect(page.items.map(\.stock) == [99, 0, 89])
        #expect(page.items.map(\.availabilityStatus) == ["In Stock", "Out of Stock", "In Stock"])
    }

    @Test func aFailedUpdateChangesNothing() async throws {
        RecordedServer.isOffline = true
        await #expect(throws: APIError.offline) { try await repository.updateStock(id: 1, stock: 5) }
        RecordedServer.isOffline = false
        #expect(try await repository.product(id: 1).stock == 99)
    }

    /// The status bands the API's own data uses: 7 left is the most it calls Low Stock.
    @Test(arguments: [(0, "Out of Stock"), (1, "Low Stock"), (7, "Low Stock"), (8, "In Stock"), (500, "In Stock")])
    func restockedStatusFollowsTheCount(stock: Int, status: String) {
        let restocked = Product.Summary.sample(id: 1, stock: 99).restocked(to: stock)
        #expect(restocked == .sample(id: 1, stock: stock, availabilityStatus: status))
    }
}

/// Answers from the recorded fixtures: the product, the first page, and a stock update that echoes the stock it was
/// sent into the recorded update answer, as the live server does.
private final class RecordedServer: URLProtocol, @unchecked Sendable {
    struct Update: Equatable {
        let path: String
        let body: String
    }

    nonisolated(unsafe) static var isOffline = false
    nonisolated(unsafe) static var lastUpdate: Update?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard !RecordedServer.isOffline else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            respond(with: try answer())
        } catch {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
        }
    }

    private func answer() throws -> Data {
        let path = request.url?.path() ?? ""
        switch (request.httpMethod, path) {
        case ("PUT", _): return try echo(stockIn: sentBody(), at: path)
        case ("GET", "/products/1"): return try fixture("product")
        case ("GET", "/products"): return try fixture("products-summary-page")
        default: throw URLError(.unsupportedURL)
        }
    }

    private func echo(stockIn body: Data, at path: String) throws -> Data {
        RecordedServer.lastUpdate = Update(path: path, body: String(decoding: body, as: UTF8.self))
        let sent = try JSONDecoder().decode(ProductEndpoint.StockUpdate.self, from: body)
        var answer = try JSONSerialization.jsonObject(with: fixture("stock-update")) as? [String: Any] ?? [:]
        answer["stock"] = sent.stock
        return try JSONSerialization.data(withJSONObject: answer)
    }

    /// The session hands a body to a protocol as a stream, never as `httpBody`.
    private func sentBody() -> Data {
        guard let stream = request.httpBodyStream else { return Data() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        stream.open()
        defer { stream.close() }
        while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 {
            data.append(buffer, count: count)
        }
        return data
    }

    private func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw URLError(.fileDoesNotExist)
        }
        return try Data(contentsOf: url)
    }

    private func respond(with body: Data) {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
