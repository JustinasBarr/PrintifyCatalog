import Foundation
import UIKit

/// Which image path the app uses, picked at launch with `-imageLoader system|downsampling`, so both can be
/// compared in Instruments on the same build.
public enum ImageLoaderKind: String, Sendable {
    /// SwiftUI `AsyncImage`: full-size decode, nothing kept in memory between appearances.
    case system
    /// `DownsamplingImageLoader`: decoded at display size, memory cache, shared in-flight requests.
    case downsampling

    /// Reads the value after `-imageLoader`; anything missing or unknown is `.downsampling`.
    public init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let value = arguments.firstIndex(of: "-imageLoader").flatMap { flag in
            arguments.indices.contains(flag + 1) ? arguments[flag + 1] : nil
        }
        self = value.flatMap(ImageLoaderKind.init(rawValue:)) ?? .downsampling
    }
}

public protocol ImageLoading: Sendable {
    /// The image decoded at no more than `maxPixelSize` pixels on its longest side.
    func image(for url: URL, maxPixelSize: Int) async throws -> UIImage
    /// The last image decoded for `url` at any size, if it is still in memory, without waiting: a screen that
    /// opens on a picture the grid already shows draws it at once, then swaps in its own sharper decode.
    func cachedImage(for url: URL) -> UIImage?
}
