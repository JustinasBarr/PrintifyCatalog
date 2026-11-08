import DesignSystem
import SwiftUI

/// Stock as a merchant reads it at a glance: an icon, words and the count, tinted by state. Colour is never
/// the only signal, so it reads the same in grayscale and to VoiceOver.
struct StockChip: View {
    let availability: Product.Availability
    let stock: Int

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                .imageScale(.small)
            Text(text)
                .lineLimit(1)
        }
        .font(.label.monospacedDigit())
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(tint.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private var text: String {
        switch availability {
        case .inStock: "In stock · \(stock)"
        case .lowStock: "Low · \(stock) left"
        case .outOfStock: "Out of stock"
        }
    }

    private var spokenText: String {
        switch availability {
        case .inStock: "In stock, \(stock)"
        case .lowStock: "Low stock, \(stock) left"
        case .outOfStock: "Out of stock"
        }
    }

    private var symbol: String {
        switch availability {
        case .inStock: "checkmark.circle.fill"
        case .lowStock: "exclamationmark.circle.fill"
        case .outOfStock: "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch availability {
        case .inStock: .stockIn
        case .lowStock: .stockLow
        case .outOfStock: .stockOut
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.m) {
        StockChip(availability: .inStock, stock: 48)
        StockChip(availability: .lowStock, stock: 4)
        StockChip(availability: .outOfStock, stock: 0)
    }
    .padding()
    .background(Color.tile)
}
