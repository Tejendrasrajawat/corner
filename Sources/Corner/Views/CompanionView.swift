import CornerKit
import CoreGraphics
import SwiftUI

/// The companion in the idle corner. A brain picks what it does (checked once a second, from the
/// store's tick, and straight away when the pointer arrives); each activity is a short loop of
/// pixel-art frames that Core Animation plays by itself. Redrawing through SwiftUI every frame
/// instead costs about 5 ms of CPU a frame, which a corner on screen all day can't afford.
struct CompanionView: View {
    let kind: CompanionKind
    /// The quarter's radius.
    let size: CGFloat
    let hovering: Bool
    let now: Date
    var animate = true
    @State private var driver = CompanionDriver()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenCorner) private var corner

    var body: some View {
        let activity = driver.step(now: now, hovering: hovering)
        CompanionSprite(kind: kind, activity: activity, corner: corner, still: reduceMotion || !animate)
            .frame(width: size, height: size)
            .clipShape(QuarterShape(corner: corner))
            .allowsHitTesting(false)
            .accessibilityLabel("\(kind.name), keeping you company")
    }
}

/// Holds the brain between ticks.
@MainActor
final class CompanionDriver {
    private var brain: CompanionBrain?

    func step(now: Date, hovering: Bool) -> CompanionActivity {
        // How long since any key press or mouse move. Needs no permission.
        let away = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        var b = brain ?? CompanionBrain(now: now)
        b.update(now: now, away: away, hour: Calendar.current.component(.hour, from: now), hovering: hovering)
        brain = b
        return b.activity
    }
}

/// Plays an activity's loop on a layer, scaled up with hard pixel edges.
struct CompanionSprite: NSViewRepresentable {
    let kind: CompanionKind
    let activity: CompanionActivity
    let corner: ScreenCorner
    /// Reduce Motion, or the corner is hidden: the loop's first frame, held.
    let still: Bool

    func makeNSView(context: Context) -> SpriteView { SpriteView() }

    func updateNSView(_ view: SpriteView, context: Context) {
        view.show(kind: kind, activity: activity, corner: corner, still: still)
    }
}

final class SpriteView: NSView {
    private let sprite = CALayer()
    private var shown: (CompanionKind, CompanionActivity, ScreenCorner, Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        sprite.contentsGravity = .resize
        sprite.magnificationFilter = .nearest
        layer?.addSublayer(sprite)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds
        CATransaction.commit()
    }

    @MainActor
    func show(kind: CompanionKind, activity: CompanionActivity, corner: ScreenCorner, still: Bool) {
        if let shown, shown == (kind, activity, corner, still) { return }
        let first = shown == nil
        shown = (kind, activity, corner, still)
        let frames = CompanionFrames.frames(kind, activity, corner: corner)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !first {
            // A quick cross-fade, so one activity never jumps into the next.
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.2
            sprite.add(fade, forKey: "fade")
        }
        sprite.removeAnimation(forKey: "loop")
        sprite.contents = frames.first
        if !still && frames.count > 1 {
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = frames
            animation.calculationMode = .discrete
            animation.duration = CompanionFrames.loop(activity).length
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            sprite.add(animation, forKey: "loop")
        }
        CATransaction.commit()
    }
}

/// A character in a small quarter, for choosing one in Settings.
struct CompanionTile: View {
    let kind: CompanionKind
    let selected: Bool
    let choose: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 5) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .underPageBackgroundColor))
                    QuarterShape().fill(Color.gray.opacity(0.25)).frame(width: 64, height: 64)
                    if let image = CompanionFrames.frames(kind, .sit).first {
                        Image(decorative: image, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(QuarterShape())
                    }
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? theme.accent : Color.primary.opacity(0.15), lineWidth: selected ? 2.5 : 1)
                )
                Text(kind.name)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.name) companion")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Frames

