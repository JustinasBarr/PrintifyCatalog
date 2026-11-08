import Foundation

/// One GET request and the type its answer decodes to. Features build these; `APIClient.send` runs them.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public let path: String
    public let query: [URLQueryItem]

    public init(path: String, query: [URLQueryItem] = []) {
        self.path = path
        self.query = query
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

extension CharacterSet {
    /// Foundation leaves `&`, `=` and `+` alone because they are legal in a query, but inside a value they
    /// split it ("red & black") or turn into a space ("S8+").
    fileprivate static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(
        CharacterSet(charactersIn: "&=+")
    )
}
