import DesignSystem
import SwiftUI

/// The product's photos on a soft stage, one per page. The first page opens on the list's thumbnail, already in
/// memory, so the photo is there in the first frame; tapping a photo opens it full screen.
struct ProductPhotoPager: View {
    let photos: [URL]
    /// The list's thumbnail, standing in for the first photo until that one loads.
    let thumbnail: URL
    @Binding var page: Int?
    let open: (_ page: Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tall enough to show the product, short enough that the name and price are on the first screen.
    private let height: CGFloat = 400
    /// The stage reaches this far above the page, so pulling the screen down shows more stage, not a white gap.
    private let overscroll: CGFloat = 600

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(pages) { photo in
                    Button {
                        open(photo.position)
                    } label: {
                        RemoteImage(
                            url: photo.url,
                            preview: photo.position == 0 ? thumbnail : nil,
                            inset: EdgeInsets(top: 84, leading: 48, bottom: 48, trailing: 48)
                        )
                    }
                    .buttonStyle(PhotoButtonStyle())
                    .containerRelativeFrame(.horizontal)
                    .accessibilityLabel("Photo \(photo.position + 1) of \(photos.count)")
                    .accessibilityHint("Opens full screen")
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        .frame(height: height)
        .clipShape(stage)
        .overlay(alignment: .bottom) { dots }
        .background { stage.fill(Color.tile).padding(.top, -overscroll) }
        .accessibilityIdentifier("detail-pager-photos")
    }

    private var stage: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32, style: .continuous)
    }

    /// A page is its place in the row, so the first page keeps its place (and its picture) when the thumbnail
    /// gives way to the full photos.
    private var pages: [Photo] {
        photos.enumerated().map { Photo(position: $0.offset, url: $0.element) }
    }

    @ViewBuilder private var dots: some View {
        if photos.count > 1 {
            HStack(spacing: 6) {
                ForEach(0..<photos.count, id: \.self) { index in
                    Capsule()
                        .fill(Color.ink.opacity(index == current ? 0.8 : 0.2))
                        .frame(width: index == current ? 18 : 6, height: 6)
                }
            }
            .animation(reduceMotion ? nil : .settle, value: current)
            .padding(.bottom, Spacing.l)
            .transition(.opacity)
            .accessibilityHidden(true)
        }
    }

    private var current: Int { page ?? 0 }

    private struct Photo: Identifiable {
        let position: Int
        let url: URL

        var id: Int { position }
    }
}

/// A photo dims a little under the finger: enough to say "this opens", without scaling a full-width picture.
private struct PhotoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.strongEaseOut, value: configuration.isPressed)
    }
}
