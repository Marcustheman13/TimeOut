import SwiftUI
import UIKit

// MARK: - Team badge, tier badge, avatar

/// `.team-badge`: the team's color disc with its ESPN logo, or the abbreviation.
struct TeamBadge: View {
    var team: Team
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: team.color))
            Text(team.abbr)
                .font(.display(max(9, (size * 0.3).rounded()), 900))
                .tracking(-0.2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
            if let logo = team.logo, let url = URL(string: logo) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        ZStack { Circle().fill(Color(hex: team.color)); image.resizable().scaledToFit() }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1.5))
    }
}

/// `.gc-live-logo`: the raised disc with a logo used on live/ESPN game cards.
struct LiveLogo: View {
    var team: Team
    var body: some View {
        ZStack {
            Circle().fill(Theme.raised)
            Text(team.abbr).font(.barlow(9, 900)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
            if let logo = team.logo, let url = URL(string: logo) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { ZStack { Circle().fill(Theme.raised); image.resizable().scaledToFit() } }
                }
            }
        }
        .frame(width: 27, height: 27)
        .clipShape(Circle())
    }
}

struct TierBadge: View {
    var tierId: String
    var sm = false
    var body: some View {
        let t = Store.tierById(tierId)
        let rookie = t.id == "rookie"
        HStack(spacing: 5) {
            Icon(t.icon, sm ? 11 : 13)
            Text(t.title.uppercased()).font(.barlow(sm ? 10 : 11, 900)).tracking(0.55)
        }
        .foregroundStyle(rookie ? Theme.text : Color(hex: "#06110a"))
        .padding(.horizontal, sm ? 7 : 9)
        .frame(height: sm ? 20 : 24)
        .background(rookie ? Theme.raised : Color(hex: t.color), in: Capsule())
        .fixedSize()
    }
}

