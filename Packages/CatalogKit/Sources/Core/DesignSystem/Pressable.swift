import SwiftUI

/// Cards answer a press: scale to 0.97, back on release; under Reduce Motion they dim instead. No haptic:
/// cards are pressed dozens of times a day, and haptics are kept for results.
public struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.strongEaseOut, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    public static var pressable: PressableStyle { PressableStyle() }
}
