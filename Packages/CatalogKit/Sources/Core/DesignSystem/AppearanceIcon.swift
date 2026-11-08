import SwiftUI

/// The appearance button's glyph: a moon while the app is light (the tap goes dark), a sun while it is dark.
///
/// It is one drawn shape, not two symbols: when `isDark` changes, the rays draw into the core as it swells into
/// the moon and a shadow slides across it; going back, the shadow slides off and the rays come out again. A tap
/// mid-way reverses from where it is. Under Reduce Motion the two shapes cross-fade instead. Decorative, so
/// VoiceOver skips it: the button carries the label.
public struct AppearanceIcon: View {
    private let isDark: Bool
    private let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter size: the glyph's side. The default sits in a 44 pt button.
    public init(isDark: Bool, size: CGFloat = 22) {
        self.isDark = isDark
        self.size = size
    }

    public var body: some View {
        glyph
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        if reduceMotion {
            ZStack {
                MorphingGlyph(progress: 0).opacity(isDark ? 1 : 0)
                MorphingGlyph(progress: 1).opacity(isDark ? 0 : 1)
            }
            .animation(crossFade, value: isDark)
        } else {
            MorphingGlyph(progress: isDark ? 0 : 1)
                .animation(morph, value: isDark)
        }
    }
}

/// A spring, so a tap mid-way reverses at the glyph's current speed instead of stopping dead. `settle`'s 0.3 s
/// spring only comes to rest after 500 ms; at `strongEaseOut`'s 0.25 s it rests by 400 ms.
private let morph = Animation.spring(duration: 0.25, bounce: 0)
/// Reduce Motion: nothing turns, grows or slides; the two still shapes swap in 200 ms.
private let crossFade = Animation.easeInOut(duration: 0.2)

/// The glyph at one point of the morph. SwiftUI animates `progress`, so every frame is drawn from it.
private struct MorphingGlyph: View, Animatable {
    /// 0 is the sun, 1 the moon.
    var progress: Double

    // `Animatable` is not tied to the main actor, so neither can this be; it only reads and writes a number.
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            AppearanceGlyph(progress: progress).draw(in: &context, size: size)
        }
    }
}

// The shapes, measured from SF Symbols' sun.max.fill and moon.fill so the glyph sits with the app's other
// symbols. Units: the sun's rays reach 1, the edge of the glyph's square.

/// The sun's core.
private let sunRadius = 0.47
/// Where a ray's middle sits, how long it is (round caps included) and how thick.
private let rayDistance = 0.818
private let rayLength = 0.364
private let rayWidth = 0.18
/// The full moon before the shadow carves it.
private let moonRadius = 0.945
/// The shadow that carves the crescent, and where it rests: up and to the right of the centre.
private let shadowRadius = 0.769
private let shadowRestDistance = 0.596
private let shadowRestAngle = Angle.degrees(-45)
/// SF's moon has round horn tips; a sharp tip would also shimmer as it moves.
private let hornRounding = 0.06

// The choreography, as slices of the progress from sun (0) to moon (1). Going back runs them backwards, so a
// reversal mid-way is always continuous.

/// The whole glyph turns a little, so the change reads as one object turning rather than a swap.
private let glyphTurn = Angle.degrees(30)
/// Each ray also turns as it draws in; with the glyph's own turn that is about 45° by the time it is gone.
private let raySpin = Angle.degrees(30)
/// A ray draws in over this much of the progress…
private let raySlice = 0.3
/// …starting later the further it is from the shadow, so the rays nearest it are gone before it arrives and,
/// coming back, return last, after it has left. The delay grows with the square of that distance: the near rays
/// must leave together, while the far ones, which the shadow never reaches, spread the wave over about 90 ms so
/// one dropped frame can't swallow it. Coming back, the rays are 15 ms apart at most.
private let rayStagger = 0.45
/// The core swells into the full moon while the rays draw in.
private let coreSlice = 0.0...0.6
/// The shadow slides in once the core has mostly grown, starting where it just touches the core, so all of its
/// slide carves.
private let shadowSlice = 0.35...1.0
private let shadowStartDistance = shadowRadius + coreRadius(at: shadowSlice.lowerBound)

/// The morph at one `progress`, from 0 (the sun) to 1 (the moon), in a square from −1 to 1 around the centre,
/// y pointing down. Each part runs in its own slice of the progress, so the parts overlap like one gesture.
private struct AppearanceGlyph {
    struct Ray {
        /// Direction from the centre, before the glyph's turn.
        let angle: Angle
        /// Distance from the centre to the ray's middle.
        let distance: Double
        let length: Double
        let width: Double
        let opacity: Double
    }

    struct Disc {
        let centre: CGPoint
        let radius: Double
    }

    let turn: Angle
    let rays: [Ray]
    let core: Disc
    /// The disc carved out of the core to leave the crescent.
    let shadow: Disc

    init(progress: Double) {
        let progress = arrived(progress)
        turn = .degrees(glyphTurn.degrees * progress)
        rays = (0..<8).map { ray($0, at: progress) }
        core = Disc(centre: .zero, radius: coreRadius(at: progress))
        let shadowDistance = mix(shadowStartDistance, shadowRestDistance, phase(of: progress, in: shadowSlice))
        shadow = Disc(centre: point(at: shadowAngle, distance: shadowDistance), radius: shadowRadius)
    }

