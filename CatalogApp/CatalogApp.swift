import Catalog
import DesignSystem
import SwiftUI
import UIKit

@main
struct CatalogApp: App {
    @State private var container = AppContainer()

    init() {
        useSerifNavigationTitles()
    }

    var body: some Scene {
        WindowGroup {
            CatalogRootView(feature: container.catalog)
                .environment(\.imageLoader, container.imageLoader)
                .environment(\.imageLoaderKind, container.imageLoaderKind)
                .tint(Color.action)
        }
    }
}

/// New York for every navigation title, like the shelf titles. SwiftUI has no modifier for the bar's title font,
/// so it is set once on the bar's appearance.
@MainActor
private func useSerifNavigationTitles() {
    let bar = UINavigationBar.appearance()
    bar.largeTitleTextAttributes = [.font: boldSerif(.largeTitle)]
    bar.titleTextAttributes = [.font: boldSerif(.headline)]
}

private func boldSerif(_ style: UIFont.TextStyle) -> UIFont {
    let system = UIFont.preferredFont(forTextStyle: style)
    let serif = system.fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.traitBold) ?? system.fontDescriptor
    return UIFont(descriptor: serif, size: 0)
}
