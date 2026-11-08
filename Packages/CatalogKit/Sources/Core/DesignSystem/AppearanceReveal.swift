import UIKit

/// Switches the window's look under a snapshot of the old one, then opens a circular hole in the snapshot from
/// the button until it passes the farthest corner. Core Animation draws the circle off the main thread, so it
/// stays smooth while every screen redraws in the new colours.
@MainActor
final class AppearanceReveal {
    /// Longer than the controls' 250 ms: the circle crosses the whole screen, and in 250 ms it reads as a flash.
    private let duration: CFTimeInterval = 0.45
    private let reducedMotionDuration: CFTimeInterval = 0.2
    weak var anchor: UIView?
    private var overlay: RevealOverlay?

    func show(_ appearance: Appearance, reduceMotion: Bool) {
        guard let anchor, let window = anchor.window else { return }
        let wasRevealing = finish()
        // An interrupted reveal is still on screen until the next frame, so the snapshot waits for that frame.
        guard let snapshot = window.snapshotView(afterScreenUpdates: wasRevealing) else {
            window.overrideUserInterfaceStyle = appearance.interfaceStyle
            return
        }
        let button = anchor.convert(anchor.bounds, to: window)
        let overlay = RevealOverlay(frame: window.bounds, passingTouchesIn: button)
        overlay.addSubview(snapshot)
        window.addSubview(overlay)
        self.overlay = overlay
        // Without this the system status bar fades on its own and its clock goes faint over the new look.
        UIView.performWithoutAnimation { window.overrideUserInterfaceStyle = appearance.interfaceStyle }
        if reduceMotion {
            fadeOut(overlay)
        } else {
            openHole(in: overlay, from: CGPoint(x: button.midX, y: button.midY), startRadius: button.width / 2)
        }
    }

    /// Removes the overlay of a reveal still running; the window already has its new look underneath.
    @discardableResult
    private func finish() -> Bool {
        guard let overlay else { return false }
        overlay.removeFromSuperview()
        self.overlay = nil
        return true
    }

    private func openHole(in overlay: UIView, from center: CGPoint, startRadius: CGFloat) {
        let bounds = overlay.bounds
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        mask.path = path(of: bounds, holeAt: center, radius: bounds.farthestCornerDistance(from: center))
        overlay.layer.mask = mask
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = path(of: bounds, holeAt: center, radius: startRadius)
        animation.duration = duration
        // The `strongEaseOut` token's curve: Core Animation can't read a SwiftUI `Animation`.
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        run(animation, on: mask, removing: overlay)
    }

    private func fadeOut(_ overlay: UIView) {
        overlay.layer.opacity = 0
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.duration = reducedMotionDuration
        // `ease`, a colour change's curve: the strong ease-out spends the fade in its first 50 ms and reads as a cut.
        animation.timingFunction = CAMediaTimingFunction(name: .default)
        run(animation, on: overlay.layer, removing: overlay)
    }

    /// Animates from `fromValue` to the value already set on `layer`, so the last frame is the end state even
    /// before the overlay goes.
    private func run(_ animation: CABasicAnimation, on layer: CALayer, removing: UIView) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak removing] in
            guard let self, let removing, overlay === removing else { return }
            finish()
        }
        layer.add(animation, forKey: animation.keyPath)
        CATransaction.commit()
    }

    /// The whole screen with a round hole: the even-odd rule leaves the circle unfilled, so it shows through.
    private func path(of bounds: CGRect, holeAt center: CGPoint, radius: CGFloat) -> CGPath {
        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true))
        return path.cgPath
    }
}

extension CGRect {
    /// How far a circle centred on `point` must grow to cover the whole rectangle.
    func farthestCornerDistance(from point: CGPoint) -> CGFloat {
        let width = max(point.x - minX, maxX - point.x)
        let height = max(point.y - minY, maxY - point.y)
        return (width * width + height * height).squareRoot()
    }
}

/// Holds the old look during a reveal and swallows taps on it, except on the button, so a second tap still
/// reaches the button and starts the next reveal.
private final class RevealOverlay: UIView {
    private let passingTouchesIn: CGRect

    init(frame: CGRect, passingTouchesIn button: CGRect) {
        passingTouchesIn = button
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !passingTouchesIn.contains(point)
    }
}