/// Builds each activity's frames from the sprites in `Sprites`. A frame is a small square pixel
/// scene over the quarter, whose corner (the screen's) is at 0, 0: the left edge is the side of the
/// screen, the top edge the menu bar. People and the cat have their own scene sizes, chosen so the
/// character fills the corner; the smaller the scene, the bigger each pixel on screen.
@MainActor
enum CompanionFrames {
    /// Each activity's loop: its length in seconds and frames per second.
    static func loop(_ activity: CompanionActivity) -> (length: Double, fps: Double) {
        switch activity {
        case .sit: (8, 8)
        case .wag: (2, 8)
        case .play: (4, 10)
        case .walk: (CompanionBrain.walkLoop, 10)
        case .climb: (CompanionBrain.climbLength, 10)
        case .sleep: (6, 4)
        case .wake: (CompanionBrain.wakeLength, 8)
        case .greet: (2.4, 8)
        }
    }

    /// Every loop is small (a frame is under 8 KB), so they're all kept once drawn.
    private static var cache: [String: [CGImage]] = [:]

    /// In the right-hand corners the scene is mirrored, so the side of the screen is still the wall;
    /// in the bottom corners it stands on the bottom edge and there's no top edge to hang from.
    static func frames(_ kind: CompanionKind, _ activity: CompanionActivity, corner: ScreenCorner = .topLeft) -> [CGImage] {
        let key = "\(kind.rawValue) \(activity.rawValue) \(corner.rawValue)"
        if let frames = cache[key] { return frames }
        let loop = loop(activity)
        let count = max(1, Int((loop.length * loop.fps).rounded()))
        let palette = Palettes.common.merging(palette(kind)) { $1 }
        let frames = (0..<count).compactMap { i -> CGImage? in
            let grid = kind == .cat ? CatScene.grid : PersonScene.grid
            var canvas = PixelCanvas(width: grid, height: grid)
            let t = Double(i) / loop.fps
            if kind == .cat {
                if corner.isBottom { canvas.offsetY = grid - 2 - CatScene.floor }
                CatScene.draw(activity, t: t, length: loop.length, bottom: corner.isBottom, on: &canvas)
            } else {
                if corner.isBottom { canvas.offsetY = grid - 2 - PersonScene.floor }
                PersonScene.draw(kind, activity, t: t, length: loop.length, bottom: corner.isBottom, on: &canvas)
            }
            if corner.isRight {
                var mirrored = PixelCanvas(width: grid, height: grid)
                mirrored.draw(canvas.sprite, x: 0, y: 0, flip: true)
                canvas = mirrored
            }
            return canvas.image(palette: palette)
        }
        cache[key] = frames
        return frames
    }

    static func palette(_ kind: CompanionKind) -> [Character: UInt32] {
        switch kind {
        case .ninja: Palettes.ninja
        case .swordsman: Palettes.swordsman
        case .mage: Palettes.mage
        case .cat: Palettes.cat
        }
    }

    /// How far through a scripted move between two times, 0...1.
    static func progress(_ t: Double, from start: Double, to end: Double) -> Double {
        min(1, max(0, (t - start) / (end - start)))
    }

    static func lerp(_ a: Int, _ b: Int, _ f: Double) -> Int { a + Int((Double(b - a) * f).rounded()) }

    /// Hearts and z's that drift up: `count` of them, staggered, each rising over `period`.
    static func rising(_ t: Double, period: Double, count: Int) -> [Double] {
        (0..<count).map { i in ((t / period) + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1) }
    }

    /// Blinks now and then, on the same beat for everyone.
    static func blinking(_ t: Double) -> Bool {
        let cycle = t.truncatingRemainder(dividingBy: 3.7)
        return cycle > 2.1 && cycle < 2.25
    }
}

// MARK: - People

/// The ninja, swordsman and mage: shared bodies and heads with their own hair and kit. Their scene
/// is 44 pixels square; they stand with their soles on row 35, which puts the tallest hat at the
/// top edge, and stay within the curve.
@MainActor
enum PersonScene {
    static let grid = 44, floor = 35, home = 11