/// A profile photo: a data URL (JPEG or the initials SVG), a web URL, or initials.
struct Avatar: View {
    var src: String
    var size: CGFloat = 36

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(Theme.raised)
            .clipShape(Circle())
    }

    @ViewBuilder private var content: some View {
        if let image = Self.image(src) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let svg = Self.initials(src) {
            ZStack {
                svg.color
                Text(svg.text).font(.system(size: size * 38 / 96, weight: .bold)).foregroundStyle(.white)
            }
        } else if let url = URL(string: src), src.hasPrefix("http") {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { Theme.raised }
            }
        } else {
            Theme.raised
        }
    }

    private static var imageCache: [String: UIImage] = [:]

    static func image(_ src: String) -> UIImage? {
        guard src.hasPrefix("data:image/"), !src.hasPrefix("data:image/svg"), let comma = src.firstIndex(of: ",") else { return nil }
        if let hit = imageCache[src] { return hit }
        guard let data = Data(base64Encoded: String(src[src.index(after: comma)...])), let img = UIImage(data: data) else { return nil }
        imageCache[src] = img
        return img
    }

    /// Reads the color and letters back out of an initials-avatar SVG.
    static func initials(_ src: String) -> (color: Color, text: String)? {
        guard src.hasPrefix("data:image/svg"), let comma = src.firstIndex(of: ",") else { return nil }
        let svg = String(src[src.index(after: comma)...]).removingPercentEncoding ?? ""
        let fill = svg.range(of: #"<rect[^>]*fill="([^"]+)""#, options: .regularExpression).map { String(svg[$0]) } ?? ""
        let colorStr = fill.range(of: #"fill="([^"]+)""#, options: .regularExpression).map { String(fill[$0].dropFirst(6).dropLast()) } ?? ""
        let text = svg.range(of: #">([^<]*)</text>"#, options: .regularExpression).map { String(svg[$0].dropFirst().dropLast(7)) } ?? "?"
        return (parseColor(colorStr), text)
    }

    private static func parseColor(_ s: String) -> Color {
        if s.hasPrefix("#") { return Color(hex: s) }
        if s.hasPrefix("hsl(") {
            let nums = s.dropFirst(4).dropLast().split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }
            if nums.count >= 3 {
                let h = nums[0] / 360, sat = nums[1] / 100, l = nums[2] / 100
                let v = l + sat * min(l, 1 - l)
                return Color(hue: h, saturation: v == 0 ? 0 : 2 * (1 - l / v), brightness: v)
            }
        }
        return Theme.raised
    }
}

// MARK: - Small labels

struct StatusPill: View {
    var status: String
    var body: some View {
        let label = ["won": "Won", "lost": "Lost", "void": "Void", "push": "Push", "open": "Open"][status] ?? status
        let (bg, fg): (Color, Color) = {
            switch status {
            case "won": return (Theme.accent, Theme.accentInk)
            case "lost": return (Theme.loss, .white)
            case "void", "push": return (Theme.muted, .white)
            default: return (Theme.raised, Theme.text)
            }
        }()
        Text(label.uppercased()).font(.barlow(11, 900)).tracking(0.55)
            .foregroundStyle(fg).padding(.horizontal, 8).frame(height: 22).background(bg, in: Capsule())
    }
}

enum TagTone { case plain, green, red, yellow, blue }

struct Tag: View {
    var text: String
    var tone: TagTone = .plain
    var icon: IconName?
    var color: Color?
    var big = false

    init(_ text: String, _ tone: TagTone = .plain, icon: IconName? = nil, color: Color? = nil, big: Bool = false) {
        self.text = text; self.tone = tone; self.icon = icon; self.color = color; self.big = big
    }

    var body: some View {
        let (bg, fg): (Color, Color) = {
            switch tone {
            case .plain: return (Theme.raised, Theme.text2)
            case .green: return (Theme.accentSoft, Theme.accent)
            case .red: return (Theme.lossSoft, Theme.loss)
            case .yellow: return (Theme.warnSoft, Theme.warn)
            case .blue: return (Theme.blueSoft, Theme.blue)
            }
        }()
        HStack(spacing: 4) {
            if let icon { Icon(icon, 10) }
            Text(text.uppercased()).font(.barlow(big ? 12 : 10.5, 800)).tracking(0.42)
        }
        .foregroundStyle(color ?? fg)
        .padding(.horizontal, 7)
        .frame(height: big ? 24 : 20)
        .background(bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
    }
}

/// The red "LIVE" label with its pulsing dot.
struct LiveTag: View {
    var text = "LIVE"
    @State private var dim = false
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Theme.live).frame(width: 6, height: 6).opacity(dim ? 0.3 : 1)
            if !text.isEmpty { Text(text).font(.barlow(11, 900)).tracking(0.44) }
        }
        .foregroundStyle(Theme.live)
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true } }
    }
}

struct CountPill: View {
    var n: Int
    var off = false
    var bg: Color?
    var fg: Color?
    var body: some View {
        Text("\(n)").font(.barlow(12, 800))
            .foregroundStyle(fg ?? (off ? Theme.text2 : Theme.accentInk))
            .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 20)
            .background(bg ?? (off ? Theme.raised : Theme.accent), in: Capsule())
    }
}

enum NoteTone { case plain, warn, red, green, blue }

/// `.note`: a tinted message box with an icon.
struct Note<Content: View>: View {
    var tone: NoteTone = .plain
    var icon: IconName?
    var content: Content

    init(_ tone: NoteTone = .plain, icon: IconName? = nil, @ViewBuilder content: () -> Content) {
        self.tone = tone; self.icon = icon; self.content = content()
    }