    /// Draws the shapes as one mask and paints the inherited foreground style through it once, so a fading ray
    /// over the core never darkens it.
    func draw(in context: inout GraphicsContext, size: CGSize) {
        let scale = min(size.width, size.height) / 2
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.scaleBy(x: scale, y: scale)
        context.rotate(by: turn)
        context.clipToLayer { mask in
            for ray in rays {
                var rayMask = mask
                rayMask.opacity = ray.opacity
                rayMask.fill(path(of: ray), with: .color(.black))
            }
            // Stroking the crescent with round joins rounds its horns; its circles are moved in by the same
            // amount, so the outline stays where it was measured.
            let crescent = path(of: Disc(centre: core.centre, radius: core.radius - hornRounding))
                .subtracting(path(of: Disc(centre: shadow.centre, radius: shadow.radius + hornRounding)))
            let rounding = StrokeStyle(lineWidth: 2 * hornRounding, lineJoin: .round)
            mask.fill(crescent, with: .color(.black))
            mask.stroke(crescent, with: .color(.black), style: rounding)
        }
        // Big enough to cover the glyph's square at any turn; the mask cuts it to the shapes.
        context.fill(Path(CGRect(x: -2, y: -2, width: 4, height: 4)), with: .foreground)
    }

    private func path(of ray: Ray) -> Path {
        let capsule = CGRect(x: ray.distance - ray.length / 2, y: -ray.width / 2, width: ray.length, height: ray.width)
        return Path(roundedRect: capsule, cornerRadius: ray.width / 2)
            .applying(CGAffineTransform(rotationAngle: ray.angle.radians))
    }

    private func path(of disc: Disc) -> Path {
        let r = disc.radius
        return Path(ellipseIn: CGRect(x: disc.centre.x - r, y: disc.centre.y - r, width: 2 * r, height: 2 * r))
    }
}

/// The shadow's direction inside the glyph: turned back by the glyph's full turn, so on the moon it rests up and to
/// the right on screen, where SF's moon has its bite.
private let shadowAngle = Angle.degrees(shadowRestAngle.degrees - glyphTurn.degrees)

/// Ray `index` of 8, clockwise from the right.
private func ray(_ index: Int, at progress: Double) -> AppearanceGlyph.Ray {
    let restAngle = Angle.degrees(Double(index) * 45)
    let away = angleBetween(restAngle, shadowAngle).degrees / 180
    let start = rayStagger * away * away
    let drawnIn = phase(of: progress, in: start...(start + raySlice))
    return AppearanceGlyph.Ray(
        angle: .degrees(restAngle.degrees + raySpin.degrees * drawnIn),
        distance: mix(rayDistance, sunRadius, drawnIn),
        length: mix(rayLength, rayWidth, drawnIn),
        width: rayWidth,
        opacity: 1 - drawnIn
    )
}

private func coreRadius(at progress: Double) -> Double {
    mix(sunRadius, moonRadius, phase(of: progress, in: coreSlice))
}

/// The spring creeps through its last few hundredths for another 150 ms, and on a large glyph that sub-pixel turn
/// still shimmers the edges. So the glyph eases into either end over the last `arrivalMargin` of the progress and
/// is still while the spring finishes unseen; in between it follows the spring as it is.
private let arrivalMargin = 0.03

private func arrived(_ progress: Double) -> Double {
    let m = arrivalMargin
    let p = min(max(progress, 0), 1)
    let eased: Double
    if p < 2 * m {
        eased = p * p / (4 * m)
    } else if p > 1 - 2 * m {
        eased = 1 - 2 * m - (1 - p) * (1 - p) / (4 * m)
    } else {
        eased = p - m
    }
    return eased / (1 - 2 * m)
}

/// How far `progress` is through `slice`, from 0 to 1. Where the slice starts or ends inside the morph, the part
/// eases in or out so it never starts or stops with a jolt; at the morph's own ends it keeps the morph's speed, so
/// only the spring and `arrived` decide how fast the morph answers a tap and how it comes to rest.
private func phase(of progress: Double, in slice: ClosedRange<Double>) -> Double {
    let x = min(max((progress - slice.lowerBound) / (slice.upperBound - slice.lowerBound), 0), 1)
    switch (slice.lowerBound > 0, slice.upperBound < 1) {
    case (true, true): return x * x * (3 - 2 * x)
    case (true, false): return x * x * (2 - x)
    case (false, true): return x * (1 + x - x * x)
    case (false, false): return x
    }
}

private func mix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
    from + (to - from) * amount
}

private func point(at angle: Angle, distance: Double) -> CGPoint {
    CGPoint(x: cos(angle.radians) * distance, y: sin(angle.radians) * distance)
}

/// The unsigned angle between two directions, 0° to 180°.
private func angleBetween(_ a: Angle, _ b: Angle) -> Angle {
    let difference = abs(a.degrees - b.degrees).truncatingRemainder(dividingBy: 360)
    return .degrees(min(difference, 360 - difference))
}
