import DesignSystem
import SwiftUI

/// Home's search field. Typing searches in place: the matches replace Home below the field until it is cleared
/// or closed with the round button beside it.
struct SearchField: View {
    let viewModel: SearchViewModel
    let productCount: Int?
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The glyphs stop growing here so they stay inside their 44-point buttons; the words keep growing.
    private let glyphLimit = DynamicTypeSize.xxxLarge

    var body: some View {
        HStack(spacing: Spacing.m) {
            field
            if isOpen {
                closeButton
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.strongEaseOut, value: isOpen)
        .task(id: viewModel.state.text) { await viewModel.search() }
    }

    private var isOpen: Bool {
        isFocused || !viewModel.state.text.isEmpty
    }

    private var field: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.ink)
                .dynamicTypeSize(...glyphLimit)
                .accessibilityHidden(true)
            TextField(prompt, text: text)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                // The matches arrive as typing pauses, so the Search key only lowers the keyboard over them.
                .onSubmit { isFocused = false }
                .accessibilityIdentifier("search-field-query")
            if !viewModel.state.text.isEmpty {
                Button {
                    viewModel.textChanged("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.ink)
                        .dynamicTypeSize(...glyphLimit)
                        .frame(width: 32, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("search-button-clear")
            }
        }
        .font(.body)
        .padding(.leading, Spacing.m)
        .padding(.trailing, viewModel.state.text.isEmpty ? Spacing.m : Spacing.xs)
        .frame(minHeight: 44)
        .background(Color.ground, in: .capsule)
        .overlay { Capsule().strokeBorder(Color.field, lineWidth: 1) }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private var closeButton: some View {
        Button {
            isFocused = false
            viewModel.close()
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.ink)
                .dynamicTypeSize(...glyphLimit)
                .frame(width: 44, height: 44)
                .background(Color.ground, in: .circle)
                .overlay { Circle().strokeBorder(Color.field, lineWidth: 1) }
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Close search")
        .accessibilityIdentifier("search-button-close")
    }

    private var text: Binding<String> {
        Binding(get: { viewModel.state.text }, set: { viewModel.textChanged($0) })
    }

    private var prompt: String {
        productCount.map { "Search \($0) products" } ?? "Search products"
    }
}
