import SwiftUI

/// A short confirmation ("SKU copied") that slides in from the top and leaves on its own. It is the result
/// of an action, so it carries the success haptic; VoiceOver reads it aloud.
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    let duration: Duration
    let topInset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ground)
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.m)
                        .background(Color.ink, in: Capsule())
                        .lift()
                        .padding(.top, topInset + Spacing.s)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .accessibilityIdentifier("toast-label-message")
                        .task(id: message) { await dismiss(after: message) }
                }
            }
            .animation(.settle, value: message)
            .sensoryFeedback(.success, trigger: message) { _, new in new != nil }
    }

    private func dismiss(after shown: String) async {
        AccessibilityNotification.Announcement(shown).post()
        do {
            try await Task.sleep(for: duration)
        } catch {
            return
        }
        message = nil
    }
}

extension View {
    /// Shows `message` as a toast while it is set, then clears it after `duration`. `topInset` moves it below a
    /// bar of buttons drawn over the top of the screen, so it never covers them.
    public func toast(
        _ message: Binding<String?>,
        duration: Duration = .seconds(1.6),
        topInset: CGFloat = 0
    ) -> some View {
        modifier(ToastModifier(message: message, duration: duration, topInset: topInset))
    }
}
