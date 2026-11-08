import Catalog
import Foundation
import Images
import Networking

/// The services that live as long as the app: one HTTP client and one image loader, so their caches and
/// connections are shared by every screen.
@MainActor
final class AppContainer {
    let apiClient: APIClient
    let imageLoaderKind: ImageLoaderKind
    /// Pictures stay in memory only: the image CDN sends `no-store`, so `URLCache` keeps nothing on disk.
    let imageLoader: any ImageLoaderProtocol
    let catalog: CatalogFeature

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let scenario = UITestScenario(arguments: arguments)
        apiClient = APIClient(configuration: scenario?.sessionConfiguration() ?? .default)
        imageLoaderKind = ImageLoaderKind(arguments: arguments)
        imageLoader = DownsamplingImageLoader(fetch: scenario?.imageFetch)
        catalog = CatalogFeature(client: apiClient)
    }
}
