import Foundation
import Persistence
import Testing

struct FileCacheTests {
    private struct Value: Codable, Equatable {
        let name: String
    }

    private let cache = FileCache(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))

    @Test func returnsWhatWasSaved() async throws {
        try await cache.save(Value(name: "mascara"), forKey: "page")
        #expect(await cache.value(Value.self, forKey: "page") == Value(name: "mascara"))
    }

    @Test func nothingSavedIsNil() async {
        #expect(await cache.value(Value.self, forKey: "page") == nil)
    }

    @Test func savingAgainReplaces() async throws {
        try await cache.save(Value(name: "mascara"), forKey: "page")
        try await cache.save(Value(name: "lipstick"), forKey: "page")
        #expect(await cache.value(Value.self, forKey: "page") == Value(name: "lipstick"))
    }

    @Test func fileOfAnotherShapeIsNil() async throws {
        try await cache.save(["unexpected": 1], forKey: "page")
        #expect(await cache.value(Value.self, forKey: "page") == nil)
    }

    /// Keys will be request paths such as "products/category/beauty"; a slash must not become a folder.
    @Test func keysWithSlashesAreOneFileEach() async throws {
        try await cache.save(Value(name: "beauty"), forKey: "products/category/beauty")
        try await cache.save(Value(name: "all"), forKey: "products")
        #expect(await cache.value(Value.self, forKey: "products/category/beauty") == Value(name: "beauty"))
        #expect(await cache.value(Value.self, forKey: "products") == Value(name: "all"))
    }

    @Test func removeAllForgetsEverything() async throws {
        try await cache.save(Value(name: "mascara"), forKey: "page")
        await cache.removeAll()
        #expect(await cache.value(Value.self, forKey: "page") == nil)
    }
}
