import AppKit
import CornerKit
import SwiftUI

extension ScreenCorner {
    /// The corner as a point of a rectangle, in SwiftUI's top-down coordinates.
    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: isRight ? rect.maxX : rect.minX, y: isBottom ? rect.maxY : rect.minY)
    }

    /// Where the quarter's curve starts, measured clockwise from pointing right (y down).
    var arcStart: Angle {
        switch self {
        case .topLeft: .degrees(0)
        case .topRight: .degrees(90)
        case .bottomRight: .degrees(180)
        case .bottomLeft: .degrees(270)
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    var unitPoint: UnitPoint {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    var opposite: UnitPoint {
        switch self {
        case .topLeft: .bottomTrailing
        case .topRight: .bottomLeading
        case .bottomLeft: .topTrailing
        case .bottomRight: .topLeading
        }
    }

    /// The card is square in the screen's corner and rounded at the far one.
    var cardShape: UnevenRoundedRectangle {
        let r = Masks.cardRadius
        return switch self {
        case .topLeft: UnevenRoundedRectangle(bottomTrailingRadius: r)
        case .topRight: UnevenRoundedRectangle(bottomLeadingRadius: r)
        case .bottomLeft: UnevenRoundedRectangle(topTrailingRadius: r)
        case .bottomRight: UnevenRoundedRectangle(topLeadingRadius: r)
        }
    }
}

private struct ScreenCornerKey: EnvironmentKey {
    static let defaultValue = ScreenCorner.topLeft
}

extension EnvironmentValues {
    var screenCorner: ScreenCorner {
        get { self[ScreenCornerKey.self] }
        set { self[ScreenCornerKey.self] = newValue }
    }
}

/// A quarter disc whose centre is the given corner of the view.
struct QuarterShape: Shape {
    var corner: ScreenCorner = .topLeft

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height)
        let c = corner.point(in: rect)
        var p = Path()
        p.move(to: c)
        p.addArc(center: c, radius: r, startAngle: corner.arcStart, endAngle: corner.arcStart + .degrees(90), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The curved edge alone.
struct QuarterArc: Shape {
    var corner: ScreenCorner = .topLeft
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: corner.point(in: rect), radius: min(rect.width, rect.height) - inset,
                 startAngle: corner.arcStart, endAngle: corner.arcStart + .degrees(90), clockwise: false)
        return p
    }
}

/// The widget's backdrop. Snapshots can't capture behind-window blur, so they get a flat fill.
struct Glass: View {
    let kind: GlassBackground.Kind
    static var flat = false
    @Environment(\.screenCorner) private var corner

    var body: some View {
        if Glass.flat {
            switch kind {
            case .quarter: QuarterShape(corner: corner).fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            case .card: corner.cardShape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            }
        } else {
            GlassBackground(kind: kind, corner: corner)
        }
    }
}

/// Behind-window blur. SwiftUI materials go flat grey while their app is inactive, and this
/// app is never active, so it pins an NSVisualEffectView to the active state and masks it.
struct GlassBackground: NSViewRepresentable {
    enum Kind { case quarter, card }
    let kind: Kind
    var corner: ScreenCorner = .topLeft

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.maskImage = kind == .quarter ? Masks.quarter(corner) : Masks.card(corner)
    }
}

enum Masks {
    static let cardRadius: CGFloat = 22

    /// Drawn for the top-left corner, then mirrored into the others.
    private static func mirrored(_ path: NSBezierPath, _ corner: ScreenCorner, in size: NSSize) {
        let t = NSAffineTransform()
        t.translateX(by: corner.isRight ? size.width : 0, yBy: corner.isBottom ? size.height : 0)
        t.scaleX(by: corner.isRight ? -1 : 1, yBy: corner.isBottom ? -1 : 1)
        path.transform(using: t as AffineTransform)
    }

    private static var quarters: [ScreenCorner: NSImage] = [:]
    private static var cards: [ScreenCorner: NSImage] = [:]

    static func quarter(_ corner: ScreenCorner) -> NSImage {
        if let image = quarters[corner] { return image }
        let image = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            let c = NSPoint(x: 0, y: rect.height)
            let path = NSBezierPath()
            path.move(to: c)
            path.line(to: NSPoint(x: rect.width, y: rect.height))
            path.appendArc(withCenter: c, radius: rect.width, startAngle: 0, endAngle: -90, clockwise: true)
            path.close()
            mirrored(path, corner, in: rect.size)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        quarters[corner] = image
        return image
    }

    /// Square except the corner away from the screen's; cap insets let it stretch to any card height.
    static func card(_ corner: ScreenCorner) -> NSImage {
        if let image = cards[corner] { return image }
        let r = cardRadius
        let image = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: .zero)
            path.line(to: NSPoint(x: rect.width - r, y: 0))
            path.appendArc(withCenter: NSPoint(x: rect.width - r, y: r), radius: r, startAngle: -90, endAngle: 0)
            path.line(to: NSPoint(x: rect.width, y: rect.height))
            path.line(to: NSPoint(x: 0, y: rect.height))
            path.close()
            mirrored(path, corner, in: rect.size)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        cards[corner] = image
        return image
    }
}

extension Tone {
    func tint(_ theme: Theme) -> Color {
        switch self {
        case .normal: theme.accent
        case .warning: .orange
        case .alert: .red
        case .muted: Color.primary.opacity(0.35)
        case .working: .claude
        case .success: .green
        }
    }
}

extension Color {
    /// Claude at work: violet in every theme, so it never reads as one of your own timers.
    static let claude = Color.vivid(0x8B5CF6)
}

struct Bar: View {
    var value: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(tint).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 4)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.controlFill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct Chip: View {
    let title: String
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.controlFill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