    enum Face { case open, blink, happy, side, surprised, yawn }
    enum Pose {
        case stand, walk(step: Bool), sit(nod: Bool), wave(high: Bool), climb(leftUp: Bool), hang(leftUp: Bool)
        case reach, swordUp, swordDown, throwBack, throwForward
    }

    /// Figures are drawn on their own canvas, so they can be mirrored whole. The body's top-left
    /// sits at (12, 30) on it, and its soles at (20, 43).
    static let bodyX = 12, bodyY = 30, figureWidth = 40, figureHeight = 46
    static let feet = (x: 20, y: 43)

    static func draw(_ kind: CompanionKind, _ activity: CompanionActivity, t: Double, length: Double, bottom: Bool,
                     on canvas: inout PixelCanvas) {
        let floor = Self.floor, home = Self.home
        let tick = Int(t * 8)
        var place = (x: home, y: floor)
        var facingLeft = false
        var pose = Pose.stand
        var face = CompanionFrames.blinking(t) ? Face.blink : Face.open
        var effects: [(PixelSprite, Int, Int)] = []

        switch activity {
        case .sit:
            // Stands about, looks around, then sits down for a bit.
            let phase = t / length
            if phase > 0.25 && phase < 0.4 { face = .side }
            if phase >= 0.55 {
                pose = .sit(nod: false)
                if phase > 0.8 && phase < 0.9 { face = .happy }
            }
        case .wag:
            pose = .wave(high: tick % 4 < 2)
            face = .happy
        case .walk:
            // Out to the right, back across towards the edge, and home.
            if t < 1 {
                place.x = CompanionFrames.lerp(home, home + 3, t)
            } else if t < 3 {
                place.x = CompanionFrames.lerp(home + 3, home - 3, (t - 1) / 2)
                facingLeft = true
            } else {
                place.x = CompanionFrames.lerp(home - 3, home, t - 3)
            }
            pose = .walk(step: tick % 2 == 0)
            face = .side
        case .climb:
            climb(t, bottom: bottom, place: &place, facingLeft: &facingLeft, pose: &pose, face: &face)
        case .play:
            play(kind, t: t, pose: &pose, face: &face, effects: &effects)
        case .sleep:
            pose = .sit(nod: Int(t / 1.5) % 2 == 1)
            face = .blink
            for rise in CompanionFrames.rising(t, period: 3, count: 3) where rise < 0.85 {
                effects.append((Sprite.zee, home + 8 + Int(rise * 8), floor - 22 - Int(rise * 10)))
            }
        case .wake:
            if t < 1.8 {
                pose = .reach
                face = .yawn
            } else {
                face = .happy
            }
        case .greet:
            pose = .wave(high: tick % 4 < 2)
            face = .happy
            if tick % 4 == 1 { place.y -= 1 }
            for rise in CompanionFrames.rising(t, period: 1.2, count: 2) where rise < 0.8 {
                effects.append((Sprite.heart, home + 10 + Int(rise * 3), floor - 27 - Int(rise * 6)))
            }
        }

        let figure = self.figure(kind, pose: pose, face: face, tick: tick)
        canvas.draw(figure, x: place.x - feet.x, y: place.y - feet.y, flip: facingLeft)
        for (sprite, x, y) in effects { canvas.draw(sprite, x: x, y: y) }
    }

