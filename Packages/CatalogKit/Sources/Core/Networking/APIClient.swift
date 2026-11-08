import Foundation
import os

/// The one HTTP client every feature uses; features bring their endpoints and models.
public struct APIClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let log = Logger(subsystem: "Catalog", category: "network")

    /// `configuration` is replaced in tests; the client adds its timeouts and headers to it.
    public init(
        baseURL: URL = URL(string: "https://dummyjson.com")!,
        configuration: URLSessionConfiguration = .default
    ) {
        // A dead connection shows the retry state after 15 s instead of iOS's default 60 s.
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.baseURL = baseURL
        session = URLSession(configuration: configuration)
    }

    public func send<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
        guard let request = request(for: endpoint) else { throw logged(.invalidRequest, endpoint) }
        let data = try await body(answering: request, for: endpoint)
        return try decoded(data, for: endpoint)
    }

    private func request<Response>(for endpoint: Endpoint<Response>) -> URLRequest? {
        guard let url = endpoint.url(relativeTo: baseURL) else { return nil }
        // A request's own 60 s default would override the session's 15 s.
        var request = URLRequest(url: url, timeoutInterval: session.configuration.timeoutIntervalForRequest)
        request.httpMethod = endpoint.method.rawValue
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// The body of a 2xx answer; anything else becomes an `APIError`.
    private func body<Response>(
        answering request: URLRequest,
        for endpoint: Endpoint<Response>
    ) async throws(APIError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw logged(APIError(transportError: error), endpoint)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw logged(.transport("Not an HTTP response"), endpoint)
        }
        log.debug("\(endpoint.name, privacy: .public) → \(status)")
        guard (200..<300).contains(status) else { throw logged(.server(status: status), endpoint) }
        return data
    }

    private func decoded<Response>(_ data: Data, for endpoint: Endpoint<Response>) throws(APIError) -> Response {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw logged(.decoding(String(describing: error)), endpoint)
        }
    }

    private func logged<Response>(_ error: APIError, _ endpoint: Endpoint<Response>) -> APIError {
        log.error("\(endpoint.name, privacy: .public) failed: \(String(describing: error))")
        return error
    }
}

extension JSONDecoder.DateDecodingStrategy {
    /// ISO 8601 with or without milliseconds. The API writes "2025-10-09T14:47:01.588Z"; Foundation's
    /// `.iso8601` reads the milliseconds only on recent systems, and the app supports iOS 17.
    public static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date")
            )
        }
    }
}
