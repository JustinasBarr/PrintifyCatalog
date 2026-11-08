import DesignSystem
import SwiftUI
import UIKit

/// One product for the merchant: photos, name, price and stock at once from the list, then the facts to copy and what
/// customers said. Restock is the main button; Share, beside Close, sends it to a customer. Presented over the list;
/// it zooms out of the tapped cell when the list passes its namespace.
struct ProductDetailView: View {
    @State private var viewModel: ProductDetailViewModel
    private let zoomNamespace: Namespace.ID?
    @State private var photoPage: Int? = 0
    /// The photo the full-screen viewer shows, while it is open.
    @State private var viewerPage: Int?
    @State private var toast: String?
    /// What the restock sheet last showed, so it keeps drawing it while it slides away instead of emptying mid-slide.
    @State private var lastRestock: ProductDetailViewModel.Restock?
    @State private var topBarBottom: CGFloat = 0
    @State private var isPhotoScrolledAway = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `zoomNamespace` is the list's: the cell marked `zoomSource(id: product.id, in:)` becomes this screen.
    init(viewModel: ProductDetailViewModel, zoomNamespace: Namespace.ID? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.zoomNamespace = zoomNamespace
    }

    private var state: ProductDetailViewModel.State { viewModel.state }

    var body: some View {
        if let zoomNamespace {
            screen.zoomDestination(id: state.summary.id, in: zoomNamespace)
        } else {
            screen
        }
    }

