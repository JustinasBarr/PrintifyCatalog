import DesignSystem
import SwiftUI

/// The facts a merchant acts on, in one card: the codes to copy, ordering, shipping, aftercare and the product's
/// measurements. Without a product it draws the same rows with redacted values, so the loaded card takes its place
/// without a line moving.
struct ProductFactsCard: View {
    let product: Product?
    /// Puts `value` on the pasteboard and confirms it with `confirmation`.
    let copy: (_ value: String, _ confirmation: String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            copyRow(
                "SKU",
                icon: "number",
                value: product?.sku ?? "XXX-XXX-XXX-000",
                confirmation: "SKU copied",
                identifier: "detail-button-copySKU"
            )
            copyRow(
                "Barcode",
                icon: "barcode",
                value: product?.meta.barcode ?? "0000000000000",
                confirmation: "Barcode copied",
                identifier: "detail-button-copyBarcode"
            )
            FactRow("Minimum order", icon: "square.stack.3d.up", value: minimumOrder, isLoading: isLoading)
            FactRow(
                "Shipping",
                icon: "shippingbox",
                value: product?.shippingInformation ?? "Ships in 1 week",
                isLoading: isLoading
            )
            FactRow(
                "Warranty",
                icon: "checkmark.shield",
                value: product?.warrantyInformation ?? "1 year warranty",
                isLoading: isLoading
            )
            FactRow(
                "Returns",
                icon: "arrow.uturn.backward",
                value: product?.returnPolicy ?? "30 days return policy",
                isLoading: isLoading
            )
            FactRow("Weight", icon: "scalemass", value: weight, isLoading: isLoading)
            FactRow("Size", icon: "ruler", value: size, spokenValue: spokenSize, isLoading: isLoading)
            FactRow("Updated", icon: "clock.arrow.circlepath", value: updated, isLoading: isLoading)
        }
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Spacing.l)
        .background(Color.tile, in: .rect(cornerRadius: Radius.card, style: .continuous))
    }

    private var isLoading: Bool { product == nil }

    private func copyRow(
        _ label: String,
        icon: String,
        value: String,
        confirmation: String,
        identifier: String
    ) -> some View {
        Button {
            copy(value, confirmation)
        } label: {
            FactRow(label, icon: icon, value: value, isLoading: isLoading, valueFont: .subheadline.monospaced()) {
                Image(systemName: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.action)
                    .opacity(isLoading ? 0 : 1)
            }
        }
        .buttonStyle(FactRowButtonStyle())
        .disabled(isLoading)
        .accessibilityHint("Copies the \(label == "SKU" ? "SKU" : label.lowercased())")
        .accessibilityIdentifier(identifier)
    }

    private var minimumOrder: String {
        product.map { "\($0.minimumOrderQuantity)" } ?? "00"
    }

    // The API sends weight and dimensions without units, so none is added here.
    private var weight: String { product.map { $0.weight.formatted() } ?? "0.0" }

    private var size: String {
        guard let dimensions = product?.dimensions else { return "W 00.00 · H 00.00 · D 00.00" }
        return
            "W \(dimensions.width.formatted()) · H \(dimensions.height.formatted()) · D \(dimensions.depth.formatted())"
    }

    private var spokenSize: String {
        guard let dimensions = product?.dimensions else { return "" }
        return "Width \(dimensions.width.formatted()), height \(dimensions.height.formatted()), "
            + "depth \(dimensions.depth.formatted())"
    }

    private var updated: String {
        product.map { $0.meta.updatedAt.formatted(.relative(presentation: .named, unitsStyle: .wide)) }
            ?? "0 days ago"
    }
}

/// One fact: an icon, its name and its value. The name stays readable while the value loads; at accessibility text
/// sizes the value moves under the name instead of squeezing it.
private struct FactRow<Accessory: View>: View {
    let label: String
    let icon: String
    let value: String
    var spokenValue: String?
    let isLoading: Bool
    var valueFont: Font = .subheadline
    @ViewBuilder let accessory: Accessory
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth = 24

    init(
        _ label: String,
        icon: String,
        value: String,
        spokenValue: String? = nil,
        isLoading: Bool,
        valueFont: Font = .subheadline,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.label = label
        self.icon = icon
        self.value = value
        self.spokenValue = spokenValue
        self.isLoading = isLoading
        self.valueFont = valueFont
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: Spacing.m) {
            Image(systemName: icon)
                .foregroundStyle(Color.ink3)
                .frame(width: iconWidth)
            nameAndValue
            accessory
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .padding(.vertical, Spacing.xs)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isLoading ? "Loading" : spokenValue ?? value)
    }

    @ViewBuilder private var nameAndValue: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                name
                valueText.multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            name
            Spacer(minLength: Spacing.m)
            valueText.multilineTextAlignment(.trailing)
        }
    }

    private var name: some View {
        Text(label).foregroundStyle(Color.ink2)
    }

    private var valueText: some View {
        Text(value)
            .font(valueFont.weight(.medium))
            .foregroundStyle(Color.ink)
            .redacted(reason: isLoading ? .placeholder : [])
            .shimmering(isLoading)
    }
}

/// A copy row answers a press with the grouped-list highlight, the press state iOS users know from Settings.
private struct FactRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Spacing.s)
            .background(
                Color.ink.opacity(configuration.isPressed ? 0.06 : 0),
                in: .rect(cornerRadius: Radius.control, style: .continuous)
            )
            .padding(.horizontal, -Spacing.s)
    }
}
