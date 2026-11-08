import CoreGraphics
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem

/// The light/dark button lives in DesignSystem, which has no test target of its own yet.
struct AppearanceToggleTests {
    @Test func aTapSwitchesToTheOppositeOfWhatTheScreenShows() {
        #expect(Appearance(oppositeOf: .light) == .dark)
        #expect(Appearance(oppositeOf: .dark) == .light)
    }

    /// Nothing stored means the merchant never chose, so the window follows the system.
    @Test func neverChosenFollowsTheSystem() {
        #expect(Appearance.system.interfaceStyle == .unspecified)
        #expect(Appearance.light.interfaceStyle == .light)
        #expect(Appearance.dark.interfaceStyle == .dark)
    }

    /// The stored strings are what earlier launches saved; renaming a case would forget the merchant's choice.
    @Test func storedValuesStayTheSame() {
        #expect(Appearance(rawValue: "light") == .light)
        #expect(Appearance(rawValue: "dark") == .dark)
        #expect(Appearance(rawValue: "system") == .system)
    }

    /// From the button near the bottom-right corner the farthest corner is the top-left one.
    @Test func revealGrowsToTheFarthestCorner() {
        let screen = CGRect(x: 0, y: 0, width: 300, height: 400)
        #expect(screen.farthestCornerDistance(from: CGPoint(x: 300, y: 400)) == 500)
        #expect(screen.farthestCornerDistance(from: CGPoint(x: 0, y: 0)) == 500)
        #expect(screen.farthestCornerDistance(from: CGPoint(x: 150, y: 200)) == 250)
    }
}
