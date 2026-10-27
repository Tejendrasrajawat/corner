import CornerKit
import SwiftUI

/// What's left of the corner while tucked away: a dot-sized quarter in the very corner, tinted by
/// the same tone the full corner would show (red when something has gone off).
struct TuckedTab: View {
    static let size: CGFloat = 10
    let tone: Tone
    @Environment(\.theme) private var theme
    @Environment(\.screenCorner) private var corner

    var body: some View {
        QuarterShape(corner: corner)
            .fill(tone == .muted ? (theme.isPlain ? Color.gray : theme.accent.opacity(0.6)) : tone.tint(theme))
            .overlay(QuarterArc(corner: corner, inset: 0.25).stroke(Color.primary.opacity(0.3), lineWidth: 0.5))
            .frame(width: Self.size, height: Self.size)
            .accessibilityLabel("Corner, tucked away")
    }
}

/// The minimized widget: a quarter circle showing one value, with progress drawn along the curve.
struct CornerFaceView: View {
    let face: CornerFace
    /// The radius drawn now: `fullSize`, or smaller while resting in shrink mode.
    let size: CGFloat
    var fullSize: CGFloat? = nil
    let hovering: Bool
    /// Off while the corner is hidden, so a companion doesn't keep drawing.
    var animate = true
    /// The store's tick, which is when a companion decides what to do next.
    var now = Date()
    @Environment(\.theme) private var theme
    @Environment(\.screenCorner) private var corner

    var body: some View {
        let ring = max(3, size * 0.04)
        let inset = size * 0.06
        let alert = face.tone == .alert
        // Amber "needs you" and green "done" tint the value and label too; working stays neutral.
        let accentText: Color? = switch face.tone {
        case .alert: .red
        case .warning where face.ref.isClaude: .orange
        case .success: .green
        default: nil
        }
        let full = fullSize ?? size
        // Text keeps its full-size font and is scaled instead, so growing animates smoothly rather
        // than jumping between font sizes. It shrinks less than the circle so it stays readable.
        let textScale = min(1, size / full * 1.3)
        let compact = size < full * 0.8
        ZStack(alignment: corner.alignment) {
            ThemedBackground(kind: .quarter)
            if let fill = accentText {
                QuarterShape(corner: corner).fill(fill.opacity(alert ? 0.22 : 0.18))
            }
            QuarterArc(corner: corner, inset: inset)
                .stroke(Color.primary.opacity(0.12), lineWidth: ring)
            if face.indeterminate {
                // No end in sight, so a short arc sweeps back and forth, one step per tick.
                let step = Int(Date().timeIntervalSince1970) % 6
                let start = Double(step < 3 ? step : 6 - step) / 3 * 0.72
                QuarterArc(corner: corner, inset: inset)
                    .trim(from: start, to: start + 0.28)
                    .stroke(face.tone.tint(theme), style: StrokeStyle(lineWidth: ring, lineCap: .round))
                    .animation(.easeInOut(duration: 0.8), value: start)
            } else {
                QuarterArc(corner: corner, inset: inset)
                    .trim(from: 0, to: face.progress)
                    .stroke(face.tone.tint(theme), style: StrokeStyle(lineWidth: ring, lineCap: .round))
            }
            QuarterArc(corner: corner, inset: 0.25)
                .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
            if let kind = face.companion {
                CompanionView(kind: kind, size: size, hovering: hovering, now: now, animate: animate)
            } else {
                faceText(accentText: accentText, textScale: textScale, compact: compact, full: full)
            }
        }
        .frame(width: size, height: size)
        .contentShape(QuarterShape(corner: corner))
        .scaleEffect(hovering ? 1.08 : 1, anchor: corner.unitPoint)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the widget")
    }

    private func faceText(accentText: Color?, textScale: CGFloat, compact: Bool, full: CGFloat) -> some View {
            // Widths follow the curve: in a top corner the label sits lower, where the quarter is
            // narrower; in a bottom corner it's the other way round. A long value shrinks to fit;
            // a long label keeps a readable size and is cut short instead.
            let side: HorizontalAlignment = corner.isRight ? .trailing : .leading
            let along: Alignment = corner.isRight ? .trailing : .leading
            let (valueWidth, labelWidth) = corner.isBottom ? (0.62, 0.68) : (0.68, 0.62)
            return VStack(alignment: side, spacing: 0) {
                Text(face.value)
                    .font(.system(size: full * 0.19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accentText ?? Color.primary)
                    .minimumScaleFactor(0.55)
                    .frame(width: size * valueWidth / textScale, alignment: along)
                label(size: max(11, full * 0.115))
                    .font(.system(size: max(11, full * 0.115), weight: .medium))
                    .foregroundStyle(accentText?.opacity(0.85) ?? Color.secondary)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .frame(width: size * labelWidth / textScale, alignment: along)
                    .opacity(compact ? 0 : 1)
            }
            .lineLimit(1)
            .scaleEffect(textScale, anchor: corner.unitPoint)
            // The same gap from the side of the screen as from the top or bottom.
            .padding(corner.isRight ? .trailing : .leading, max(7, size * 0.14))
            .padding(corner.isBottom ? .bottom : .top, max(7, size * 0.14))
    }

    /// A working Claude session is marked with Claude's sparkle, since its label is just the chat's name.
    private func label(size: CGFloat) -> Text {
        guard face.ref.isClaude, face.tone == .working else { return Text(face.label) }
        let sparkle = Text(Image(systemName: "sparkle")).font(.system(size: size * 0.8, weight: .semibold)).foregroundStyle(Color.claude)
        return sparkle + Text("\u{2009}" + face.label)
    }
}