    /// Up the side of the screen, hand over hand under the menu bar, a drop, and home: one
    /// 8-second trip. In a bottom corner there's no top edge, so it clings to the side and drops.
    static func climb(_ t: Double, bottom: Bool, place: inout (x: Int, y: Int), facingLeft: inout Bool, pose: inout Pose, face: inout Face) {
        let floor = Self.floor, home = Self.home
        let wall = 8, hangTo = bottom ? wall : 14
        if bottom && t >= 2.0 && t < 4.4 {
            place.x = wall
            place.y = floor - 5
            pose = .climb(leftUp: Int(t * 3) % 2 == 0)
            return
        }
        // Where the soles are once it has climbed, and while its hands hold the top edge.
        let climbedFeet = 29, hangingFeet = 27
        let tick = Int(t * 8)
        switch t {
        case ..<0.6:
            place.x = CompanionFrames.lerp(home, wall, t / 0.6)
            facingLeft = true
            pose = .walk(step: tick % 2 == 0)
            face = .side
        case ..<2.0:
            place.x = wall
            place.y = CompanionFrames.lerp(floor, bottom ? floor - 5 : climbedFeet, CompanionFrames.progress(t, from: 0.8, to: 2.0))
            pose = .climb(leftUp: tick % 2 == 0)
        case ..<4.4:
            place.x = CompanionFrames.lerp(wall, hangTo, CompanionFrames.progress(t, from: 2.2, to: 4.4))
            place.y = hangingFeet + (tick % 4 < 2 ? 0 : 1)
            pose = .hang(leftUp: tick % 2 == 0)
            face = .happy
        case ..<4.8:
            let fall = CompanionFrames.progress(t, from: 4.4, to: 4.8)
            let from = bottom ? floor - 5 : hangingFeet
            place.x = hangTo
            place.y = from + Int(Double(floor - from) * fall * fall)
            pose = .reach
            face = .surprised
        case ..<5.3:
            place.x = hangTo
            pose = .sit(nod: false)
            face = .happy
        case ..<6.0:
            place.x = CompanionFrames.lerp(hangTo, home, CompanionFrames.progress(t, from: 5.3, to: 6.0))
            facingLeft = true
            pose = .walk(step: tick % 2 == 0)
            face = .side
        default:
            face = .happy
        }
    }

    /// Each one's own trick, twice in a 4-second loop.
    static func play(_ kind: CompanionKind, t: Double, pose: inout Pose, face: inout Face, effects: inout [(PixelSprite, Int, Int)]) {
        let floor = Self.floor, home = Self.home
        let tick = Int(t * 10)
        let beat = t.truncatingRemainder(dividingBy: 2)
        switch kind {
        case .ninja:
            // Wind up, throw, and the star spins away across the corner.
            if beat < 0.4 {
                pose = .throwBack
            } else if beat < 0.7 {
                pose = .throwForward
                face = .happy
            }
            if beat >= 0.5 && beat < 1.3 {
                let flight = CompanionFrames.progress(beat, from: 0.5, to: 1.3)
                let star = tick % 2 == 0 ? Sprite.shuriken1 : Sprite.shuriken2
                effects.append((star, home + 9 + Int(flight * 16), floor - 21 + Int(flight * 3)))
            }
        case .swordsman:
            // Raise the sword, cut, hold, put it away.
            if beat >= 0.3 && beat < 0.9 {
                pose = .swordUp
            } else if beat >= 0.9 && beat < 1.6 {
                pose = .swordDown
                face = .happy
                if beat < 1.2 { effects.append((Sprite.slash, home + 6, floor - 23)) }
            }
        case .mage:
            // Staff up, and a ring of sparkles turning round it.
            if beat < 1.4 {
                pose = .reach
                face = .happy
                let spin = beat * 2 * .pi / 1.4
                for i in 0..<4 {
                    let angle = spin + Double(i) * .pi / 2
                    let sparkle = (tick + i) % 2 == 0 ? Sprite.sparkleSmall : Sprite.sparkle
                    effects.append((sparkle, home + 9 + Int(cos(angle) * 8), floor - 26 + Int(sin(angle) * 5)))
                }
            }
        case .cat:
            break
        }
    }

    // MARK: Building a figure

