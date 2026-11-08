import Foundation
import Images
import os

/// Launch with `-ui-test-scenario <name>` to run the app on recorded responses instead of the network. Only the
/// network is faked: the real client, decoder and screens run.
enum UITestScenario: String {
    /// Every products request is answered from `UITestFixtures`, recorded from the live API.
    case catalog
    /// Every request fails the way it does on a phone with no connection.
    case offline
    /// The catalog on a weak connection: every answer, pictures included, arrives `slowAnswerDelay` late.
    case slow
    /// The connection drops after the first look: each address answers once, then fails as offline, and a page after
    /// a list's first never arrives. So a next page fails under a loaded list, and Try again, pull to refresh and a
    /// product opened a second time fail after their screen loaded.
    case offlineAfterFirst = "offline-after-first"
    /// The connection drops right after Home's category list: every other request fails as offline, so each shelf
    /// on Home, Needs attention included, shows its own message and Try again.
    case offlineAfterCategories = "offline-after-categories"

    init?(arguments: [String]) {
        guard let flag = arguments.firstIndex(of: "-ui-test-scenario"), flag + 1 < arguments.count else { return nil }
        // `AsyncImage` loads through `URLSession.shared`, past the fake, so it would reach the image CDN.
        precondition(
            ImageLoaderKind(arguments: arguments) == .downsampling,
            "A scenario fakes pictures through the downsampling loader only; drop -imageLoader system."
        )
        self.init(rawValue: arguments[flag + 1])
    }

    /// The session configuration the app's client uses while this scenario runs. `URLProtocol.registerClass`
    /// reaches only `URLSession.shared`, and the client builds its own session, so the fake goes in here.
    func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [network]
        return configuration
    }

    /// Pictures are not recorded. In `catalog`, `offline` and `offline-after-categories` each fails at once and its
    /// cell shows the broken image; `slow` and `offline-after-first` answer every picture with one stand-in photo,
    /// late or once.
    var imageFetch: @Sendable (URL) async throws -> Data {
        switch self {
        case .catalog, .offline, .offlineAfterCategories:
            { _ in throw URLError(.notConnectedToInternet) }
        case .slow:
            { _ in
                try await Task.sleep(for: slowAnswerDelay)
                return try standInPhoto()
            }
        case .offlineAfterFirst:
            { url in
                guard isFirstAsk(for: url) else { throw URLError(.notConnectedToInternet) }
                return try standInPhoto()
            }
        }
    }

    private var network: URLProtocol.Type {
        switch self {
        case .catalog: RecordedNetwork.self
        case .offline: OfflineNetwork.self
        case .slow: SlowNetwork.self
        case .offlineAfterFirst: DroppingNetwork.self
        case .offlineAfterCategories: CategoriesOnlyNetwork.self
        }
    }
}

/// Answers every request inside the app, so none reaches the network.
private class FakeNetwork: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    fileprivate func failOffline() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
}

private final class OfflineNetwork: FakeNetwork {
    override func startLoading() {
        failOffline()
    }
}

/// Answers each request with the recording for its path and the query items that pick a page, an order or a
/// search. A request with no recording is logged as an error and answered 404, so a missing fixture shows.
private class RecordedNetwork: FakeNetwork {
    override func startLoading() {
        answerFromRecordings()
    }

    fileprivate func answerFromRecordings() {
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

/// The recordings, each `slowAnswerDelay` late. A request the app cancels meanwhile gets no answer.
private final class SlowNetwork: RecordedNetwork {
    private var delay: Task<Void, Never>?

    override func startLoading() {
        // The SDK does not mark `URLProtocol` `Sendable`; the session leaves this one alone until it answers.
        nonisolated(unsafe) let network = self
        delay = Task {
            try? await Task.sleep(for: slowAnswerDelay)
            guard !Task.isCancelled else { return }
            network.answerFromRecordings()
        }
    }

    override func stopLoading() {
        delay?.cancel()
    }
}

/// The recordings, each address once; a second ask, and any page after a list's first, fails as offline.
private final class DroppingNetwork: RecordedNetwork {
    override func startLoading() {
        let url = request.url!
        guard !isNextPage(url), isFirstAsk(for: url) else { return failOffline() }
        answerFromRecordings()
    }
}

/// The category list from its recording; every other request fails as offline.
private final class CategoriesOnlyNetwork: RecordedNetwork {
    override func startLoading() {
        guard recordingKey(for: request.url!) == categoriesKey else { return failOffline() }
        answerFromRecordings()
    }
}

private let log = Logger(subsystem: "Catalog", category: "ui-test")

/// Long enough to see every placeholder, well short of the client's 15 s timeout.
private let slowAnswerDelay = Duration.seconds(3)

/// Every address `offline-after-first` has answered, API and pictures alike, from the session's and the image
/// loader's threads.
private let answeredAddresses = OSAllocatedUnfairLock(initialState: Set<URL>())

private func isFirstAsk(for url: URL) -> Bool {
    answeredAddresses.withLock { $0.insert(url).inserted }
}

/// A list asks for the rows after the ones it has with `skip` above 0.
private func isNextPage(_ url: URL) -> Bool {
    let skip = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "skip" }
    return (skip?.value.flatMap(Int.init) ?? 0) > 0
}

/// One drawn product photo (`stand-in-photo.png`) for every picture URL, so pictures load without the image CDN.
private func standInPhoto() throws -> Data {
    guard let url = Bundle.main.url(forResource: "stand-in-photo", withExtension: "png") else {
        throw URLError(.fileDoesNotExist)
    }
    return try Data(contentsOf: url)
}

/// The request as the recordings know it: the path, then `skip`, `sortBy`, `order` and `q` when present.
/// `limit` and `select` are left out, so a new page size or row field needs no new recording. A first page asking
/// for fewer rows gets the whole recording: the Needs attention list asks for 12 and gets the 48 Home checks, so its
/// next page starts at `skip=48`.
private func recordingKey(for url: URL) -> String {
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let picked = ["skip", "sortBy", "order", "q"].compactMap { name in
        query.first { $0.name == name }.map { "\(name)=\($0.value ?? "")" }
    }
    let path = String(url.path().dropFirst())
    return picked.isEmpty ? path : "\(path)?\(picked.joined(separator: "&"))"
}

private let categoriesKey = "products/categories"

/// Each file in `UITestFixtures` is the live API's answer to the request the app sends, recorded with curl. The
/// only edit: the category list keeps its first four entries, so every shelf on Home has a recording.
private let recordings = [
    categoriesKey: "categories",
    "products?skip=0&sortBy=stock&order=asc": "products-by-stock",
    "products?skip=48&sortBy=stock&order=asc": "products-by-stock-skip48",
    "products/category/beauty?skip=0": "category-beauty",
    "products/category/fragrances?skip=0": "category-fragrances",
    "products/category/furniture?skip=0": "category-furniture",
    "products/category/groceries?skip=0": "category-groceries",
    "products/category/groceries?skip=12": "category-groceries-skip12",
    "products/category/groceries?skip=0&sortBy=price&order=asc": "category-groceries-price-asc",
    "products/search?skip=0&q=red": "search-red",
    "products/search?skip=0&q=qwerty": "search-qwerty",
    "products/4": "product-4",
    "products/5": "product-5",
    "products/16": "product-16",
    "products/17": "product-17",
    "products/23": "product-23",
    "products/26": "product-26",
    "products/117": "product-117",
]
