import DesignSystem
import SwiftUI

/// Adds stock to one product: how many arrived, what the stock becomes, then Confirm. No cost line: the API has no
/// supplier cost, and the selling price would be the wrong number. While it sends, nothing can close it, so the
/// merchant never wonders whether a cancelled restock went through.
struct RestockSheet: View {
    let title: String
    let restock: ProductDetailViewModel.Restock
    let changeQuantity: @MainActor (Int) -> Void
    let confirm: () -> Void
    let cancel: () -> Void

    private var isSending: Bool { restock.status == .sending }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            heading
            VStack(spacing: 0) {
                quantity
                Divider().padding(.leading, Spacing.l)
                newStock
            }
            .background(Color.tile, in: .rect(cornerRadius: Radius.card, style: .continuous))
            if case .failed(let message) = restock.status {
                failure(message)
            }
            Spacer(minLength: 0)
            buttons
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.s)
        .animation(.strongEaseOut, value: restock.status)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.ground)
        .interactiveDismissDisabled(isSending)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Restock")
                .font(.sectionTitle)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.ink2)
                .lineLimit(2)
        }
    }

    private var quantity: some View {
        Stepper(
            value: Binding(get: { restock.quantity }, set: changeQuantity),
            in: ProductDetailViewModel.Restock.quantities
        ) {
            HStack {
                Text("Add")
                    .foregroundStyle(Color.ink2)
                Spacer()
                Text(restock.quantity, format: .number)
                    .font(.price)
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText(value: Double(restock.quantity)))
            }
        }
        .disabled(isSending)
        .padding(.horizontal, Spacing.l)
        .frame(minHeight: 56)
        .accessibilityValue("\(restock.quantity)")
        .accessibilityIdentifier("restock-stepper-quantity")
    }

    private var newStock: some View {
        HStack {
            Text("Stock")
                .foregroundStyle(Color.ink2)
            Spacer()
            Text("\(restock.stock) → \(restock.newStock)")
                .font(.price)
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText(value: Double(restock.newStock)))
        }
        .padding(.horizontal, Spacing.l)
        .frame(minHeight: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stock goes from \(restock.stock) to \(restock.newStock)")
        .accessibilityIdentifier("restock-label-stock")
    }

    private func failure(_ message: String) -> some View {
        Label {
            Text(message).foregroundStyle(Color.ink)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.stockOut)
        }
        .font(.subheadline)
        .transition(.opacity)
        .accessibilityIdentifier("restock-label-error")
    }

    private var buttons: some View {
        VStack(spacing: Spacing.xs) {
            Button(action: confirm) {
                ZStack {
                    if isSending {
                        ProgressView().tint(Color.onAction)
                    } else {
                        Text(confirmTitle)
                    }
                }
                .font(.headline)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(Color.onAction)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.action, in: .capsule)
            }
            .buttonStyle(.pressable)
            .disabled(isSending)
            .accessibilityLabel(isSending ? "Sending" : confirmTitle)
            .accessibilityIdentifier("restock-button-confirm")
            Button("Cancel", action: cancel)
                .font(.headline)
                .foregroundStyle(Color.ink2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
                .buttonStyle(.pressable)
                .disabled(isSending)
                .accessibilityIdentifier("restock-button-cancel")
        }
    }

    private var confirmTitle: String {
        if case .failed = restock.status { return "Try again" }
        return "Confirm"
    }
}
