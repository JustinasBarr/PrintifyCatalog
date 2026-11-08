import SwiftUI

/// The App Store card zoom on iOS 18 and later; on iOS 17 the system's plain cover. Call sites are the same
/// on both.
extension View {
    /// Marks the view a detail zooms out of, such as a grid cell.
    @ViewBuilder
    public func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Marks the presented detail that zooms out of the source with the same `id`.
    @ViewBuilder
    public func zoomDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
