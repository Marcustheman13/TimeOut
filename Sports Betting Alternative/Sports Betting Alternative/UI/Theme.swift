import SwiftUI

/// Dark sportsbook look: near-black canvas, raised cards, bright green for money-in, red for money-out.
enum Theme {
    static let background = Color(hex: "0A0D12")
    static let surface = Color(hex: "141922")
    static let raised = Color(hex: "1D2430")
    static let stroke = Color(hex: "283141")
    static let textSecondary = Color(hex: "8C96A8")
    static let textMuted = Color(hex: "5E687A")

    static let accent = Color(hex: "22D66E")
    static let win = Color(hex: "22D66E")
    static let loss = Color(hex: "FF5A5F")
    static let live = Color(hex: "FF3B4A")
    static let warning = Color(hex: "FFC940")

    /// Colorblind-safe pair for charts (validated: CVD ΔE ≥ 12 on the dark surface).
    static let chartGain = Color(hex: "1AA590")
    static let chartLoss = Color(hex: "E26A3B")

    static let brand = "StakeTime"
}

extension Font {
    /// Condensed heavy display type, the way sportsbooks set scores and odds.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.35; g = 0.39; b = 0.46
        }
        self.init(red: r, green: g, blue: b)
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardBackground(padding: padding)) }
}

/// Team logo from ESPN, falling back to a colored disc with the abbreviation.
struct TeamBadge: View {
    let team: Team
    var size: CGFloat = 26
    /// Pre-loaded logo, used when rendering to an image (ImageRenderer doesn't wait for AsyncImage).
    var preloaded: UIImage?

    var body: some View {
        Group {
            if let preloaded {
                Image(uiImage: preloaded).resizable().scaledToFit()
            } else if let url = team.logoURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Circle()
            .fill(Color(hex: team.colorHex))
            .overlay(
                Text(team.abbreviation.prefix(3))
                    .font(.system(size: size * 0.34, weight: .black))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            )
    }
}

struct LiveBadge: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Theme.live).frame(width: 6, height: 6)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            Text("LIVE").font(.system(size: 11, weight: .black))
        }
        .foregroundStyle(Theme.live)
        .onAppear { pulse = true }
    }
}

struct StatusPill: View {
    let status: BetStatus

    var body: some View {
        Text(status.title.uppercased())
            .font(.system(size: 11, weight: .black))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(background, in: .capsule)
    }

    private var foreground: Color {
        switch status {
        case .won: .black
        case .lost: .white
        default: .white
        }
    }

    private var background: Color {
        switch status {
        case .open: Theme.raised
        case .won: Theme.win
        case .lost: Theme.loss
        case .push, .void: Theme.textMuted
        }
    }
}

nonisolated extension Int {
    /// "+12 min" / "−8 min" / "0 min".
    var signedMinutes: String {
        self > 0 ? "+\(self) min" : self < 0 ? "−\(abs(self)) min" : "0 min"
    }
}

/// Countdown to local midnight, when the betting balance resets.
struct MidnightCountdown: View {
    var font: Font = .display(28)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Int(DayClock.nextMidnight(after: context.date).timeIntervalSince(context.date))
            Text(String(format: "%02d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60))
                .font(font)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}
