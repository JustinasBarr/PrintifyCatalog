import DesignSystem
import SwiftUI

/// The product list's sort and filter sheet. A pick applies at once, so the list changes behind the sheet; Done
/// closes it and Reset returns the list to how it opened.
struct SortFilterSheet: View {
    let viewModel: ProductListViewModel
    /// The attention list shows only what needs attention, so it has no filter to switch.
    let offersAttentionFilter: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    orders
                    if offersAttentionFilter {
                        attentionFilter
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.ground)
            .navigationTitle("Sort and filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buttons }
        }
        // Every row fits half the screen at the usual text sizes; the largest ones get the whole screen.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium])
        .presentationBackground(Color.ground)
    }

    private var orders: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Sort by")
                .font(.label)
                .foregroundStyle(Color.ink2)
                .padding(.leading, Spacing.l)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Product.Sort.allCases, id: \.self) { sort in
                    OrderRow(sort: sort, isPicked: viewModel.shownOrder == sort) {
                        Task { await viewModel.sort(by: sort) }
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
            .background(Color.tile, in: .rect(cornerRadius: Radius.card, style: .continuous))
            // The server sorts by `price`, the price before the discount, while cards show the price after it,
            // so two neighbours can look out of order; this line says why.
            Text("Prices sort before discounts.")
                .font(.footnote)
                .foregroundStyle(Color.ink2)
                .padding(.leading, Spacing.l)
        }
    }

    private var attentionFilter: some View {
        Toggle(isOn: needsAttentionOnly) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Needs attention only")
                    .font(.body)
                    .foregroundStyle(Color.ink)
                Text("Low stock and out of stock")
                    .font(.footnote)
                    .foregroundStyle(Color.ink2)
            }
        }
        .tint(Color.action)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(Color.tile, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .accessibilityIdentifier("sort-toggle-attention")
    }

    @ToolbarContentBuilder
    private var buttons: some ToolbarContent {
        if viewModel.isSortedOrFiltered {
            ToolbarItem(placement: .cancellationAction) {
                Button("Reset") { Task { await viewModel.resetSortFilter() } }
                    .accessibilityIdentifier("sort-button-reset")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
                .accessibilityIdentifier("sort-button-done")
        }
    }

    private var needsAttentionOnly: Binding<Bool> {
        Binding(
            get: { viewModel.state.sortFilter.needsAttentionOnly },
            set: { isOn in Task { await viewModel.showOnlyNeedingAttention(isOn) } }
        )
    }
}

/// One order: its name, and a check when it is the list's order.
private struct OrderRow: View {
    let sort: Product.Sort
    let isPicked: Bool
    let pick: () -> Void
    /// Grows with the text, so two-line rows at the largest sizes stay apart.
    @ScaledMetric(relativeTo: .body) private var verticalPadding = Spacing.s

    var body: some View {
        Button(action: pick) {
            HStack(spacing: Spacing.m) {
                Text(sort.name)
                    .font(.body)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.action)
                    .opacity(isPicked ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .accessibilityIdentifier("sort-option-\(sort.identifier)")
    }
}

extension Product.Sort {
    fileprivate var name: String {
        switch self {
        case .stockLowFirst: "Stock, lowest first"
        case .priceLowToHigh: "Price, low to high"
        case .priceHighToLow: "Price, high to low"
        case .ratingHighFirst: "Rating, highest first"
        case .nameAToZ: "Name, A to Z"
        }
    }

    fileprivate var identifier: String {
        switch self {
        case .stockLowFirst: "stockLow"
        case .priceLowToHigh: "priceLow"
        case .priceHighToLow: "priceHigh"
        case .ratingHighFirst: "rating"
        case .nameAToZ: "name"
        }
    }
}
