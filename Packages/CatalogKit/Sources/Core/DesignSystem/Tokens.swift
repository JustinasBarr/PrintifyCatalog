import SwiftUI

/// The spacing scale. Every gap and padding is one of these, so screens line up on one grid.
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    /// The screen's side margin: iOS's own on large phones.
    public static let page: CGFloat = 20
}

/// Corner radii, always with the `.continuous` style. Chips and pills use `Capsule` instead.
public enum Radius {
    /// Buttons and fields.
    public static let control: CGFloat = 10
    /// A product picture inside a card.
    public static let image: CGFloat = 12
    /// Cards and grid tiles.
    public static let card: CGFloat = 16
}

/// One motion vocabulary for the app: a strong ease-out for things that appear or settle, and a spring with
/// no bounce for things the finger moves. Retuning the app's feel is a change here.
extension Animation {
    /// `cubic-bezier(0.23, 1, 0.32, 1)`: starts fast, so the change answers at once.
    public static let strongEaseOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.25)
    public static let settle = Animation.spring(duration: 0.3, bounce: 0)
}

/// SF Pro text styles, so Dynamic Type scales every line.
extension Font {
    public static let screenTitle = Font.largeTitle.weight(.bold)
    public static let sectionTitle = Font.title3.weight(.semibold)
    public static let cardTitle = Font.subheadline.weight(.medium)
    /// Digits keep one width, so a price or a count never shifts its neighbours when it changes.
    public static let price = Font.headline.monospacedDigit()
    public static let label = Font.caption.weight(.semibold)
    /// New York for shelf titles on Home; screen titles get it from the navigation bar's appearance.
    public static let shelfTitle = Font.system(.title2, design: .serif, weight: .bold)
    /// A card's price: the size of its title, bold, so a grid row reads title then price at one size.
    public static let cardPrice = Font.subheadline.bold().monospacedDigit()
    /// A product's name on its own screen: New York, the one display voice next to SF Pro text.
    public static let productTitle = Font.system(.title, design: .serif, weight: .bold)
}

/// Cool neutral grounds and one accent. Each colour has a designed dark pair, not an inverted one.
///
/// Every text colour passes WCAG AA for small text (4.5:1) on `ground`, `tile` and `field` in both
/// appearances. Worst measured ratio: ink 14.29, ink2 5.52, ink3 4.68, action 5.77.
extension Color {
    /// The screen.
    public static let ground = Color(light: 0xFFFFFF, dark: 0x0B0D12)
    /// Cards and grid tiles, one step up from the ground.
    public static let tile = Color(light: 0xF3F4F7, dark: 0x171A21)
    /// Search fields and chips.
    public static let field = Color(light: 0xEEF0F4, dark: 0x1F232C)
    /// Titles and prices.
    public static let ink = Color(light: 0x0E1320, dark: 0xF2F4F8)
    /// Secondary text: brand, category.
    public static let ink2 = Color(light: 0x596070, dark: 0xA4ABBA)
    /// Quiet text: captions, counts.
    public static let ink3 = Color(light: 0x646B7B, dark: 0x8C93A3)
    /// Buttons and links. Named `action`, not `accent`, so it never clashes with the asset catalog's
    /// generated `AccentColor`.
    public static let action = Color(light: 0x3446E8, dark: 0x8A9BFF)
    /// Text on an `action` fill. White fails on the light dark-mode `action` (2.6:1), so dark mode uses the
    /// ground: 7.6:1. Light: 6.6:1.
    public static let onAction = Color(light: 0xFFFFFF, dark: 0x0B0D12)
    /// The rating star. It sits next to the number it stands for, so it is decoration, not the signal.
    public static let rating = Color(light: 0xF2A20C, dark: 0xFFC24D)
    public static let skeleton = Color(light: 0xE7E9EE, dark: 0x232731)

    /// Stock colours, always next to words and a count, never on their own. Each passes 4.5:1 on ground,
    /// tile, field and on its own 12% tint over a tile (a chip with a faint fill). Worst measured ratio:
    /// in 4.55, low 4.56, out 4.54 (all on their own tint in light mode).
    public static let stockIn = Color(light: 0x137345, dark: 0x4CC38A)
    public static let stockLow = Color(light: 0xA34A06, dark: 0xF5A55C)
    public static let stockOut = Color(light: 0xBD2828, dark: 0xFF8A80)

    /// The moving band of the loading shimmer: bright on light skeletons, a faint lift on dark ones.
    static let shimmerBand = Color(
        uiColor: UIColor { traits in
            UIColor.white.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.07 : 0.55)
        }
    )

    init(light: UInt32, dark: UInt32) {
        self.init(
            uiColor: UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

extension UIColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// The shadow for layers that float above the screen (a toast, a menu): a tight contact shadow plus a
    /// wide soft one. Cards on the ground stay flat.
    public func lift() -> some View {
        shadow(color: Color(red: 14 / 255, green: 19 / 255, blue: 32 / 255).opacity(0.04), radius: 1, y: 1)
            .shadow(color: Color(red: 14 / 255, green: 19 / 255, blue: 32 / 255).opacity(0.10), radius: 16, y: 8)
    }
}
