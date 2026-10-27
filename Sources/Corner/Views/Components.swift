import AppKit
import CornerKit
import SwiftUI

/// A quarter disc whose corner sits at the view's top-left.
struct QuarterShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height)
        var p = Path()
        p.move(to: rect.origin)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addArc(center: rect.origin, radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The curved edge alone, running from the top edge down to the left edge.
struct QuarterArc: Shape {
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: rect.origin, radius: min(rect.width, rect.height) - inset,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        return p
    }
}

/// The widget's backdrop. Snapshots can't capture behind-window blur, so they get a flat fill.
struct Glass: View {
    let kind: GlassBackground.Kind
    static var flat = false

    var body: some View {
        if Glass.flat {
            switch kind {
            case .quarter: QuarterShape().fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            case .card: UnevenRoundedRectangle(bottomTrailingRadius: Masks.cardRadius)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            }
        } else {
            GlassBackground(kind: kind)
        }
    }
}

/// Behind-window blur. SwiftUI materials go flat grey while their app is inactive, and this
/// app is never active, so it pins an NSVisualEffectView to the active state and masks it.
struct GlassBackground: NSViewRepresentable {
    enum Kind { case quarter, card }
    let kind: Kind

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = kind == .quarter ? Masks.quarter : Masks.card
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

enum Masks {
    static let cardRadius: CGFloat = 22

    static let quarter = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
        let corner = NSPoint(x: 0, y: rect.height)
        let path = NSBezierPath()
        path.move(to: corner)
        path.line(to: NSPoint(x: rect.width, y: rect.height))
        path.appendArc(withCenter: corner, radius: rect.width, startAngle: 0, endAngle: -90, clockwise: true)
        path.close()
        NSColor.black.setFill()
        path.fill()
        return true
    }

    /// Square except the bottom-right corner; cap insets let it stretch to any card height.
    static let card: NSImage = {
        let r = cardRadius
        let image = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: .zero)
            path.line(to: NSPoint(x: rect.width - r, y: 0))
            path.appendArc(withCenter: NSPoint(x: rect.width - r, y: r), radius: r, startAngle: -90, endAngle: 0)
            path.line(to: NSPoint(x: rect.width, y: rect.height))
            path.line(to: NSPoint(x: 0, y: rect.height))
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }()
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
