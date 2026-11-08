import Foundation
import ImageIO
import UIKit

/// Pictures for a scrolling grid: decoded at display size, kept in memory, fetched once per URL and size
/// even when several cells ask together. One instance for the whole app, so the cache outlives screens.
public actor DownsamplingImageLoader: ImageLoading {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    /// The bytes arrived but are not an image.
    public struct UndecodableImage: Error {}

    private struct Key: Hashable {
        let url: URL
        let maxPixelSize: Int
        var cacheKey: NSString { "\(maxPixelSize)|\(url.absoluteString)" as NSString }
    }

    private let fetch: Fetch
    /// `NSCache` is documented as safe to use from any thread, so `cachedImage(for:)` reads these from the main
    /// actor without waiting; the SDK does not mark it `Sendable`, hence `unsafe`.
    private nonisolated(unsafe) let memory = NSCache<NSString, UIImage>()
    /// The key of the last decode per URL, not the picture, so every picture counts against `memory`'s limit.
    private nonisolated(unsafe) let newestKey = NSCache<NSURL, NSString>()
    private var inFlight: [Key: Task<UIImage, any Error>] = [:]

    /// `fetch` is replaced in tests; by default pictures come from `URLSession.shared`.
    public init(fetch: Fetch? = nil, memoryLimit: Int = 64 * 1024 * 1024) {
        self.fetch = fetch ?? fetchFromNetwork
        memory.totalCostLimit = memoryLimit
    }

    public nonisolated func cachedImage(for url: URL) -> UIImage? {
        newestKey.object(forKey: url as NSURL).flatMap { memory.object(forKey: $0) }
    }

    public func image(for url: URL, maxPixelSize: Int) async throws -> UIImage {
        let key = Key(url: url, maxPixelSize: maxPixelSize)
        if let cached = memory.object(forKey: key.cacheKey) { return cached }
        if let running = inFlight[key] { return try await running.value }

        let task = Task { [fetch] in try await downloadAndDecode(url, maxPixelSize: maxPixelSize, fetch: fetch) }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let image = try await task.value
        memory.setObject(image, forKey: key.cacheKey, cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
        newestKey.setObject(key.cacheKey, forKey: url as NSURL)
        return image
    }
}

/// Runs off the loader's actor, so one large decode never holds up the cache lookups of other cells.
@concurrent
private func downloadAndDecode(
    _ url: URL,
    maxPixelSize: Int,
    fetch: DownsamplingImageLoader.Fetch
) async throws -> UIImage {
    let data = try await fetch(url)
    guard let image = downsample(data, maxPixelSize: maxPixelSize) else {
        throw DownsamplingImageLoader.UndecodableImage()
    }
    return image
}

/// ImageIO decodes straight to the target size, so a 1000 px picture never sits in memory at full size.
private func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
    let options =
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    else { return nil }
    return UIImage(cgImage: image)
}

private func fetchFromNetwork(_ url: URL) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
        throw URLError(.badServerResponse)
    }
    return data
}