    static func figure(_ kind: CompanionKind, pose: Pose, face: Face, tick: Int) -> PixelSprite {
        var c = PixelCanvas(width: figureWidth, height: figureHeight)
        let bx = bodyX
        var by = bodyY
        var back = false
        var sitting = false
        var nod = 0
        let body: PixelSprite
        switch pose {
        case .stand: body = Sprite.stand
        case .walk(let step): body = step ? Sprite.walk : Sprite.stand
        case .sit(let nodding):
            body = Sprite.sit
            sitting = true
            nod = nodding ? 1 : 0
            by += Sprite.stand.height - Sprite.sit.height
        case .wave, .throwBack, .throwForward, .swordDown: body = Sprite.standOneArm
        case .climb:
            body = Sprite.backReach
            back = true
        case .hang, .reach, .swordUp: body = Sprite.reach
        }
        let headY = by - 12 + nod

        // Behind the body.
        if kind == .ninja && !back {
            c.draw(tick % 4 < 2 ? Sprite.scarfTail1 : Sprite.scarfTail2, x: bx - 5, y: by - 2)
        }
        if kind == .swordsman && !back && !sitting {
            c.draw(Sprite.sheath, x: bx + 2, y: by + 5)
        }

        c.draw(body, x: bx, y: by)
        let hair = Sprite.hair(kind)
        if back {
            c.draw(Sprite.head, x: bx, y: headY)
            c.draw(Sprite.backHair(kind), x: bx + hair.dx, y: headY + hair.dy)
        } else {
            c.draw(Sprite.head(face), x: bx, y: headY)
            c.draw(hair.sprite, x: bx + hair.dx, y: headY + hair.dy)
        }

        // Arms go over the head, then the kit in front.
        switch pose {
        case .wave(let high):
            c.draw(Sprite.armWave, x: bx + 11, y: by - (high ? 5 : 3))
        case .throwBack:
            c.draw(Sprite.armWave, x: bx + 11, y: by - 6)
        case .throwForward:
            c.draw(Sprite.armWave, x: bx + 12, y: by - 2)
        case .climb(let leftUp), .hang(let leftUp):
            c.draw(Sprite.armUp, x: bx + 10, y: by - 14 + (leftUp ? 2 : 0))
            c.draw(Sprite.armUp, x: bx - 1, y: by - 14 + (leftUp ? 0 : 2), flip: true)
        case .reach:
            c.draw(Sprite.armUp, x: bx + 10, y: by - 14)
            c.draw(Sprite.armUp, x: bx - 1, y: by - 14, flip: true)
            if kind == .mage { c.draw(Sprite.staff, x: bx + 15, y: by - 22) }
        case .swordUp:
            c.draw(Sprite.armUp, x: bx + 10, y: by - 14)
            c.draw(Sprite.sword, x: bx + 15, y: by - 24)
        case .swordDown:
            c.draw(Sprite.sword.flippedVertically, x: bx + 12, y: by + 2)
        case .stand, .walk, .sit:
            break
        }
        if kind == .ninja && !back {
            c.draw(Sprite.scarf, x: bx + 2, y: by)
        }
        if kind == .mage && !back {
            switch pose {
            case .stand, .walk: c.draw(Sprite.staff, x: bx + 13, y: by - 6)
            default: break
            }
        }
        return c.sprite
    }
}

// MARK: - Cat

/// The cat's scene is 30 pixels square, so the cat, about half the size of the people in pixels,
/// fills the corner as well as they do.
@MainActor
enum CatScene {
    static let grid = 30, floor = 21, home = 10

