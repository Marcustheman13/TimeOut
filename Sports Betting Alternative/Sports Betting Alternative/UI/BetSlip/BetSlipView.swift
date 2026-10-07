import SwiftUI

struct BetSlipView: View {
    @Environment(AppModel.self) private var model
    @State private var error: BetError?
    @FocusState private var friendFieldFocused: Bool

    private let quickStakes = [5, 10, 15, 30]
    private let friendIdeas = ["Loser does the dishes", "Loser buys coffee", "Loser folds the laundry", "Loser posts a hype video for the winner"]

    var body: some View {
        @Bindable var slip = model.slip
        let book = model.book

        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Bet type", selection: $slip.mode) {
                        ForEach(BetSlip.Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    if let notice = slip.notice {
                        banner(notice, icon: "info.circle.fill", color: Theme.warning)
                    }
                    if slip.hasOddsChanges {
                        banner("Odds changed since you added \(slip.legs.count > 1 ? "these picks" : "this pick"). Review the new prices below.", icon: "exclamationmark.triangle.fill", color: Theme.warning)
                    }

                    VStack(spacing: 8) {
                        ForEach(slip.legs) { leg in
                            LegRow(leg: leg) {
                                withAnimation { slip.remove(leg) }
                            }
                        }
                    }

                    if slip.legs.count > 1 {
                        HStack {
                            Text("\(slip.legs.count)-Leg Parlay")
                                .font(.system(size: 15, weight: .heavy))
                            Spacer()
                            Text(Odds.format(slip.americanOdds))
                                .font(.display(20))
                                .foregroundStyle(Theme.accent)
                        }
                        .card(padding: 12)
                    }

                    if slip.mode == .screenTime {
                        stakePicker
                    } else {
                        friendStakeEditor
                    }

                    if let error {
                        banner(error.errorDescription ?? "", icon: "xmark.octagon.fill", color: Theme.loss)
                            .transition(.opacity)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(Theme.background)
        .onChange(of: slip.stake) { error = nil }
        .onChange(of: slip.mode) { error = nil }
        .onChange(of: book.balance) { error = nil }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Bet Slip")
                .font(.system(size: 20, weight: .heavy))
            Text("\(model.slip.legs.count)/\(BetBook.maxLegs)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textMuted)
            Spacer()
            Button("Clear") {
                model.slip.clear()
                model.slip.isPresented = false
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: Stake

    private var stakePicker: some View {
        @Bindable var slip = model.slip
        let book = model.book
        let tooMuch = slip.stake > book.balance

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stake")
                    .font(.system(size: 15, weight: .heavy))
                Spacer()
                Text("Balance: \(book.balance) min")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tooMuch ? Theme.loss : Theme.textSecondary)
            }

            HStack(spacing: 12) {
                stepButton("minus") { slip.stake = max(slip.stake - 1, 1) }
                VStack(spacing: 0) {
                    Text("\(slip.stake)")
                        .font(.display(40, weight: .black))
                        .foregroundStyle(tooMuch ? Theme.loss : .white)
                        .contentTransition(.numericText())
                    Text("MINUTES")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity)
                stepButton("plus") { slip.stake += 1 }
            }

            HStack(spacing: 8) {
                ForEach(quickStakes, id: \.self) { value in
                    quickChip("\(value)", selected: slip.stake == value) { slip.stake = value }
                }
                quickChip("Max", selected: slip.stake == book.balance && book.balance > 0) { slip.stake = max(book.balance, 1) }
            }

            if tooMuch {
                Label("Not enough screentime. You have \(book.balance) min left.", systemImage: "hourglass.bottomhalf.filled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.loss)
            }

            perksSection

            let payout = slip.payout(multiplier: model.slipPerks.winningsMultiplier)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TO WIN").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.textMuted)
                    Text("\(payout - slip.stake) min").font(.display(20)).foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TOTAL PAYOUT").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.textMuted)
                    Text("\(payout) min").font(.display(20)).foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            }
            .padding(.top, 4)

            Text("Wins and losses change tomorrow's phone screen time limit.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
        }
        .card()
    }

    // MARK: Perks

    /// Streak multiplier, odds boost and parlay insurance, when the user has them.
    @ViewBuilder
    private var perksSection: some View {
        @Bindable var slip = model.slip
        let book = model.book
        let tier = model.tier
        let boostsLeft = book.boostsLeft(for: tier)
        let insuranceLeft = book.insuranceLeft(for: tier)

        VStack(spacing: 8) {
            if book.streakMultiplier > 1 {
                perkRow(icon: "flame.fill", color: Theme.warning,
                        title: "\(book.streakDays)-day streak",
                        detail: "Winnings \(Rewards.formatMultiplier(book.streakMultiplier)), applied automatically")
            }
            if boostsLeft > 0 {
                Toggle(isOn: $slip.useBoost) {
                    perkLabel(icon: "bolt.fill", color: Color(hex: "4FB3FF"), title: "Odds boost +\(Int(Rewards.boostPercent * 100))%",
                              detail: "\(boostsLeft) left today · \(tier.title) perk")
                }
                .tint(Color(hex: "4FB3FF"))
            } else if tier < .allStar {
                perkRow(icon: "lock.fill", color: Theme.textMuted, title: "Odds boosts",
                        detail: "Reach All-Star by locking more apps")
            }
            if slip.legs.count > 1 && insuranceLeft > 0 {
                Toggle(isOn: $slip.useInsurance) {
                    perkLabel(icon: "shield.lefthalf.filled", color: Color(hex: "C58CFF"), title: "Parlay insurance",
                              detail: "Miss by one leg, get your stake back · 1 a week")
                }
                .tint(Color(hex: "C58CFF"))
            }
        }
    }

    private func perkRow(icon: String, color: Color, title: String, detail: String) -> some View {
        perkLabel(icon: icon, color: color, title: title, detail: detail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func perkLabel(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 48, height: 48)
                .background(Theme.raised, in: .circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }

    private func quickChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .heavy))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(selected ? .black : .white)
                .background(selected ? Theme.accent : Theme.raised, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: Friend bet

    private var friendStakeEditor: some View {
        @Bindable var slip = model.slip
        return VStack(alignment: .leading, spacing: 10) {
            Text("What's on the line?")
                .font(.system(size: 15, weight: .heavy))
            Text("Bet a friend for something real instead of screen time. You'll get a card to send them.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            TextField("e.g. Loser does the dishes", text: $slip.friendStake, axis: .vertical)
                .lineLimit(2...3)
                .focused($friendFieldFocused)
                .padding(12)
                .background(Theme.raised, in: .rect(cornerRadius: 12))
                .onChange(of: slip.friendStake) { _, value in
                    if value.count > BetBook.friendStakeLimit {
                        slip.friendStake = String(value.prefix(BetBook.friendStakeLimit))
                    }
                }

            HStack {
                Spacer()
                Text("\(slip.friendStake.count)/\(BetBook.friendStakeLimit)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(slip.friendStake.count >= BetBook.friendStakeLimit ? Theme.warning : Theme.textMuted)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(friendIdeas, id: \.self) { idea in
                        Button(idea) { slip.friendStake = idea }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.raised, in: .capsule)
                            .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .card()
    }

    // MARK: Footer

    private var footer: some View {
        let slip = model.slip
        let book = model.book
        return VStack(spacing: 8) {
            if slip.hasOddsChanges {
                Button {
                    withAnimation { slip.acceptChanges() }
                    error = nil
                } label: {
                    footerLabel("Accept New Odds", color: Theme.warning)
                }
            } else if slip.mode == .screenTime && book.isLockedOut {
                VStack(spacing: 4) {
                    Text("Out of screentime · betting reopens in")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    MidnightCountdown(font: .display(24))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                Button {
                    friendFieldFocused = false
                    withAnimation { error = model.placeBet() }
                } label: {
                    footerLabel(placeTitle, color: Theme.accent)
                }
                .disabled(slip.isEmpty || slip.hasClosedLegs)
                .sensoryFeedback(.success, trigger: book.bets.count)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.surface)
    }

    private var placeTitle: String {
        let slip = model.slip
        if slip.hasClosedLegs { return "Market Closed" }
        if slip.mode == .friend { return "Create & Share Friend Bet" }
        return "Place Bet · \(slip.stake) min"
    }

    private func footerLabel(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(color, in: .rect(cornerRadius: 14))
    }

    private func banner(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}

private struct LegRow: View {
    let leg: BetSlip.Leg
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TeamBadge(team: pickedTeam, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(leg.selection.label(for: leg.game))
                    .font(.system(size: 16, weight: .heavy))
                Text("\(leg.selection.marketLabel) · \(leg.game.matchup)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                if leg.closed {
                    Text("Market closed. Remove this pick to continue.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.loss)
                } else if let latest = leg.latest, leg.hasChanged {
                    HStack(spacing: 6) {
                        Text("Now:")
                        Text(latest.label(for: leg.game))
                        Text(Odds.format(latest.price)).fontWeight(.heavy)
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(Odds.format(leg.selection.price))
                    .font(.display(18))
                    .foregroundStyle(leg.hasChanged ? Theme.textMuted : Theme.accent)
                    .strikethrough(leg.hasChanged)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove pick")
            }
        }
        .card(padding: 12)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(leg.hasChanged ? Theme.warning.opacity(0.6) : .clear, lineWidth: 1))
    }

    private var pickedTeam: Team {
        switch leg.selection.side {
        case .away: leg.game.away
        case .home: leg.game.home
        default: Team(id: "t", abbreviation: leg.selection.side == .over ? "O" : leg.selection.side == .under ? "U" : "X",
                      name: "", fullName: "", colorHex: "283141")
        }
    }
}
