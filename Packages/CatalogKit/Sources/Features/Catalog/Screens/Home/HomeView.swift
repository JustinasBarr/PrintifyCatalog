import DesignSystem
import SwiftUI

/// Home: the search field, the categories as chips that filter Home in place, then what the chips chose.
struct HomeView: View {
    let viewModel: HomeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            if case .failed(let message) = viewModel.state.categories {
                LoadFailedView(
                    title: "Couldn't load your catalog",
                    message: message,
                    retryIdentifier: "home-button-retry"
                ) {
                    await viewModel.retry()
                }
                .containerRelativeFrame(.vertical) { height, _ in height * 0.8 }
            } else {
                sections
            }
        }
        .background(Color.ground)
        .navigationTitle("Products")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchField(productCount: viewModel.state.productCount)
                .padding(.horizontal, Spacing.l)
            if let failure = viewModel.state.refreshFailure {
                RefreshFailedNotice(message: failure, retryIdentifier: "home-button-retryRefresh") {
                    await viewModel.refresh()
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.m)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            CategoryChips(viewModel: viewModel)
                .padding(.top, Spacing.m)
            HomeSections(viewModel: viewModel)
        }
        .padding(.bottom, Spacing.xxl)
        .animation(.strongEaseOut, value: viewModel.state.refreshFailure)
    }
}

/// Where search will be. The API searches names only, and search results come in a later step, so the field
/// is shown with the catalog's size but takes no input yet.
private struct SearchField: View {
    let productCount: Int?

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.ink)
                .accessibilityHidden(true)
            TextField(prompt, text: .constant(""))
                .disabled(true)
                .accessibilityIdentifier("home-field-search")
        }
        .font(.body)
        .padding(.horizontal, Spacing.m)
        .frame(minHeight: 44)
        .background(Color.ground, in: .capsule)
        .overlay { Capsule().strokeBorder(Color.field, lineWidth: 1) }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private var prompt: String {
        productCount.map { "Search \($0) products" } ?? "Search products"
    }
}

/// Toggles that filter Home: "All", then one chip per category in the shelves' order. "All" is chosen when no
/// category is, and tapping it clears the choice.
private struct CategoryChips: View {
    let viewModel: HomeViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s) {
                switch viewModel.state.categories {
                case .loaded(let categories):
                    chip("All", isChosen: chosen.isEmpty, identifier: "home-chip-all") {
                        viewModel.clearCategories()
                    }
                    ForEach(categories) { category in
                        chip(
                            category.name,
                            isChosen: chosen.contains(category),
                            identifier: "home-chip-\(category.slug)"
                        ) {
                            viewModel.toggleCategory(category)
                        }
                    }
                case .loading, .failed:
                    ForEach(["All", "Beauty", "Fragrances", "Furniture"], id: \.self) { name in
                        Chip(name: name, isChosen: false)
                    }
                    .redacted(reason: .placeholder)
                    .shimmering()
                    .accessibilityHidden(true)
                }
            }
        }
        .contentMargins(.horizontal, Spacing.l, for: .scrollContent)
        .scrollIndicators(.hidden)
        .animation(.strongEaseOut, value: viewModel.state.categories.value == nil)
    }

    private var chosen: [Product.Category] {
        viewModel.state.selectedCategories
    }

    private func chip(
        _ name: String,
        isChosen: Bool,
        identifier: String,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            Chip(name: name, isChosen: isChosen)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// A pill: 36 pt to the eye, 44 pt to the finger. A chosen chip is filled and checked, never colour alone. Both
/// looks are always laid out and cross-fade, so a chip keeps its width and the chips after it never move.
private struct Chip: View {
    let name: String
    let isChosen: Bool

    var body: some View {
        ZStack {
            Text(name)
                .foregroundStyle(Color.ink)
                .opacity(isChosen ? 0 : 1)
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                Text(name)
            }
            .foregroundStyle(Color.onAction)
            .opacity(isChosen ? 1 : 0)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(isChosen ? Color.action : Color.field, in: .capsule)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .animation(.strongEaseOut, value: isChosen)
    }
}