    static func draw(_ activity: CompanionActivity, t: Double, length: Double, bottom: Bool, on canvas: inout PixelCanvas) {
        let floor = Self.floor, home = Self.home
        let tick = Int(t * 8)
        let sitting = CompanionFrames.blinking(t) ? Sprite.catSitBlink : Sprite.catSit
        func sit(at x: Int, _ sprite: PixelSprite, lift: Int = 0) {
            canvas.draw(sprite, x: x - 8, y: floor - 15 - lift)
        }
        func walk(at x: Int, left: Bool) {
            canvas.draw(tick % 2 == 0 ? Sprite.catWalk1 : Sprite.catWalk2, x: x - 10, y: floor - 12, flip: left)
        }

        switch activity {
        case .sit:
            sit(at: home, sitting)
        case .wag:
            sit(at: home, Sprite.catSitHappy, lift: tick % 4 == 1 ? 1 : 0)
        case .walk:
            // Out to the right and back; there's no room to its left.
            if t < 2 {
                walk(at: CompanionFrames.lerp(home, home + 4, t / 2), left: false)
            } else {
                walk(at: CompanionFrames.lerp(home + 4, home, (t - 2) / 2), left: true)
            }
        case .climb where bottom:
            // No top edge to walk along: up the side a little, hang on, and drop.
            let up = tick % 2 == 0 ? Sprite.catClimb1 : Sprite.catClimb2
            switch t {
            case ..<1.2:
                canvas.draw(up, x: 0, y: CompanionFrames.lerp(floor - 19, floor - 24, t / 1.2))
            case ..<3.2:
                canvas.draw(Sprite.catClimb1, x: 0, y: floor - 24)
            case ..<3.6:
                let fall = CompanionFrames.progress(t, from: 3.2, to: 3.6)
                canvas.draw(Sprite.catClimb1, x: 0, y: floor - 24 + Int(5 * fall * fall))
            default:
                sit(at: home, t < 4.4 ? Sprite.catSitHappy : sitting)
            }
        case .climb:
            // Up against the side of the screen, upside down along the top, and a drop.
            let up = tick % 2 == 0 ? Sprite.catClimb1 : Sprite.catClimb2
            let along = tick % 2 == 0 ? Sprite.catCeiling1 : Sprite.catCeiling2
            switch t {
            case ..<1.6:
                canvas.draw(up, x: 0, y: CompanionFrames.lerp(floor - 19, 0, CompanionFrames.progress(t, from: 0, to: 1.6)))
            case ..<3.8:
                canvas.draw(along, x: CompanionFrames.lerp(0, 8, CompanionFrames.progress(t, from: 1.6, to: 3.8)), y: 0)
            case ..<4.2:
                let fall = CompanionFrames.progress(t, from: 3.8, to: 4.2)
                sit(at: 12, Sprite.catSitHappy, lift: Int(Double(floor - 15) * (1 - fall * fall)))
            case ..<5.0:
                sit(at: 12, Sprite.catSitHappy)
            case ..<6.0:
                walk(at: CompanionFrames.lerp(12, home, CompanionFrames.progress(t, from: 5.0, to: 6.0)), left: true)
            default:
                sit(at: home, sitting)
            }
        case .play:
            // Yarn rolls about in front; the cat watches, then pounces after it.
            let beat = t.truncatingRemainder(dividingBy: 2)
            if beat < 1.2 {
                sit(at: home, sitting)
            } else {
                walk(at: home, left: true)
            }
            canvas.draw(Sprite.yarn, x: 1 + Int((1 + sin(t * .pi)) * 2), y: floor - 5 - (tick % 4 == 0 ? 1 : 0))
        case .sleep:
            canvas.draw(Sprite.catSleep, x: home - 10, y: floor - 9)
            for rise in CompanionFrames.rising(t, period: 3, count: 3) where rise < 0.85 {
                canvas.draw(Sprite.zee, x: home + 4 + Int(rise * 6), y: floor - 14 - Int(rise * 8))
            }
        case .wake:
            sit(at: home, t < 1.6 ? Sprite.catSitBlink : Sprite.catSitHappy)
        case .greet:
            sit(at: home, Sprite.catSitHappy, lift: tick % 4 == 1 ? 1 : 0)
            for rise in CompanionFrames.rising(t, period: 1.2, count: 2) where rise < 0.8 {
                canvas.draw(Sprite.heart, x: home + 4 + Int(rise * 2), y: floor - 18 - Int(rise * 3))
            }
        }
    }
}

// MARK: - Sprites, parsed

