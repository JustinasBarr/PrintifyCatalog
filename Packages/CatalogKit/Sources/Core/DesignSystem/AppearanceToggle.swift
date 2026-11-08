import SwiftUI
import UIKit

extension View {
    /// Floats the light/dark button in the bottom-right corner and applies the merchant's choice to the whole
    /// window, so covers and sheets follow it too. Put it on the root view, once.
    public func appearanceToggle() -> some View {
        modifier(AppearanceToggleModifier())
    }
}

/// The look the merchant chose with the button, stored by its raw value.
enum Appearance: String {
    /// Never chosen: the app follows the system.
    case system
    case light
    case dark

    /// The look a tap switches to: the opposite of what the screen shows now.
    init(oppositeOf colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .light : .dark
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct AppearanceToggleModifier: ViewModifier {
    @AppStorage("appearance") private var appearance = Appearance.system
    @State private var reveal = AppearanceReveal()
    @State private var isKeyboardShown = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let size: CGFloat = 44

    func body(content: Content) -> some View {
        content
            // The last row of a grid scrolls clear of the button instead of ending under it.
            .safeAreaPadding(.bottom, size + Spacing.l)
            .overlay(alignment: .bottomTrailing) {
                button
                    .padding([.trailing, .bottom], Spacing.l)
                    .opacity(isKeyboardShown ? 0 : 1)
                    .allowsHitTesting(!isKeyboardShown)
                    .animation(.strongEaseOut, value: isKeyboardShown)
                    .ignoresSafeArea(.keyboard)
            }
            .task { await follow(UIResponder.keyboardWillShowNotification, isShown: true) }
            .task { await follow(UIResponder.keyboardWillHideNotification, isShown: false) }
    }

    private var button: some View {
        let isDark = colorScheme == .dark
        let symbol = isDark ? "sun.max.fill" : "moon.fill"
        return Button(action: toggle) {
            AppearanceIcon(isDark: isDark)
                .foregroundStyle(Color.ink)
                .frame(width: size, height: size)
                .background(Color.raised, in: Circle())
                .lift()
        }
        .buttonStyle(.pressable)
        .background(WindowAnchor(reveal: reveal, appearance: appearance))
        .accessibilityRepresentation {
            Toggle("Dark mode", isOn: Binding(get: { isDark }, set: { _ in toggle() }))
        }
        .accessibilityIdentifier("app-button-appearance")
        .accessibilityShowsLargeContentViewer {
            Label("Dark mode", systemImage: symbol)
        }
    }

    private func toggle() {
        appearance = Appearance(oppositeOf: colorScheme)
        reveal.show(appearance, reduceMotion: reduceMotion)
    }

    private func follow(_ keyboardEvent: Notification.Name, isShown: Bool) async {
        for await _ in NotificationCenter.default.notifications(named: keyboardEvent) {
            isKeyboardShown = isShown
        }
    }
}

/// A UIKit view behind the button: it knows the window and where the button sits in it, and applies the stored
/// look as soon as it joins the window, before the first frame.
private struct WindowAnchor: UIViewRepresentable {
    let reveal: AppearanceReveal
    let appearance: Appearance

    func makeUIView(context: Context) -> AnchorView {
        let anchor = AnchorView()
        anchor.isUserInteractionEnabled = false
        reveal.anchor = anchor
        return anchor
    }

    func updateUIView(_ anchor: AnchorView, context: Context) {
        anchor.appearance = appearance
    }
}

private final class AnchorView: UIView {
    var appearance = Appearance.system

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window?.overrideUserInterfaceStyle = appearance.interfaceStyle
    }
}
