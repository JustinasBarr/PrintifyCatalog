import Foundation
import Testing
import UIKit

@testable import Images

/// The loader runs on a fake fetch, so downloads are counted, not guessed.
@Suite(.timeLimit(.minutes(1)))
struct DownsamplingImageLoaderTests {
    private let url = URL(string: "https://cdn.example.com/a.png")!

    @Test func decodesAtTheRequestedPixelSize() async throws {
        let server = FakeImageServer(png: png(width: 400, height: 200))
        let loader = DownsamplingImageLoader(fetch: server.fetch)
        let image = try await loader.image(for: url, maxPixelSize: 100)
        #expect(image.cgImage?.width == 100)
        #expect(image.cgImage?.height == 50)
    }

    @Test func secondRequestIsServedFromMemory() async throws {
        let server = FakeImageServer(png: png(width: 40, height: 40))
        let loader = DownsamplingImageLoader(fetch: server.fetch)
        _ = try await loader.image(for: url, maxPixelSize: 40)
        _ = try await loader.image(for: url, maxPixelSize: 40)
        #expect(await server.fetches == 1)
    }

    /// Two cells showing the same product at once ask together; the second waits for the first download.
    @Test func requestsInFlightAreShared() async throws {
        let server = FakeImageServer(png: png(width: 40, height: 40))
        await server.hold()
        let loader = DownsamplingImageLoader(fetch: server.fetch)
        async let first = loader.image(for: url, maxPixelSize: 40)
        async let second = loader.image(for: url, maxPixelSize: 40)
        await server.waitForFirstFetch()
        await server.release()
        _ = try await (first, second)
        #expect(await server.fetches == 1)
    }

    @Test func cachedImageIsTheLastDecodeForTheURL() async throws {
        let server = FakeImageServer(png: png(width: 400, height: 200))
        let loader = DownsamplingImageLoader(fetch: server.fetch)
        #expect(loader.cachedImage(for: url) == nil)
        _ = try await loader.image(for: url, maxPixelSize: 100)
        #expect(loader.cachedImage(for: url)?.cgImage?.width == 100)
        _ = try await loader.image(for: url, maxPixelSize: 200)
        #expect(loader.cachedImage(for: url)?.cgImage?.width == 200)
    }

    /// Every picture the loader keeps counts against one budget, so a merchant opening detail after detail
    /// cannot grow the app past it.
    @Test func picturesKeptStayWithinTheMemoryLimit() async throws {
        let server = FakeImageServer(png: png(width: 100, height: 100))
        let probe = try await DownsamplingImageLoader(fetch: server.fetch).image(for: url, maxPixelSize: 100)
        let oneImage = try #require(probe.cgImage).bytesPerRow * 100
        let loader = DownsamplingImageLoader(fetch: server.fetch, memoryLimit: 3 * oneImage)
        let urls = (1...20).map { URL(string: "https://cdn.example.com/\($0).png")! }
        for url in urls { _ = try await loader.image(for: url, maxPixelSize: 100) }
        #expect(urls.filter { loader.cachedImage(for: $0) != nil }.count <= 3)
    }

    @Test func failureIsNotCached() async throws {
        let server = FakeImageServer(png: png(width: 40, height: 40))
        await server.failNext()
        let loader = DownsamplingImageLoader(fetch: server.fetch)
        await #expect(throws: URLError.self) { try await loader.image(for: url, maxPixelSize: 40) }
        _ = try await loader.image(for: url, maxPixelSize: 40)
        #expect(await server.fetches == 2)
    }

    @Test func bytesThatAreNotAnImageThrow() async {
        let loader = DownsamplingImageLoader(fetch: { _ in Data("not an image".utf8) })
        await #expect(throws: DownsamplingImageLoader.UndecodableImage.self) {
            try await loader.image(for: url, maxPixelSize: 40)
        }
    }

    @Test(arguments: [
        (["App", "-imageLoader", "system"], ImageLoaderKind.system),
        (["App", "-imageLoader", "downsampling"], .downsampling),
        (["App"], .downsampling),
        (["App", "-imageLoader"], .downsampling),
        (["App", "-imageLoader", "bogus"], .downsampling),
    ])
    func loaderKindComesFromLaunchArguments(arguments: [String], expected: ImageLoaderKind) {
        #expect(ImageLoaderKind(arguments: arguments) == expected)
    }

    private func png(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}

/// Serves one PNG; can hold every fetch until released, or fail the next one.
actor FakeImageServer {
    private let png: Data
    private(set) var fetches = 0
    private var held = false
    private var shouldFail = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(png: Data) {
        self.png = png
    }

    func hold() { held = true }
    func failNext() { shouldFail = true }

    func release() {
        held = false
        for continuation in waiting { continuation.resume() }
        waiting = []
    }

    func waitForFirstFetch() async {
        while fetches == 0 { await Task.yield() }
    }

    nonisolated var fetch: @Sendable (URL) async throws -> Data {
        { _ in try await self.answer() }
    }

    private func answer() async throws -> Data {
        fetches += 1
        if held { await withCheckedContinuation { waiting.append($0) } }
        if shouldFail {
            shouldFail = false
            throw URLError(.notConnectedToInternet)
        }
        return png
    }
}
