import Foundation

/// Saves one Codable value per key as a JSON file. Meant for data the server can always rebuild, so a
/// missing or unreadable file is simply "nothing saved".
public actor FileCache {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL) {
        self.directory = directory
    }

    public func value<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = try? Data(contentsOf: fileURL(key)) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    public func save<Value: Encodable>(_ value: Value, forKey key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(value).write(to: fileURL(key), options: .atomic)
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Keys are request paths such as "products/category/beauty"; encoding them keeps one flat file per key
    /// instead of a folder per slash.
    private func fileURL(_ key: String) -> URL {
        let name = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return directory.appending(path: "\(name).json")
    }
}