    var body: some View {
        let (bg, fg): (Color, Color) = {
            switch tone {
            case .plain: return (Theme.raised, Theme.text2)
            case .warn: return (Theme.warnSoft, Theme.warn)
            case .red: return (Theme.lossSoft, Theme.loss)
            case .green: return (Theme.accentSoft, Theme.accent)
            case .blue: return (Theme.blueSoft, Theme.blue)
            }
        }()
        HStack(alignment: .top, spacing: 8) {
            if let icon { Icon(icon, 16).padding(.top, 1) }
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.barlow(13, 600))
        .foregroundStyle(fg)
        .lineSpacing(1.5)
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension Note where Content == Text {
    init(_ tone: NoteTone = .plain, icon: IconName? = nil, _ text: AttributedString) {
        self.init(tone, icon: icon) { Text(text) }
    }
    init(_ tone: NoteTone = .plain, icon: IconName? = nil, _ text: String) {
        self.init(tone, icon: icon) { Text(verbatim: text) }
    }
    init(_ tone: NoteTone = .plain, icon: IconName? = nil, markdown: String) {
        self.init(tone, icon: icon) { Text(md(markdown)) }
    }
}

struct FormError: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.barlow(13.5, 700)).foregroundStyle(Theme.loss)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(Theme.lossSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct Bar: View {
    var pct: Double
    var color: Color = Theme.accent
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                RoundedRectangle(cornerRadius: height / 2).fill(color).frame(width: max(0, min(1, pct / 100)) * geo.size.width)
                    .animation(.easeOut(duration: 0.4), value: pct)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2))
    }
}

struct HRule: View {
    var body: some View { Rectangle().fill(Theme.stroke).frame(height: 1) }
}

struct VRule: View {
    var body: some View { Rectangle().fill(Theme.stroke).frame(width: 1) }
}

/// `.section-title` row with an h2.
struct SectionTitle<Trailing: View>: View {
    var title: String
    var trailing: Trailing
    init(_ title: String, @ViewBuilder trailing: () -> Trailing) { self.title = title; self.trailing = trailing() }
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.barlow(17, 800)).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
            trailing
        }
    }
}

struct H2: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.barlow(17, 800)).foregroundStyle(Theme.text) }
}

/// `.page-head`: big condensed title and a short description.
struct PageHead: View {
    var title: String
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.display(34, 900)).foregroundStyle(Theme.text)
            Text(text).font(.barlow(14)).foregroundStyle(Theme.text2).frame(maxWidth: 290, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4).padding(.horizontal, 16).padding(.bottom, 10)
    }
}

// MARK: - Chips and segmented control

struct Chip: View {
    var label: String
    var on = false
    var n: Int = 0
    var icon: IconName?
    var dashed = false
    var sm = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Icon(icon, 14) }
                Text(label).font(.barlow(sm ? 12.5 : 14, 700))
                if n > 0 { Text("\(n)").font(.barlow(11, 800)).foregroundStyle(on ? Theme.accentInk.opacity(0.6) : Theme.muted) }
            }
            .foregroundStyle(on ? Theme.accentInk : dashed ? Theme.text2 : Theme.text)
            .padding(.horizontal, sm ? 10 : 13)
            .frame(height: sm ? 28 : 34)
            .background(on ? Theme.accent : dashed ? Color.clear : Theme.surface, in: Capsule())
            .overlay {
                if dashed { Capsule().strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
                else if !on { Capsule().strokeBorder(Theme.stroke, lineWidth: 1) }
            }
            .fixedSize()
        }
        .buttonStyle(.press)
    }
}

struct Seg<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        HStack(spacing: 3) { content }
            .padding(3)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

struct SegButton<Label: View>: View {
    var on: Bool
    var action: () -> Void
    var label: Label
    init(on: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) { self.on = on; self.action = action; self.label = label() }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { label }
                .font(.barlow(14, 700))
                .foregroundStyle(on ? Theme.text : Theme.text2)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(on ? Theme.raised2 : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.press)
    }
}