/// `Sprites` turned into pixel grids, with the variants the scenes need.
@MainActor
enum Sprite {
    static let head = PixelSprite(Sprites.head)
    static let stand = PixelSprite(Sprites.stand)
    static let walk = PixelSprite(Sprites.walk)
    static let sit = PixelSprite(Sprites.sit)
    static let standOneArm = PixelSprite(Sprites.standOneArm)
    static let reach = PixelSprite(Sprites.reach)
    /// The reaching body from behind: the same, without the front opening.
    static let backReach = reach.replacing("C", with: "A", rows: 2..<6)
    static let armUp = PixelSprite(Sprites.armUp)
    static let armWave = PixelSprite(Sprites.armWave)
    static let scarf = PixelSprite(Sprites.scarf)
    static let scarfTail1 = PixelSprite(Sprites.scarfTail1)
    static let scarfTail2 = PixelSprite(Sprites.scarfTail2)
    static let sheath = PixelSprite(Sprites.sheath)
    static let sword = PixelSprite(Sprites.sword)
    static let slash = PixelSprite(Sprites.slash)
    static let staff = PixelSprite(Sprites.staff)
    static let shuriken1 = PixelSprite(Sprites.shuriken1)
    static let shuriken2 = PixelSprite(Sprites.shuriken2)
    static let sparkle = PixelSprite(Sprites.sparkle)
    static let sparkleSmall = PixelSprite(Sprites.sparkleSmall)
    static let heart = PixelSprite(Sprites.heart)
    static let zee = PixelSprite(Sprites.zee)
    static let catSit = PixelSprite(Sprites.catSit)
    static let catSitBlink = catSit.replacingRows(from: 6, with: PixelSprite(Sprites.catBlink))
    static let catSitHappy = catSit.replacingRows(from: 6, with: PixelSprite(Sprites.catHappy))
    static let catWalk1 = PixelSprite(Sprites.catWalk1)
    static let catWalk2 = PixelSprite(Sprites.catWalk2)
    /// Turned to walk up the side of the screen, and upside down along the top.
    static let catClimb1 = catWalk1.rotatedLeft
    static let catClimb2 = catWalk2.rotatedLeft
    static let catCeiling1 = catWalk1.rotated180.flipped
    static let catCeiling2 = catWalk2.rotated180.flipped
    static let catSleep = PixelSprite(Sprites.catSleep)
    static let yarn = PixelSprite(Sprites.yarn)

    private static let faces: [PersonScene.Face: PixelSprite] = [
        .blink: head.replacingRows(from: 6, with: PixelSprite(Sprites.eyesBlink)),
        .happy: head.replacingRows(from: 6, with: PixelSprite(Sprites.eyesHappy)),
        .side: head.replacingRows(from: 6, with: PixelSprite(Sprites.eyesSide)),
        .surprised: head.replacingRows(from: 6, with: PixelSprite(Sprites.eyesSurprised)),
        .yawn: head.replacingRows(from: 6, with: PixelSprite(Sprites.eyesYawn)),
    ]

    static func head(_ face: PersonScene.Face) -> PixelSprite { faces[face] ?? head }

    private static let ninjaHair = PixelSprite(Sprites.ninjaHair)
    private static let swordsmanHair = PixelSprite(Sprites.swordsmanHair)
    private static let mageHat = PixelSprite(Sprites.mageHat)

    /// Hair (or hat and hair), and where its top-left goes relative to the head's.
    static func hair(_ kind: CompanionKind) -> (sprite: PixelSprite, dx: Int, dy: Int) {
        switch kind {
        case .ninja, .cat: (ninjaHair, -2, -5)
        case .swordsman: (swordsmanHair, -2, -5)
        case .mage: (mageHat, -3, -10)
        }
    }

    private static var backHairs: [CompanionKind: PixelSprite] = [:]

