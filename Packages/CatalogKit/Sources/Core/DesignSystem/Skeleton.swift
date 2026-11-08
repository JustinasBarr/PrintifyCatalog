import SwiftUI

/// How long a placeholder waits before it shimmers: a fast load must not flicker.
private let slowLoad = Duration.milliseconds(400)

/// Every band on screen reads one clock, so a grid of skeletons shimmers as one sweep instead of each cell
/// starting when it appeared. The placeholder draws at once and the band fades in only once the load is slow. With
/// Reduce Motion on, the placeholder stays still.
struct Shimmer: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSlow = false
    private let period = 1.3

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive && isSlow && !reduceMotion {
                    TimelineView(.animation) { timeline in
                        GeometryReader { proxy in
                            LinearGradient(
                                colors: [.clear, .shimmerBand, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: proxy.size.width * 0.6)
                            .offset(x: phase(at: timeline.date) * proxy.size.width * 1.6)
                        }
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .task(id: isActive) { await waitForSlowLoad() }
    }

    private func waitForSlowLoad() async {
        isSlow = false
        guard isActive else { return }
        do {
            try await Task.sleep(for: slowLoad)
        } catch {
            return
        }
        withAnimation(.strongEaseOut) { isSlow = true }
    }

    /// From -1 to 1 once per period, linear: constant motion has no easing.
    private func phase(at date: Date) -> CGFloat {
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return CGFloat(progress * 2 - 1)
    }
}

extension View {
    /// The moving band, clipped to this view's shapes. Pair it with `.redacted(reason: .placeholder)` on the
    /// real view, so the skeleton has exactly the loaded layout; pass `false` once the content has loaded.
    public func shimmering(_ isActive: Bool = true) -> some View {
        modifier(Shimmer(isActive: isActive))
    }
}
