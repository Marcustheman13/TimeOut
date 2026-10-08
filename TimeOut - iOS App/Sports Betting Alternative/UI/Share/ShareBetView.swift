import SwiftUI

/// PRD: tapping Share creates an image with the teams, pick, odds and stake, plus an optional custom
/// reward or punishment (up to 100 characters) for betting with a friend.
struct ShareBetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let bet: Bet

    @State private var challenge: String
    @State private var image: Image?
    @State private var logos: [URL: UIImage] = [:]

    init(bet: Bet) {
        self.bet = bet
        _challenge = State(initialValue: bet.friendStake ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    BetShareCard(bet: bet, challenge: challenge, logos: logos, tier: model.tier)
                        .clipShape(.rect(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.6), radius: 20, y: 10)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(bet.isFriendBet ? "What's on the line" : "Add a challenge (optional)")
                            .font(.system(size: 15, weight: .heavy))
                        TextField("e.g. Loser does the dishes", text: $challenge, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(12)
                            .background(Theme.raised, in: .rect(cornerRadius: 12))
                            .onChange(of: challenge) { _, value in
                                if value.count > BetBook.friendStakeLimit {
                                    challenge = String(value.prefix(BetBook.friendStakeLimit))
                                }
                            }
                        HStack {
                            Text("Friends see this on the card instead of a screen time stake.")
                            Spacer()
                            Text("\(challenge.count)/\(BetBook.friendStakeLimit)")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                    }
                    .card()
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Share Bet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let image {
                    ShareLink(item: image, message: Text(shareMessage), preview: SharePreview(bet.title, image: image)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Theme.accent, in: .rect(cornerRadius: 14))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .task { await loadLogos(); render() }
            .onChange(of: challenge) { render() }
        }
    }

    private var shareMessage: String {
        let pick = bet.legs.map(\.label).joined(separator: " + ")
        if !challenge.isEmpty {
            return "I'm taking \(pick). \(challenge). You in? 🏈 via \(Theme.brand)"
        }
        return "I've got \(bet.stake) min of screen time on \(pick). via \(Theme.brand)"
    }

    private func loadLogos() async {
        let urls = Set(bet.legs.flatMap { [$0.game.home.logoURL, $0.game.away.logoURL] }.compactMap { $0 })
        for url in urls where logos[url] == nil {
            if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                logos[url] = image
            }
        }
    }

    private func render() {
        let renderer = ImageRenderer(content: BetShareCard(bet: bet, challenge: challenge, logos: logos, tier: model.tier))
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            image = Image(uiImage: uiImage)
        }
    }
}

/// The image that gets shared. Fixed width so it renders the same everywhere.
struct BetShareCard: View {
    let bet: Bet
    var challenge: String
    var logos: [URL: UIImage] = [:]
    var tier: Tier = .rookie

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .foregroundStyle(Theme.accent)
                    Text(Theme.brand)
                        .font(.display(22, weight: .black))
                        .italic()
                        .foregroundStyle(.white)
                    if tier > .rookie {
                        TierBadge(tier: tier, compact: true)
                    }
                }
                Spacer()
                if bet.status != .open {
                    StatusPill(status: bet.status)
                } else {
                    Text(bet.isParlay ? "\(bet.legs.count)-LEG PARLAY" : "SINGLE")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(spacing: 14) {
                ForEach(bet.legs) { leg in
                    HStack(spacing: 12) {
                        HStack(spacing: -8) {
                            TeamBadge(team: leg.game.away, size: 34, preloaded: leg.game.away.logoURL.flatMap { logos[$0] })
                            TeamBadge(team: leg.game.home, size: 34, preloaded: leg.game.home.logoURL.flatMap { logos[$0] })
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(leg.label)
                                .font(.display(22, weight: .black))
                                .foregroundStyle(.white)
                            Text("\(leg.game.away.fullName) @ \(leg.game.home.fullName)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(Odds.format(leg.selection.price))
                            .font(.display(20))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            Rectangle().fill(Theme.stroke).frame(height: 1)

            if !challenge.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ON THE LINE")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.warning)
                    Text(challenge)
                        .font(.display(24, weight: .heavy))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    stat("STAKE", "\(bet.stake) MIN", .white)
                    Spacer()
                    stat("ODDS", Odds.format(bet.americanOdds), .white)
                    Spacer()
                    switch bet.status {
                    case .won: stat("WON", "+\(bet.netMinutes) MIN", Theme.win)
                    case .lost: stat("LOST", "\(bet.netMinutes) MIN", Theme.loss)
                    default: stat("TO WIN", "\(bet.potentialWinnings) MIN", Theme.accent)
                    }
                }
            }

            Text(bet.isFriendBet ? "Friendly wager. No real-money betting." : "Screen time, not money. No real-money betting.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(22)
        .frame(width: 360)
        .background(
            LinearGradient(colors: [Color(hex: "16202B"), Theme.background], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Theme.accent.opacity(0.18))
                .frame(width: 180)
                .blur(radius: 50)
                .offset(x: 60, y: -60)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .black)).foregroundStyle(Theme.textMuted)
            Text(value).font(.display(22, weight: .black)).foregroundStyle(color)
        }
    }
}
