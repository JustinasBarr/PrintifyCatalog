import Foundation
import os

/// Launch with `-ui-test-scenario <name>` to run the app on recorded responses instead of the network. Only the
/// network is faked: the real client, decoder and screens run.
enum UITestScenario: String {
    /// Every products request is answered from `UITestFixtures`, recorded from the live API.
    case catalog
    /// Every request fails the way it does on a phone with no connection.
    case offline

    init?(arguments: [String]) {
        guard let flag = arguments.firstIndex(of: "-ui-test-scenario"), flag + 1 < arguments.count else { return nil }
        self.init(rawValue: arguments[flag + 1])
    }

    /// The session configuration the app's client uses while this scenario runs. `URLProtocol.registerClass`
    /// reaches only `URLSession.shared`, and the client builds its own session, so the fake goes in here.
    func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [network]
        return configuration
    }

    /// Pictures are not recorded, so none is fetched: each fails at once and its cell shows the broken image.
    var imageFetch: @Sendable (URL) async throws -> Data {
        { _ in throw URLError(.notConnectedToInternet) }
    }

    private var network: URLProtocol.Type {
        switch self {
        case .catalog: RecordedNetwork.self
        case .offline: OfflineNetwork.self
        }
    }
}

/// Answers every request inside the app, so none reaches the network.
private class FakeNetwork: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
}

private final class OfflineNetwork: FakeNetwork {
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
}

/// Answers each request with the recording for its path and the query items that pick a page, an order or a
/// search. A request with no recording is logged as an error and answered 404, so a missing fixture shows.
private final class RecordedNetwork: FakeNetwork {
    override func startLoading() {
        let url = request.url!
        let key = recordingKey(for: url)
        guard let name = recordings[key], let body = recording(named: name) else {
            log.error("No recording for \(key, privacy: .public)")
            return answer(url, status: 404, body: Data())
        }
        log.debug("\(key, privacy: .public) → \(name, privacy: .public).json")
        answer(url, status: 200, body: body)
    }

    private func recording(named name: String) -> Data? {
        Bundle.main.url(forResource: name, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }

    private func answer(_ url: URL, status: Int, body: Data) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private let log = Logger(subsystem: "Catalog", category: "ui-test")

/// The request as the recordings know it: the path, then `skip`, `sortBy`, `order` and `q` when present.
/// `limit` and `select` are left out, so a new page size or row field needs no new recording.
private func recordingKey(for url: URL) -> String {
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let picked = ["skip", "sortBy", "order", "q"].compactMap { name in
        query.first { $0.name == name }.map { "\(name)=\($0.value ?? "")" }
    }
    let path = String(url.path().dropFirst())
    return picked.isEmpty ? path : "\(path)?\(picked.joined(separator: "&"))"
}

/// Each file in `UITestFixtures` is the live API's answer to the request the app sends, recorded with curl. The
/// only edit: the category list keeps its first four entries, so every shelf on Home has a recording.
private let recordings = [
    "products/categories": "categories",
    "products?skip=0&sortBy=stock&order=asc": "products-by-stock",
    "products/category/beauty?skip=0": "category-beauty",
    "products/category/fragrances?skip=0": "category-fragrances",
    "products/category/furniture?skip=0": "category-furniture",
    "products/category/groceries?skip=0": "category-groceries",
    "products/category/groceries?skip=12": "category-groceries-skip12",
    "products/16": "product-16",
    "products/26": "product-26",
    "products/117": "product-117",
]