    /// The hair from behind: the head's shape filled with hair, under the front hair.
    static func backHair(_ kind: CompanionKind) -> PixelSprite {
        if let made = backHairs[kind] { return made }
        let (front, dx, dy) = hair(kind)
        var out = front
        for r in 0..<head.height {
            for c in 0..<head.width where head[c, r] != nil {
                let (x, y) = (c - dx, r - dy)
                guard x >= 0, y >= 0, x < out.width, y < out.height, out[x, y] == nil else { continue }
                let edge = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { step in
                    let (nc, nr) = (c + step.0, r + step.1)
                    return nc < 0 || nr < 0 || nc >= head.width || nr >= head.height || head[nc, nr] == nil
                }
                out[x, y] = edge ? "K" : (r >= 11 ? "h" : "H")
            }
        }
        backHairs[kind] = out
        return out
    }
}

/// Pixels as palette letters; nil is see-through.
struct PixelSprite {
    let width: Int
    let height: Int
    var pixels: [Character?]

    init(width: Int, height: Int, pixels: [Character?]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// From rows of letters, "." for see-through.
    init(_ art: String) {
        let rows = art.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let w = rows.map(\.count).max() ?? 0
        width = w
        height = rows.count
        pixels = rows.flatMap { row in
            let letters: [Character?] = row.map { $0 == "." ? nil : $0 }
            return letters + Array(repeating: nil, count: w - letters.count)
        }
    }

    subscript(x: Int, y: Int) -> Character? {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    var flipped: PixelSprite { transformed(width, height) { x, y in (width - 1 - x, y) } }
    var flippedVertically: PixelSprite { transformed(width, height) { x, y in (x, height - 1 - y) } }
    var rotated180: PixelSprite { transformed(width, height) { x, y in (width - 1 - x, height - 1 - y) } }
    /// A quarter turn anticlockwise: what faced right now faces up.
    var rotatedLeft: PixelSprite { transformed(height, width) { x, y in (width - 1 - y, x) } }

    /// The sprite with its rows from `start` swapped for another sprite's rows.
    func replacingRows(from start: Int, with rows: PixelSprite) -> PixelSprite {
        var out = self
        for y in 0..<rows.height where start + y < height {
            for x in 0..<min(width, rows.width) { out[x, start + y] = rows[x, y] }
        }
        return out
    }

    func replacing(_ letter: Character, with other: Character, rows: Range<Int>) -> PixelSprite {
        var out = self
        for y in rows where y < height {
            for x in 0..<width where out[x, y] == letter { out[x, y] = other }
        }
        return out
    }

    /// A sprite of the given size whose pixel (x, y) is this one's pixel `source(x, y)`.
    private func transformed(_ w: Int, _ h: Int, _ source: (Int, Int) -> (Int, Int)) -> PixelSprite {
        var out = PixelSprite(width: w, height: h, pixels: Array(repeating: nil, count: w * h))
        for y in 0..<h {
            for x in 0..<w {
                let (sx, sy) = source(x, y)
                out[x, y] = self[sx, sy]
            }
        }
        return out
    }
}

/// A frame being put together, letter by letter.
struct PixelCanvas {
    let width: Int
    let height: Int
    /// Moves everything drawn down by this many rows.
    var offsetY = 0
    private var pixels: [Character?]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = Array(repeating: nil, count: width * height)
    }

    var sprite: PixelSprite { PixelSprite(width: width, height: height, pixels: pixels) }

    mutating func draw(_ s: PixelSprite, x: Int, y: Int, flip: Bool = false) {
        for sy in 0..<s.height {
            let ty = y + sy + offsetY
            guard ty >= 0, ty < height else { continue }
            for sx in 0..<s.width {
                guard let letter = s[flip ? s.width - 1 - sx : sx, sy] else { continue }
                let tx = x + sx
                guard tx >= 0, tx < width else { continue }
                pixels[ty * width + tx] = letter
            }
        }
    }

    func image(palette: [Character: UInt32]) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (i, letter) in pixels.enumerated() {
            guard let letter, let rgb = palette[letter] else { continue }
            bytes[i * 4] = UInt8((rgb >> 16) & 0xFF)
            bytes[i * 4 + 1] = UInt8((rgb >> 8) & 0xFF)
            bytes[i * 4 + 2] = UInt8(rgb & 0xFF)
            bytes[i * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
