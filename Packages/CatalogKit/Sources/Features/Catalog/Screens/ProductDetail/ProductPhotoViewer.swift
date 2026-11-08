import DesignSystem
import SwiftUI

/// The photos full screen on black: swipe between them, pinch or double-tap to zoom, drag down or tap the button to
/// close. It hands back the photo it ended on, so the pager below shows the same one.
struct ProductPhotoViewer: View {
    let photos: [URL]
    /// The list's thumbnail, which stands in on the first page while the full photo loads.
    let thumbnail: URL
    let close: (_ page: Int) -> Void
    @State private var page: Int?
    @State private var isZoomed = false
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(photos: [URL], thumbnail: URL, start: Int, close: @escaping (_ page: Int) -> Void) {
        self.photos = photos
        self.thumbnail = thumbnail
        self.close = close
        _page = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity).ignoresSafeArea()
            pages
                .offset(y: reduceMotion ? 0 : drag)
                .simultaneousGesture(closeDrag, including: isZoomed ? .subviews : .all)
        }
        .overlay(alignment: .top) { bar }
        .opacity(contentOpacity)
        // The container comes right before its identifier; with modifiers in between, the identifier spreads to the
        // children and the close button loses its own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail-viewer-photos")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close(page ?? 0) }
    }

    private var pages: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                // A page is its place in the row, so the first page keeps its place when the thumbnail gives way to
                // the full photos.
                ForEach(photos.indices, id: \.self) { index in
                    ZoomablePhoto(url: photos[index], preview: index == 0 ? thumbnail : nil, isZoomed: $isZoomed)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .accessibilityElement()
                        .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
                        .accessibilityAddTraits(.isImage)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        .scrollDisabled(isZoomed)
        // A zoomed photo grows past the safe area to the screen's edges instead of stopping short of them.
        .scrollClipDisabled()
    }

    private var bar: some View {
        HStack {
            Text("\((page ?? 0) + 1) of \(photos.count)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityHidden(true)
            Spacer()
            Button {
                close(page ?? 0)
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.16), in: .circle)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Close photos")
            .accessibilityShowsLargeContentViewer { Label("Close photos", systemImage: "xmark") }
            .accessibilityIdentifier("detail-button-closeViewer")
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, Spacing.s)
        .opacity(drag == 0 ? 1 : 0)
        .animation(.strongEaseOut, value: drag == 0)
    }

    /// The black thins as the photo is pulled down, so the detail shows through before it is let go.
    private var backdropOpacity: Double { 1 - min(drag / 400, 0.6) }

    /// With Reduce Motion the photo stays put while dragged and the whole viewer fades instead.
    private var contentOpacity: Double { reduceMotion ? 1 - min(drag / 300, 0.7) : 1 }

    /// Only a mostly vertical drag closes, so a sideways swipe still turns the page. A quick flick is enough.
    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                drag = max(0, value.translation.height)
            }
            .onEnded { value in
                if drag > 0, value.translation.height > 140 || value.predictedEndTranslation.height > 400 {
                    close(page ?? 0)
                } else {
                    withAnimation(reduceMotion ? .strongEaseOut : .settle) { drag = 0 }
                }
            }
    }
}

/// One photo that zooms: pinch between 1× and 4×, double-tap to zoom in where the finger is, drag to look around
/// while zoomed. With Reduce Motion a double-tap jumps to the new size instead of animating there.
private struct ZoomablePhoto: View {
    let url: URL
    let preview: URL?
    @Binding var isZoomed: Bool
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maxScale: CGFloat = 4
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { proxy in
            RemoteImage(url: url, preview: preview)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(.rect)
                .gesture(magnify(in: proxy.size))
                .simultaneousGesture(pan(in: proxy.size), including: scale > 1 ? .all : .subviews)
                .onTapGesture(count: 2) { location in
                    toggleZoom(at: location, in: proxy.size)
                }
        }
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(settledScale * value.magnification, 1), maxScale)
                offset = clamped(settledOffset * (scale / settledScale), in: size)
            }
            .onEnded { _ in
                settle(scale: scale < 1.1 ? 1 : scale, offset: offset, in: size)
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(settledOffset + value.translation, in: size)
            }
            .onEnded { _ in
                settledOffset = offset
            }
    }

    /// Zooms in keeping the tapped point under the finger, or back out to the whole photo.
    private func toggleZoom(at location: CGPoint, in size: CGSize) {
        guard scale == 1 else {
            settle(scale: 1, offset: .zero, in: size, animated: true)
            return
        }
        let fromCenter = CGSize(width: location.x - size.width / 2, height: location.y - size.height / 2)
        settle(scale: doubleTapScale, offset: fromCenter * (1 - doubleTapScale), in: size, animated: true)
    }

    private func settle(scale newScale: CGFloat, offset newOffset: CGSize, in size: CGSize, animated: Bool = false) {
        let target = newScale == 1 ? .zero : clamped(newOffset, in: size, at: newScale)
        withAnimation(animated && !reduceMotion ? .settle : nil) {
            scale = newScale
            offset = target
        }
        settledScale = newScale
        settledOffset = target
        isZoomed = newScale > 1
    }

    /// Keeps the zoomed photo covering its frame: it can be moved until an edge reaches the screen's edge.
    private func clamped(_ offset: CGSize, in size: CGSize, at zoom: CGFloat? = nil) -> CGSize {
        let overflow = (zoom ?? scale) - 1
        let limit = CGSize(width: size.width * overflow / 2, height: size.height * overflow / 2)
        return CGSize(
            width: min(max(offset.width, -limit.width), limit.width),
            height: min(max(offset.height, -limit.height), limit.height)
        )
    }
}

extension CGSize {
    fileprivate static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }

    fileprivate static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}
