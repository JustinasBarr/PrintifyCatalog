import DesignSystem
import SwiftUI

/// Home: the search field, the categories as chips that filter Home in place, then what the chips chose. While
/// the field has words, its matches show in place of the chips and everything below them.
struct HomeView: View {
    let viewModel: HomeViewModel
    let search: SearchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            if case .failed(let message) = viewModel.state.categories {
                LoadFailedView(
                    title: "Couldn't load your catalog",
                    message: message,
                    retryIdentifier: "home-button-retry",
                    isRetrying: viewModel.state.isRetrying
                ) {
                    await viewModel.retry()
                }
                .containerRelativeFrame(.vertical) { height, _ in height * 0.8 }
            } else {
                VStack(spacing: 0) {
                    SearchField(viewModel: search, productCount: viewModel.state.productCount)
                        .padding(.horizontal, Spacing.l)
                    if search.state.results == nil {
                        sections
                    } else {
                        SearchResults(viewModel: search, productCount: viewModel.state.productCount)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color.ground)
        .navigationTitle("Products")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            // Search results cover Home, so a pull over them must not reload Home out of sight.
            guard search.state.results == nil else { return }
            await viewModel.refresh()
        }
        .task { await viewModel.load() }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 0) {
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
