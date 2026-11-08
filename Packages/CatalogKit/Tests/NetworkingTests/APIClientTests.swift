import Foundation
import Testing
import os

@testable import Networking

/// The client runs for real against a stubbed `URLProtocol` set on its session configuration, so URL building,
/// status checks, error mapping and decoding are all the production code. `.serialized` because the stub's
/// answer is shared between tests.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct APIClientTests {
    private struct Item: Decodable, Equatable, Sendable {
        let id: Int
    }

    private let client: APIClient = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.com")!, configuration: configuration)
    }()

    private let item = Endpoint<Item>(path: "item")

    private var lastRequest: URLRequest? { StubProtocol.lastRequest.withLock { $0 } }
    private var lastBody: Data? { StubProtocol.lastBody.withLock { $0 } }

    init() {
        StubProtocol.lastRequest.withLock { $0 = nil }
        StubProtocol.lastBody.withLock { $0 = nil }
    }

    @Test func joinsBaseURLPathAndQuery() async throws {
        StubProtocol.answer = .json(#"{"id":1}"#)
        _ = try await client.send(Endpoint<Item>(path: "products", query: [URLQueryItem(name: "limit", value: "12")]))
        #expect(lastRequest?.url?.absoluteString == "https://example.com/products?limit=12")
        #expect(lastRequest?.httpMethod == "GET")
    }

    @Test func noQueryLeavesNoQuestionMark() async throws {
        StubProtocol.answer = .json(#"{"id":1}"#)
        _ = try await client.send(item)
        #expect(lastRequest?.url?.absoluteString == "https://example.com/item")
    }

    /// `&`, `=` and `+` are legal inside a query, so Foundation leaves some of them as they are; the server
    /// would then read "red & black" as two parameters and "S8+" as "S8 ".
    @Test func queryValuesArePercentEncoded() async throws {
        StubProtocol.answer = .json(#"{"id":1}"#)
        _ = try await client.send(
            Endpoint<Item>(path: "products/search", query: [URLQueryItem(name: "q", value: "red & black = S8+ é")])
        )
        #expect(
            lastRequest?.url?.absoluteString
                == "https://example.com/products/search?q=red%20%26%20black%20%3D%20S8%2B%20%C3%A9"
        )
    }

    @Test func asksForJSON() async throws {
        StubProtocol.answer = .json(#"{"id":1}"#)
        _ = try await client.send(item)
        #expect(lastRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func putSendsItsJSONBody() async throws {
        StubProtocol.answer = .json(#"{"id":1}"#)
        let body = Data(#"{"stock":15}"#.utf8)
        _ = try await client.send(Endpoint<Item>(path: "products/1", method: .put, body: body))
        #expect(lastRequest?.httpMethod == "PUT")
        #expect(lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(lastBody == body)
    }

    @Test func decodesTheEndpointsResponseType() async throws {
        StubProtocol.answer = .json(#"{"id":7}"#)
        #expect(try await client.send(item) == Item(id: 7))
    }

    @Test(arguments: [400, 404, 500, 503])
    func nonSuccessStatusIsServerError(status: Int) async {
        StubProtocol.answer = .status(status)
        await #expect(throws: APIError.server(status: status)) {
            try await client.send(item)
        }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed])
    func noConnectionIsOffline(code: URLError.Code) async {
        StubProtocol.answer = .failure(URLError(code))
        await #expect(throws: APIError.offline) {
            try await client.send(item)
        }
    }

    @Test func slowServerIsTimedOut() async {
        StubProtocol.answer = .failure(URLError(.timedOut))
        await #expect(throws: APIError.timedOut) {
            try await client.send(item)
        }
    }

    @Test func otherTransportFailuresAreTransport() async {
        StubProtocol.answer = .failure(URLError(.cannotFindHost))
        do {
            _ = try await client.send(item)
            Issue.record("expected a transport error")
        } catch {
            guard case .transport = error else {
                Issue.record("got \(error)")
                return
            }
        }
    }

    @Test func unreadableBodyIsDecodingError() async {
        StubProtocol.answer = .json(#"{"id":"not a number"}"#)
        do {
            _ = try await client.send(item)
            Issue.record("expected a decoding error")
        } catch {
            guard case .decoding = error else {
                Issue.record("got \(error)")
                return
            }
        }
    }

    /// The user left the screen while the request was on the wire.
    @Test func cancellingTheTaskIsCancelled() async throws {
        StubProtocol.answer = .never
        let task = Task { try await client.send(item) }
        while lastRequest == nil { await Task.yield() }
        task.cancel()
        await #expect(throws: APIError.cancelled) {
            try await task.value
        }
    }

    @Test func swiftCancellationIsCancelled() {
        #expect(APIError(transportError: CancellationError()) == .cancelled)
        #expect(APIError(transportError: URLError(.cancelled)) == .cancelled)
    }

    @Test func messagesAreWordsNotCodes() {
        #expect(APIError.offline.message == "You're offline. Check your connection and try again.")
        #expect(!APIError.server(status: 503).message.contains("503"))
        #expect(!APIError.decoding("keyNotFound id").message.contains("keyNotFound"))
    }
}

/// Answers every request with `answer` and remembers the last request and its body. URLSession calls
/// `startLoading` on its own thread while a test polls `lastRequest`, so those two sit behind locks; `answer` is
/// written only before a request starts, and `.serialized` keeps tests apart.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Answer {
        case json(String)
        case status(Int)
        case failure(URLError)
        /// Never answers, like a request still on the wire.
        case never
    }

    nonisolated(unsafe) static var answer = Answer.status(500)
    static let lastRequest = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
    /// The session hands a body to a protocol as a stream, never as `httpBody`.
    static let lastBody = OSAllocatedUnfairLock<Data?>(initialState: nil)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        StubProtocol.lastRequest.withLock { $0 = request }
        let body = request.httpBodyStream.map(readAll)
        StubProtocol.lastBody.withLock { $0 = body }
        switch StubProtocol.answer {
        case .json(let body): respond(status: 200, body: Data(body.utf8))
        case .status(let status): respond(status: status, body: Data())
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .never: break
        }
    }

    private func readAll(_ stream: InputStream) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        stream.open()
        defer { stream.close() }
        while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 {
            data.append(buffer, count: count)
        }
        return data
    }

    private func respond(status: Int, body: Data) {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
