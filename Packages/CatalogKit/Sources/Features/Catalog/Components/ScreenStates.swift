import DesignSystem
import SwiftUI

/// A screen that could not load anything: what happened in plain words and the one way out.
struct LoadFailedView: View {
    let title: String
    let message: String
    let retryIdentifier: String
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title).font(.shelfTitle).foregroundStyle(Color.ink)
            } icon: {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.ink3)
            }
        } description: {
            Text(message).foregroundStyle(Color.ink2)
        } actions: {
            Button("Try again") { Task { await retry() } }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Color.action)
                .foregroundStyle(Color.onAction)
                .accessibilityIdentifier(retryIdentifier)
        }
    }
}

/// A pull to refresh that failed over content that stays: one quiet line above it, with the way to try again.
struct RefreshFailedNotice: View {
    let message: String
    let retryIdentifier: String
    let retry: () async -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.ink3)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Try again") { Task { await retry() } }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.action)
                .frame(minHeight: 44)
                .accessibilityIdentifier(retryIdentifier)
        }
        .padding(.leading, Spacing.l)
        .padding(.trailing, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .background(Color.tile, in: .rect(cornerRadius: Radius.card, style: .continuous))
    }
}

/// A list with nothing in it, said plainly.
struct EmptyListView: View {
    let title: String
    let message: String
    let systemImage: String
    let identifier: String

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title).font(.shelfTitle).foregroundStyle(Color.ink)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(Color.ink3)
            }
        } description: {
            Text(message).foregroundStyle(Color.ink2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
