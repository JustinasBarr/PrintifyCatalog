import Foundation

/// One request and the type its answer decodes to. Features build these; `APIClient.send` runs them.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public let path: String
    public let query: [URLQueryItem]
    public let method: HTTPMethod
    /// JSON, sent as the request's body.
    public let body: Data?

    public init(path: String, query: [URLQueryItem] = [], method: HTTPMethod = .get, body: Data? = nil) {
        self.path = path
        self.query = query
        self.method = method
        self.body = body
    }

    /// The path alone, for logs: query values can hold what a merchant typed.
    public var name: String { path }

    func url(relativeTo baseURL: URL) -> URL? {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.percentEncodedQueryItems = query.map(percentEncoded)
        }
        return components?.url
    }

    private func percentEncoded(_ item: URLQueryItem) -> URLQueryItem {
        URLQueryItem(
            name: item.name.addingPercentEncoding(withAllowedCharacters: .queryValueAllowed) ?? item.name,
            value: item.value?.addingPercentEncoding(withAllowedCharacters: .queryValueAllowed)
        )
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case put = "PUT"
}

extension CharacterSet {
    /// Foundation leaves `&`, `=` and `+` alone because they are legal in a query, but inside a value they
    /// split it ("red & black") or turn into a space ("S8+").
    fileprivate static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(
        CharacterSet(charactersIn: "&=+")
    )
}