    private var screen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                ProductPhotoPager(photos: state.photos, thumbnail: state.summary.thumbnail, page: $photoPage) {
                    openViewer(at: $0)
                }
                .onGeometryChange(for: Bool.self) { [topBarBottom] in
                    $0.frame(in: .global).maxY < topBarBottom
                } action: {
                    isPhotoScrolledAway = $0
                }
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    ProductHeader(summary: state.header)
                    details
                }
                .padding(.horizontal, Spacing.page)
            }
            .padding(.bottom, Spacing.xl)
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .background(Color.ground)
        .overlay(alignment: .top) { topBar }
        .safeAreaInset(edge: .bottom) { restockBar }
        .toast($toast, topInset: TopBarIcon.height)
        .overlay { viewer }
        .statusBarHidden(viewerPage != nil)
        .sheet(isPresented: isRestocking) { restockSheet }
        .onChange(of: state.restock) { _, restock in
            if let restock { lastRestock = restock }
        }
        .onChange(of: state.restockedStock) { _, stock in
            if let stock { toast = "Stock updated to \(stock)" }
        }
        .task { await viewModel.load() }
    }

    /// Loading and loaded draw the same rows, so swapping one for the other is a cross-fade in place. They overlap
    /// in a `ZStack` while it runs: in the page's `VStack` the leaving copy would push the arriving one down.
    private var details: some View {
        ZStack(alignment: .top) {
            switch state.product {
            case .loading:
                ProductDetails(product: nil, reviews: nil, copy: copy)
                    .transition(.opacity)
            case .loaded(let product):
                ProductDetails(product: product, reviews: state.reviews, copy: copy)
                    .transition(.opacity)
            case .failed(let message):
                LoadFailedCard(message: message) {
                    Task { await viewModel.retry() }
                }
                .transition(.opacity)
            }
        }
        .animation(.strongEaseOut, value: state.product)
    }

    /// Drawn over the screen rather than presented, so it fades and settles with the app's own curve; a system cover
    /// would slide up first.
    @ViewBuilder private var viewer: some View {
        if let viewerPage {
            ProductPhotoViewer(
                photos: state.photos,
                thumbnail: state.summary.thumbnail,
                start: viewerPage,
                close: closeViewer
            )
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    /// Over the photo it is only the share and close buttons. Once the photo has scrolled under them, a band of the
    /// page colour fades in behind them, so the clock and the buttons never sit on top of the facts.
    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            shareButton
            closeButton
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Spacing.page - Spacing.xs)
        .padding(.bottom, Spacing.xs)
        .background(alignment: .top) { topBarBand }
        .onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .global).maxY
        } action: {
            topBarBottom = $0
        }
    }

    /// Its lower edge fades out like the restock bar's, so text scrolling under it fades rather than being cut.
    private var topBarBand: some View {
        VStack(spacing: 0) {
            Color.ground
            LinearGradient(colors: [Color.ground, Color.ground.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: Spacing.l)
        }
        .padding(.bottom, -Spacing.l)
        .ignoresSafeArea(edges: .top)
        .opacity(isPhotoScrolledAway ? 1 : 0)
        .allowsHitTesting(isPhotoScrolledAway)
        .animation(.strongEaseOut, value: isPhotoScrolledAway)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            TopBarIcon(systemName: "xmark")
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Close")
        .accessibilityShowsLargeContentViewer { Label("Close", systemImage: "xmark") }
        .accessibilityIdentifier("detail-button-close")
    }

    /// Everything a customer needs is in the list's summary, so sharing works before the full product arrives. No
    /// haptic: `ShareLink` never says whether the person sent it or cancelled.
    private var shareButton: some View {
        let header = state.header
        let price = header.discountedPrice.formatted(.currency(code: "USD"))
        return PhotoShareLink(photo: state.photos[0], title: header.title, message: "\(header.title) – \(price)") {
            TopBarIcon(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Share product")
        .accessibilityHint("Sends its photo, name and price")
        .accessibilityShowsLargeContentViewer { Label("Share product", systemImage: "square.and.arrow.up") }
        .accessibilityIdentifier("detail-button-share")
    }

    /// The merchant's main job on this screen. Its text stops growing at the first accessibility size, where it still
    /// fits one line; past that it would cover a sixth of the screen.
    private var restockBar: some View {
        Button {
            viewModel.startRestock()
        } label: {
            Label("Restock", systemImage: "shippingbox")
                .font(.headline)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(Color.onAction)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.action, in: .capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Adds stock to this product")
        .accessibilityShowsLargeContentViewer { Label("Restock", systemImage: "shippingbox") }
        .accessibilityIdentifier("detail-button-restock")
        .padding(.horizontal, Spacing.page)
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.s)
        .background {
            LinearGradient(colors: [Color.ground.opacity(0), Color.ground], startPoint: .top, endPoint: .center)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var isRestocking: Binding<Bool> {
        Binding {
            viewModel.state.restock != nil
        } set: { isPresented in
            if !isPresented { viewModel.cancelRestock() }
        }
    }

    @ViewBuilder private var restockSheet: some View {
        if let restock = state.restock ?? lastRestock {
            RestockSheet(
                title: state.header.title,
                restock: restock,
                changeQuantity: { viewModel.changeRestockQuantity(to: $0) },
                confirm: { Task { await viewModel.confirmRestock() } },
                cancel: { viewModel.cancelRestock() }
            )
        }
    }

    private func copy(_ value: String, confirmation: String) {
        UIPasteboard.general.string = value
        toast = confirmation
    }

    private func openViewer(at page: Int) {
        withAnimation(.strongEaseOut) { viewerPage = page }
    }

    private func closeViewer(on page: Int) {
        photoPage = page
        withAnimation(.strongEaseOut) { viewerPage = nil }
    }
}

/// A glyph in a page-colour circle that lifts off the photo. The glyph stops growing where it would leave the circle;
/// at accessibility sizes a long press shows it large.
private struct TopBarIcon: View {
    /// The touch target; the circle drawn inside it is smaller.
    static let height: CGFloat = 44

    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.bold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(Color.ink2)
            .frame(width: 36, height: 36)
            .background(Color.ground, in: .circle)
            .lift()
            .frame(width: TopBarIcon.height, height: TopBarIcon.height)
            .contentShape(.circle)
    }
}

/// The facts, the description and the reviews: placeholders while the product loads, the real ones once it has.
private struct ProductDetails: View {
    let product: Product?
    let reviews: [Product.Review]?
    let copy: (_ value: String, _ confirmation: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            ProductFactsCard(product: product, copy: copy)
            ProductDescription(text: product?.description)
            ProductReviews(reviews: reviews)
        }
    }
}

/// The product's own words. While it loads, three redacted lines hold its place.
private struct ProductDescription: View {
    let text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Description")
                .font(.sectionTitle)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            Text(text ?? placeholder)
                .font(.subheadline)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .redacted(reason: text == nil ? .placeholder : [])
                .shimmering(text == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholder: String {
        "A product description runs to about this length on screen: two or three short lines of plain words that "
            + "say what the product is and why a customer buys it."
    }
}

/// The header stays; this takes the facts' place and says what went wrong and how to get them. One row, so on a
/// standard phone the whole card, button included, ends above the Restock bar; at accessibility sizes it stacks.
private struct LoadFailedCard: View {
    let message: String
    let retry: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.m))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.m))
        layout {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("The details didn't load")
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: retry) {
                Text("Try again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.action)
                    .padding(.horizontal, Spacing.l)
                    .frame(minHeight: 44)
                    .background(Color.action.opacity(0.12), in: .capsule)
            }
            .buttonStyle(.pressable)
            .fixedSize()
            .accessibilityIdentifier("detail-button-retry")
        }
        .padding(Spacing.l)
        .background(Color.tile, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
