import AppKit
import CornerKit
import SwiftUI

/// Colors for the corner, card and history window. Alerts stay red and "soon" stays amber in
/// every theme, so they always read as warnings.
struct Theme {
    let id: ThemeID
    let name: String
    /// Progress rings, bars and controls.
    let accent: Color
    /// Laid over the glass, top-left to bottom-right. Empty keeps the plain glass.
    let wash: [Color]
    /// Paints `wash` as an opaque background instead of tinting the glass.
    let solid: Bool
    let timer: Color
    let meeting: Color
    let countdown: Color
    let todo: Color
    let stopwatch: Color
    let workday: Color

    /// Solid themes draw their own dark background, so their text is always light.
    var forcedScheme: ColorScheme? { solid ? .dark : nil }
    var isPlain: Bool { id == .system }
    /// Chip and button fills pick up the accent in colored themes.
    var controlFill: Color { isPlain ? Color.primary.opacity(0.08) : accent.opacity(0.2) }

    static func named(_ id: ThemeID) -> Theme { all.first { $0.id == id } ?? all[0] }

    static let all: [Theme] = [
        Theme(id: .system, name: "Glass", accent: .accentColor, wash: [], solid: false,
              timer: .accentColor, meeting: .accentColor, countdown: .secondary, todo: .accentColor,
              stopwatch: .secondary, workday: .secondary),
        Theme(id: .ocean, name: "Ocean", accent: .vivid(0x38BDF8), wash: [.vivid(0x0EA5E9), .vivid(0x6366F1)], solid: false,
              timer: .vivid(0x38BDF8), meeting: .vivid(0x60A5FA), countdown: .vivid(0x22D3EE), todo: .vivid(0x34D399),
              stopwatch: .vivid(0x818CF8), workday: .vivid(0x38BDF8)),
        Theme(id: .sunset, name: "Sunset", accent: .vivid(0xF472B6), wash: [.vivid(0xF97316), .vivid(0xDB2777)], solid: false,
              timer: .vivid(0xFB923C), meeting: .vivid(0xF472B6), countdown: .vivid(0xF87171), todo: .vivid(0xFBBF24),
              stopwatch: .vivid(0xE879F9), workday: .vivid(0xFB923C)),
        Theme(id: .forest, name: "Forest", accent: .vivid(0x34D399), wash: [.vivid(0x059669), .vivid(0x0D9488)], solid: false,
              timer: .vivid(0x34D399), meeting: .vivid(0x2DD4BF), countdown: .vivid(0xA3E635), todo: .vivid(0x4ADE80),
              stopwatch: .vivid(0xFBBF24), workday: .vivid(0x34D399)),
        Theme(id: .lavender, name: "Lavender", accent: .vivid(0xA78BFA), wash: [.vivid(0x7C3AED), .vivid(0xDB2777)], solid: false,
              timer: .vivid(0xA78BFA), meeting: .vivid(0xC084FC), countdown: .vivid(0xF0ABFC), todo: .vivid(0x818CF8),
              stopwatch: .vivid(0xF472B6), workday: .vivid(0xA78BFA)),
        Theme(id: .aurora, name: "Aurora", accent: .vivid(0x22D3EE),
              wash: [.vivid(0x06B6D4), .vivid(0x8B5CF6), .vivid(0xEC4899)], solid: false,
              timer: .vivid(0x22D3EE), meeting: .vivid(0xA78BFA), countdown: .vivid(0xF472B6), todo: .vivid(0x4ADE80),
              stopwatch: .vivid(0xFBBF24), workday: .vivid(0x22D3EE)),
        Theme(id: .midnight, name: "Midnight", accent: Color(rgb: 0xFBBF24),
              wash: [Color(rgb: 0x0F172A), Color(rgb: 0x312E81)], solid: true,
              timer: Color(rgb: 0xFBBF24), meeting: Color(rgb: 0x60A5FA), countdown: Color(rgb: 0xF472B6),
              todo: Color(rgb: 0x34D399), stopwatch: Color(rgb: 0xA78BFA), workday: Color(rgb: 0xFBBF24)),
    ]
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }

    /// The color as given in dark mode, a quarter darker in light mode so it holds up on pale glass.
    static func vivid(_ rgb: UInt32) -> Color {
        let base = NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? base : (base.blended(withFraction: 0.25, of: .black) ?? base)
        })
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.named(.system)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// Hands the theme to every view below, and forces dark text for solid themes.
    @ViewBuilder
    func themed(_ theme: Theme) -> some View {
        let base = environment(\.theme, theme).tint(theme.accent)
        if let scheme = theme.forcedScheme {
            base.environment(\.colorScheme, scheme)
        } else {
            base
        }
    }
}

/// The glass (or a solid theme's own background) behind the corner and the card.
struct ThemedBackground: View {
    let kind: GlassBackground.Kind
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.screenCorner) private var corner

    var body: some View {
        let shape = kind == .quarter ? AnyShape(QuarterShape(corner: corner)) : AnyShape(corner.cardShape)
        let gradient = LinearGradient(colors: theme.wash, startPoint: corner.unitPoint, endPoint: corner.opposite)
        ZStack {
            if theme.solid {
                shape.fill(gradient).opacity(0.96)
            } else {
                Glass(kind: kind)
                if !theme.wash.isEmpty {
                    shape.fill(gradient).opacity(scheme == .dark ? 0.34 : 0.24)
                }
            }
        }
    }
}

/// A theme's thumbnail in Settings: its corner, ring and accent.
struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 5) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .underPageBackgroundColor))
                    preview
                }
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? theme.accent : Color.primary.opacity(0.15), lineWidth: selected ? 2.5 : 1)
                )
                Text(theme.name)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var preview: some View {
        let fill: AnyShapeStyle = theme.wash.isEmpty
            ? AnyShapeStyle(Color.gray.opacity(0.35))
            : AnyShapeStyle(LinearGradient(colors: theme.wash, startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(theme.solid ? 1 : 0.75))
        return ZStack(alignment: .topLeading) {
            QuarterShape().fill(fill)
            QuarterArc(inset: 4)
                .trim(from: 0, to: 0.62)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .frame(width: 46, height: 46)
    }
}
