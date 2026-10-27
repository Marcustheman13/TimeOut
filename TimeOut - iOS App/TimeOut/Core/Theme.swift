import CoreText
import SwiftUI

/// Colors and type from the web demo's app.css (:root variables).
enum Theme {
    static let bg = Color(hex: "#0a0d12")
    static let surface = Color(hex: "#141922")
    static let raised = Color(hex: "#1d2430")
    static let raised2 = Color(hex: "#262f3d")
    static let stroke = Color(hex: "#283141")
    static let text = Color(hex: "#f2f5f9")
    static let text2 = Color(hex: "#8c96a8")
    static let muted = Color(hex: "#5e687a")
    static let accent = Color(hex: "#22d66e")
    static let accentInk = Color(hex: "#03140a")
    static let accentSoft = Color(red: 34 / 255, green: 214 / 255, blue: 110 / 255).opacity(0.13)
    static let loss = Color(hex: "#ff5a5f")
    static let lossSoft = Color(red: 1, green: 90 / 255, blue: 95 / 255).opacity(0.13)
    static let live = Color(hex: "#ff3b4a")
    static let warn = Color(hex: "#ffc940")
    static let warnSoft = Color(red: 1, green: 201 / 255, blue: 64 / 255).opacity(0.12)
    static let blue = Color(hex: "#4fb3ff")
    static let blueSoft = Color(red: 79 / 255, green: 179 / 255, blue: 1).opacity(0.13)
    static let purple = Color(hex: "#c58cff")
    static let scrim = Color.black.opacity(0.6)
    /// Sheets, the drawer and the sheet footer.
    static let sheet = Color(hex: "#0e1218")
    static let dialog = Color(hex: "#151a23")

    /// Registers the bundled Barlow and Barlow Condensed fonts (the web demo loads them from Google Fonts).
    static func registerFonts() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Barlow, the body font. Weight in CSS numbers (400–900).
    static func barlow(_ size: CGFloat, _ weight: Int = 400) -> Font {
        let name: String
        switch weight {
        case ..<500: name = "Barlow-Regular"
        case 500..<600: name = "Barlow-Medium"
        case 600..<700: name = "Barlow-SemiBold"
        case 700..<800: name = "Barlow-Bold"
        default: name = "Barlow-ExtraBold"
        }
        return .custom(name, fixedSize: size)
    }

    /// Barlow Condensed, the display font for numbers, titles and the wordmark.
    static func display(_ size: CGFloat, _ weight: Int = 800, italic: Bool = false) -> Font {
        let base: String
        switch weight {
        case ..<700: base = "BarlowCondensed-SemiBold"
        case 700..<800: base = "BarlowCondensed-Bold"
        case 800..<900: base = italic ? "BarlowCondensed-ExtraBoldItalic" : "BarlowCondensed-ExtraBold"
        default: base = italic ? "BarlowCondensed-BlackItalic" : "BarlowCondensed-Black"
        }
        return .custom(base, fixedSize: size)
    }
}

extension Color {
    /// "#RRGGBB" or "#RGB".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s.prefix(6), radix: 16) ?? 0x5A6475
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    /// Initials-avatar color for a name, matching `hsl(hash % 360, 55%, 42%)`.
    static func hashed(_ name: String) -> Color {
        let h = Double(TO.hash(name) % 360) / 360
        let s = 0.55, l = 0.42
        // HSL → HSB
        let v = l + s * min(l, 1 - l)
        let sb = v == 0 ? 0 : 2 * (1 - l / v)
        return Color(hue: h, saturation: sb, brightness: v)
    }
}

// MARK: - Text helpers

extension View {
    func eyebrow(_ color: Color = Theme.text2) -> some View {
        self.font(.barlow(11, 800)).tracking(0.88).textCase(.uppercase).foregroundStyle(color)
    }
}

/// `.card`: surface, 1px stroke, 16 radius, 14 padding.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 14
    var border: Color = Theme.stroke
    var background: Color = Theme.surface
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border, lineWidth: 1))
    }
}

extension View {
    func card(_ padding: CGFloat = 14, border: Color = Theme.stroke, background: Color = Theme.surface, radius: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding, border: border, background: background, radius: radius))
    }

    /// The 16pt side gutter used throughout (`margin: 0 16px`).
    func gutter() -> some View { padding(.horizontal, 16) }

    @ViewBuilder func `if`<V: View>(_ condition: Bool, _ transform: (Self) -> V) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Buttons (.btn)

enum BtnKind { case normal, primary, warn, danger, ghost, quiet }
enum BtnSize { case md, sm, xs }

struct BtnStyle: ButtonStyle {
    var kind: BtnKind = .normal
    var size: BtnSize = .md
    var full = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let h: CGFloat = size == .md ? 48 : size == .sm ? 36 : 30
        let r: CGFloat = size == .md ? 14 : size == .sm ? 11 : 9
        let fs: CGFloat = size == .md ? 16 : size == .sm ? 14 : 13
        let pad: CGFloat = size == .md ? 18 : size == .sm ? 12 : 10
        let (bg, fg, border): (Color, Color, Color) = {
            switch kind {
            case .normal: return (Theme.raised, Theme.text, Theme.stroke)
            case .primary: return (Theme.accent, Theme.accentInk, .clear)
            case .warn: return (Theme.warn, Color(hex: "#1d1600"), .clear)
            case .danger: return (Theme.loss, .white, .clear)
            case .ghost: return (.clear, Theme.text, Theme.stroke)
            case .quiet: return (.clear, Theme.text2, .clear)
            }
        }()
        return configuration.label
            .font(.barlow(fs, 800))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(fg)
            .padding(.horizontal, pad)
            .frame(height: h)
            .frame(maxWidth: full ? .infinity : nil)
            .background(bg, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: r))
            .opacity(enabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && enabled ? 0.985 : 1)
    }
}

extension ButtonStyle where Self == BtnStyle {
    static func btn(_ kind: BtnKind = .normal, _ size: BtnSize = .md, full: Bool = false) -> BtnStyle { BtnStyle(kind: kind, size: size, full: full) }
}

/// Buttons that should only give press feedback (rows, cards, odds).
struct PlainPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == PlainPress {
    static var press: PlainPress { PlainPress() }
}

/// A button-label row: icon + text with the `.btn` 8pt gap.
struct BtnLabel: View {
    var icon: IconName?
    var text: String
    var iconSize: CGFloat = 18
    init(_ text: String, icon: IconName? = nil, iconSize: CGFloat = 18) {
        self.text = text
        self.icon = icon
        self.iconSize = iconSize
    }
    var body: some View {
        HStack(spacing: 8) {
            if let icon { Icon(icon, iconSize) }
            Text(text)
        }
    }
}
