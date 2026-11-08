import DesignSystem
import SwiftUI

/// What Home shows below its search field while the field has words: how many products match, then the matches
/// in the list's grid, paging as it scrolls.
struct SearchResults: View {
    let viewModel: SearchViewModel
    /// The catalog's size, for "18 of 194 products match"; nil until Home has it.
    let productCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            countLine
            ProductGrid(viewModel: viewModel, screen: "search", retryIdentifier: "search-button-retry", empty: noMatch)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("search-grid-results")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.xl)
    }

    @ViewBuilder
    private var countLine: some View {
        switch viewModel.state.results {
        case .loading:
            // The typed words are in the placeholder so a long query wraps here as it will in the answer.
            countText("18 of 194 products match “\(viewModel.state.text)”")
                .redacted(reason: .placeholder)
                .shimmering()
                .accessibilityHidden(true)
        case .loaded(let results) where !results.products.isEmpty:
            countText(count(results))
                .accessibilityIdentifier("search-text-count")
        case .loaded, .failed, nil:
            EmptyView()
        }
    }

    private func countText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.ink2)
            .padding(.top, Spacing.l)
            .padding(.leading, Spacing.xs)
    }

    /// "18 of 194 products match “red”". The total is the server's, across every page.
    private func count(_ results: SearchViewModel.Results) -> String {
        let verb = results.total == 1 ? "matches" : "match"
        guard let productCount else {
            return "\(results.total) \(results.total == 1 ? "product" : "products") \(verb) “\(results.query)”"
        }
        return "\(results.total) of \(productCount) products \(verb) “\(results.query)”"
    }

    private var noMatch: EmptyListView {
        EmptyListView(
            title: "No products match “\(viewModel.state.results?.value?.query ?? viewModel.state.text)”",
            message: "Search looks at product names and descriptions, not SKUs.",
            systemImage: "magnifyingglass",
            identifier: "search-text-empty"
        )
    }
}
