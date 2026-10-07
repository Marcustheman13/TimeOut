import SwiftUI

struct MyBetsView: View {
    @Environment(AppModel.self) private var model
    @State private var segment = Segment.open

    enum Segment: String, CaseIterable {
        case open = "Open"
        case settled = "Settled"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    Picker("Bets", selection: $segment) {
                        ForEach(Segment.allCases, id: \.self) { segment in
                            Text(segment == .open ? "Open (\(model.book.openBets.count))" : "Settled")
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 4)

                    let bets = segment == .open ? model.book.openBets : model.book.settledBets
                    if bets.isEmpty {
                        ContentUnavailableView(
                            segment == .open ? "No open bets" : "No settled bets yet",
                            systemImage: "ticket",
                            description: Text(segment == .open ? "Pick a line on the Sportsbook tab to get started." : "Your bet history shows up here.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(bets) { bet in
                            BetCard(bet: bet)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("My Bets")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .refreshable { await model.tick() }
        }
    }
}

struct BetCard: View {
    @Environment(AppModel.self) private var model
    let bet: Bet

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatusPill(status: bet.status)
                if bet.isFriendBet {
                    Label("Friend Bet", systemImage: "person.2.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.warning)
                }
                Spacer()
                Text(bet.isParlay ? "\(bet.legs.count)-LEG PARLAY" : "SINGLE")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.textMuted)
                Text(Odds.format(bet.americanOdds))
                    .font(.display(16))
                    .foregroundStyle(Theme.textSecondary)
            }

            ForEach(bet.legs) { leg in
                legRow(leg)
            }

            if bet.multiplier > 1 || bet.isInsured {
                HStack(spacing: 6) {
                    if bet.isBoosted { perkChip("BOOSTED", icon: "bolt.fill", color: Color(hex: "4FB3FF")) }
                    if bet.multiplier > 1 { perkChip("WINS \(Rewards.formatMultiplier(bet.multiplier))", icon: "arrow.up.right", color: Theme.accent) }
                    if bet.isInsured {
                        perkChip(bet.insurancePaid == true ? "INSURANCE PAID" : "INSURED", icon: "shield.lefthalf.filled", color: Color(hex: "C58CFF"))
                    }
                }
            }

            Divider().overlay(Theme.stroke)

            HStack(alignment: .bottom) {
                if let friend = bet.friendStake {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ON THE LINE").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.textMuted)
                        Text(friend).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.warning)
                    }
                } else {
                    amount("STAKE", "\(bet.stake) min", .white)
                    Spacer()
                    resultAmount
                }
                Spacer(minLength: 8)
                Button {
                    model.sharing = bet
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Theme.raised, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share bet")
            }

            Text(footnote)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
        }
        .card()
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 14)
        }
    }

    private func perkChip(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: .capsule)
    }

    private var accent: Color {
        switch bet.status {
        case .open: Theme.accent.opacity(0.5)
        case .won: Theme.win
        case .lost: Theme.loss
        case .push, .void: Theme.textMuted
        }
    }

    @ViewBuilder
    private var resultAmount: some View {
        switch bet.status {
        case .open: amount("TO WIN", "\(bet.potentialWinnings) min", Theme.accent)
        case .won: amount("WON", bet.netMinutes.signedMinutes, Theme.win)
        case .lost: amount("LOST", bet.netMinutes.signedMinutes, Theme.loss)
        case .push, .void: amount("REFUNDED", "\(bet.payout) min", Theme.textSecondary)
        }
    }

    private func amount(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.textMuted)
            Text(value).font(.display(20)).foregroundStyle(color)
        }
    }

    private func legRow(_ leg: BetLeg) -> some View {
        let game = model.feed.game(id: leg.game.gameID)
        return HStack(alignment: .top, spacing: 10) {
            legIcon(leg.result)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(leg.label).font(.system(size: 15, weight: .heavy))
                    Spacer()
                    Text(Odds.format(leg.selection.price))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 6) {
                    Text(leg.selection.marketLabel)
                    Text("·")
                    Text(leg.game.league.title)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textMuted)

                if let finalScore = leg.finalScore {
                    Text(finalScore).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                } else if let game, game.state == .live {
                    HStack(spacing: 6) {
                        LiveBadge()
                        Text("\(Settlement.scoreLine(game)) · \(game.statusDetail)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                } else {
                    Text("\(leg.game.longMatchup) · \(leg.game.start.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func legIcon(_ result: LegResult) -> some View {
        let (icon, color): (String, Color) = switch result {
        case .pending: ("circle", Theme.textMuted)
        case .won: ("checkmark.circle.fill", Theme.win)
        case .lost: ("xmark.circle.fill", Theme.loss)
        case .push, .void: ("minus.circle.fill", Theme.textSecondary)
        }
        return Image(systemName: icon)
            .font(.system(size: 18))
            .foregroundStyle(color)
            .accessibilityLabel(result.rawValue)
    }

    private var footnote: String {
        let placed = "Placed \(bet.placedAt.formatted(date: .abbreviated, time: .shortened))"
        guard !bet.isFriendBet else { return placed }
        switch bet.status {
        case .open: return "\(placed) · result counts toward the next day's screen time"
        case .won, .lost:
            return "\(placed) · \(bet.netMinutes.signedMinutes) applied to screen time the day after"
        case .push, .void: return "\(placed) · stake returned"
        }
    }
}
