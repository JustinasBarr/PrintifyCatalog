import Images
import SwiftUI

/// Serves views that the app has not handed its loader, such as previews: one instance, so its cache is
/// shared instead of a new empty loader on every read of the environment.
private let fallbackImageLoader = DownsamplingImageLoader()

extension EnvironmentValues {
    @Entry public var imageLoaderKind: ImageLoaderKind = .downsampling
    /// The app injects its one shared loader.
    @Entry public var imageLoader: any ImageLoaderProtocol = fallbackImageLoader
}

/// A product picture. While it loads, a shimmer covers the whole frame (not just the inset photo), so the
/// tile keeps one shape and colour and only the picture fades in. The launch argument `-imageLoader` picks
/// `AsyncImage` or the downsampling loader, so both can be measured on one build.
public struct RemoteImage: View {
    private let url: URL?
    private let preview: URL?
    private let contentMode: ContentMode
    private let inset: EdgeInsets
    @Environment(\.imageLoaderKind) private var kind
    @Environment(\.redactionReasons) private var redaction

    /// `preview` is a picture already on screen elsewhere (the list's thumbnail): while `url` loads, its cached
    /// copy stands in, so a detail swapping the thumbnail for the full photo never flashes empty.
    public init(url: URL?, preview: URL? = nil, contentMode: ContentMode = .fit, inset: EdgeInsets = EdgeInsets()) {
        self.url = url
        self.preview = preview
        self.contentMode = contentMode
        self.inset = inset
    }

    public var body: some View {
        Group {
            if redaction.contains(.placeholder) {
                ImagePlaceholder()
            } else {
                switch kind {
                case .system: SystemImage(url: url, contentMode: contentMode, inset: inset)
                case .downsampling:
                    DownsampledImage(url: url, preview: preview, contentMode: contentMode, inset: inset)
                }
            }
        }
        // A reused view showing a new product starts empty, never with the previous product's picture. Keyed on the
        // preview when there is one, so the picture on screen stays while the sharper photo for it loads.
        .id(preview ?? url)
        .accessibilityHidden(true)
    }
}

/// A faint tint with the moving band, filling the whole frame on any background.
private struct ImagePlaceholder: View {
    var body: some View {
        Rectangle().fill(Color.ink.opacity(0.035)).shimmering()
    }
}

private struct SystemImage: View {
    let url: URL?
    let contentMode: ContentMode
    let inset: EdgeInsets

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .strongEaseOut)) { phase in
            switch phase {
            case .success(let image): image.resizable().aspectRatio(contentMode: contentMode).padding(inset)
            case .failure: BrokenImage()
            default: ImagePlaceholder()
            }
        }
    }
}

private struct DownsampledImage: View {
    let url: URL?
    let preview: URL?
    let contentMode: ContentMode
    let inset: EdgeInsets
    @Environment(\.imageLoader) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let picture = image ?? cachedCopy {
                    // Fades only: nothing moves when data arrives.
                    Image(uiImage: picture).resizable().aspectRatio(contentMode: contentMode).padding(inset)
                        .transition(.opacity)
                } else if failed {
                    BrokenImage()
                } else {
                    ImagePlaceholder().transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Keyed on the URL and on "has a size", never on the size itself: a zoom transition resizes the
            // frame every frame, and each new size would restart the load (the flicker).
            .task(id: Request(url: url, hasSize: proxy.size.width > 0 && proxy.size.height > 0)) {
                await load(pixels: Int(max(proxy.size.width, proxy.size.height) * displayScale))
            }
        }
    }

    private struct Request: Equatable {
        let url: URL?
        let hasSize: Bool
    }

    private func load(pixels: Int) async {
        guard let url else {
            failed = true
            return
        }
        guard pixels > 0 else { return }
        failed = false
        do {
            show(try await loader.image(for: url, maxPixelSize: pixels))
        } catch is CancellationError {
        } catch {
            failed = image == nil
        }
    }

    /// Fades in over an empty frame; over a picture already on screen it swaps at once, because the two are the same
    /// photo and a fade between them would dim it halfway.
    private func show(_ loaded: UIImage) {
        guard image ?? cachedCopy == nil else {
            image = loaded
            return
        }
        withAnimation(.strongEaseOut) { image = loaded }
    }

    /// A detail that opens on a picture the grid already shows draws it in its first frame, before the load task
    /// starts, then swaps in its sharper decode.
    private var cachedCopy: UIImage? {
        url.flatMap(loader.cachedImage(for:)) ?? preview.flatMap(loader.cachedImage(for:))
    }
}

private struct BrokenImage: View {
    var body: some View {
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(Color.ink3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