/// `.switch`: 50×30 track, white knob.
struct SwitchView: View {
    var isOn: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.accent : Theme.raised2)
                Circle().fill(.white).frame(width: 24, height: 24).padding(3)
            }
            .frame(width: 50, height: 30)
            .animation(.easeOut(duration: 0.2), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct CheckBox: View {
    var on: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Theme.accent : .clear)
            RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(on ? Theme.accent : Theme.muted, lineWidth: 2)
            if on { Icon(.check, 15).foregroundStyle(Theme.accentInk) }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Lists

/// `.list`: a rounded surface with hairlines between rows.
struct ListBox<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        Group(subviews: content) { subviews in
            VStack(spacing: 0) {
                ForEach(subviews.indices, id: \.self) { i in
                    if i > 0 { HRule() }
                    subviews[i]
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// `.list-row`: icon tile, title and subtitle, then a trailing control.
struct ListRow<Leading: View, Trailing: View>: View {
    var title: String
    var sub: AttributedString?
    var leading: Leading
    var trailing: Trailing

    init(_ title: String, sub: AttributedString? = nil, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.sub = sub; self.leading = leading(); self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.barlow(15, 700)).foregroundStyle(Theme.text)
                if let sub { Text(sub).font(.barlow(12.5)).foregroundStyle(Theme.text2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

/// `.lr-icon`: the 32pt rounded icon tile at the start of a list row.
struct LrIcon: View {
    var icon: IconName
    var bg: Color = Theme.raised
    var fg: Color = Theme.text2
    var size: CGFloat = 32
    var iconSize: CGFloat = 17
    var body: some View {
        Icon(icon, iconSize).foregroundStyle(fg)
            .frame(width: size, height: size)
            .background(bg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// `.sport-opt .sq`: the league short name in a 40pt tile.
struct SportSquare: View {
    var text: String
    var body: some View {
        Text(text).font(.display(13, 900)).foregroundStyle(Theme.text)
            .frame(width: 40, height: 40)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct HowCard: View {
    var n: Int
    var title: String
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").font(.display(19, 900)).foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.barlow(16, 700)).foregroundStyle(Theme.text)
                Text(text).font(.barlow(14)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// `.empty`: centered icon, title, text and actions.
struct EmptyState<Actions: View>: View {
    var icon: IconName
    var iconSize: CGFloat = 40
    var title: String
    var text: String?
    var actions: Actions

    init(icon: IconName, iconSize: CGFloat = 40, title: String, text: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.icon = icon; self.iconSize = iconSize; self.title = title; self.text = text; self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 10) {
            Icon(icon, iconSize).foregroundStyle(Theme.muted)
            Text(title).font(.barlow(18, 700)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            if let text { Text(text).font(.barlow(14)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).frame(maxWidth: 270) }
            actions
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 22)
    }
}

extension EmptyState where Actions == EmptyView {
    init(icon: IconName, iconSize: CGFloat = 40, title: String, text: String? = nil) {
        self.init(icon: icon, iconSize: iconSize, title: title, text: text) { EmptyView() }
    }
}

// MARK: - Countdown

/// A live HH:MM:SS countdown to a moment, updated every second.
struct Countdown: View {
    var target: Ms
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(Fmt.countdown(target - TO.now())).monospacedDigit()
        }
    }
}

// MARK: - Odds button

/// One odds button. Tapping adds or removes the pick on the bet slip.
struct OddsButton: View {
    var sel: Selection
    var suspended = false
    var move: Int?
    var big = false
    var label: String?
    var compact = false

    var body: some View {
        let on = Slip.shared.has(sel.id)
        let ln: String? = sel.market == "spread" ? OddsMath.fmtLine(sel.line ?? 0)
            : sel.market == "total" ? "\(sel.side == "over" ? "O" : "U") \(OddsMath.fmtLine(sel.line ?? 0, signed: false))" : nil
        Button { Slip.shared.toggle(sel.id) } label: {
            VStack(spacing: 1) {
                if suspended {
                    Icon(.lock, 14).foregroundStyle(Theme.muted)
                } else {
                    if big, let label {
                        Text(label).font(.barlow(compact ? 10 : 12, 700)).foregroundStyle(on ? Theme.accentInk : Theme.text2).lineLimit(1).truncationMode(.tail)
                    }
                    if let ln { Text(ln).font(.barlow(compact ? 11 : 12.5, 700)).foregroundStyle(on ? Theme.accentInk : Theme.text) }
                    HStack(spacing: 2) {
                        if let move, move != 0 {
                            Text(move > 0 ? "▲" : "▼").font(.system(size: 8)).foregroundStyle(on ? Theme.accentInk : move > 0 ? Theme.accent : Theme.loss)
                        }
                        Text(OddsMath.fmt(sel.price))
                            .font(.barlow(compact ? 12 : (ln == nil && !(big && label != nil) ? 15 : 13.5), 800))
                            .monospacedDigit()
                            .foregroundStyle(on ? Theme.accentInk : Theme.accent)
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 48 : big ? 56 : 46)
            .background(on ? Theme.accent : Theme.raised, in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous).strokeBorder(on ? .clear : Theme.stroke, lineWidth: 1))
            .opacity(suspended ? 0.55 : 1)
        }
        .buttonStyle(.press)
        .disabled(suspended)
        .accessibilityLabel("\(label ?? "") \(ln ?? "") \(OddsMath.fmt(sel.price))\(suspended ? " suspended" : "")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A disabled odds button for a market with no line ("N/A" / "—").
struct UnavailableOdds: View {
    var label: String
    var text: String
    var compact = false
    var body: some View {
        VStack(spacing: 1) {
            Text(label).font(.barlow(compact ? 10 : 12, 700)).foregroundStyle(Theme.text2).lineLimit(1)
            Text(text).font(.barlow(compact ? 12 : 13.5, 800)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).frame(height: compact ? 48 : 56)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .opacity(0.55)
        .accessibilityLabel("\(label) unavailable")
    }
}

// MARK: - Form fields

/// `.field`: label, input, then an error or hint.
struct FieldView: View {
    var label: String
    @Binding var text: String
    var placeholder = ""
    var secure = false
    var err: String?
    var hint: String?
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType?
    var autocap = false

    @State private var reveal = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.barlow(13, 700)).foregroundStyle(Theme.text2)
            HStack(spacing: 0) {
                Group {
                    if secure && !reveal {
                        SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.muted))
                    } else {
                        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.muted))
                    }
                }
                .focused($focused)
                .font(.barlow(16))
                .foregroundStyle(Theme.text)
                .keyboardType(keyboard)
                .textContentType(content)
                .textInputAutocapitalization(autocap ? .sentences : .never)
                .autocorrectionDisabled(!autocap)
                if secure {
                    Button { reveal.toggle() } label: {
                        Icon(reveal ? .eyeOff : .eye, 18).foregroundStyle(Theme.text2).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(reveal ? "Hide password" : "Show password")
                    .padding(.trailing, -10)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(err != nil ? Theme.loss : focused ? Theme.accent : Theme.stroke, lineWidth: 1))
            if let err { Text(err).font(.barlow(12.5, 600)).foregroundStyle(Theme.loss) }
            else if let hint { Text(hint).font(.barlow(12.5)).foregroundStyle(Theme.muted) }
        }
    }
}

/// Copies text to the clipboard (the web demo's ui.copy).
enum Clipboard {
    static func copy(_ text: String) -> Bool {
        UIPasteboard.general.string = text
        return true
    }
}

/// Crops a picked photo to a 256px square JPEG data URL, like the web demo's readPhoto.
enum PhotoData {
    static func dataURL(from data: Data) -> String? {
        guard let img = UIImage(data: data) else { return nil }
        let side = min(img.size.width, img.size.height)
        let crop = CGRect(x: (img.size.width - side) / 2, y: (img.size.height - side) / 2, width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let out = renderer.image { _ in
            img.draw(in: CGRect(x: -crop.minX * 256 / side, y: -crop.minY * 256 / side, width: img.size.width * 256 / side, height: img.size.height * 256 / side))
        }
        guard let jpeg = out.jpegData(compressionQuality: 0.85) else { return nil }
        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }
}
