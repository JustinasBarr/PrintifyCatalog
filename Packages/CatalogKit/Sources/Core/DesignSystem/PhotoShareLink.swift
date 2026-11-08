import Images
import SwiftUI
import UniformTypeIdentifiers

/// Shares a remote photo with a line of words, such as a product with its price. The photo is downloaded through
/// the app's image loader only once the person picks where to send it.
public struct PhotoShareLink<Label: View>: View {
    private let photo: URL
    private let title: String
    private let message: String
    private let label: Label
    @Environment(\.imageLoader) private var loader

    /// `title` names the photo's file and heads the share sheet; `message` travels with the photo where the app
    /// accepts text, such as Messages or Mail.
    public init(photo: URL, title: String, message: String, @ViewBuilder label: () -> Label) {
        self.photo = photo
        self.title = title
        self.message = message
        self.label = label()
    }

    public var body: some View {
        let item = ShareablePhoto(url: photo, name: title, loader: loader)
        ShareLink(item: item, subject: Text(title), message: Text(message), preview: SharePreview(title, image: item)) {
            label
        }
    }
}

/// Sharp on any phone, and still a few hundred kilobytes: small enough for any chat app.
private let sharedPixelSize = 2048

/// The photo as a JPEG file: the image CDN serves WebP, which some apps cannot open.
private struct ShareablePhoto: Transferable {
    let url: URL
    let name: String
    let loader: any ImageLoaderProtocol

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { photo in try await photo.jpegData() }
            .suggestedFileName { $0.name }
    }

    private func jpegData() async throws -> Data {
        let image: UIImage
        do {
            image = try await loader.image(for: url, maxPixelSize: sharedPixelSize)
        } catch {
            // Offline: the picture already on screen is still worth sending.
            guard let cached = loader.cachedImage(for: url) else { throw error }
            image = cached
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else { throw UnencodableImage() }
        return data
    }

    private struct UnencodableImage: Error {}
}
