import SwiftUI

/// A game on the board: teams, live score and a grid of odds buttons — one tap adds a pick to the slip.
struct GameCard: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let odds = model.feed.odds[game.id]
        VStack(alignment: .leading, spacing: 10) {
            statusRow

            if game.isBettable, let odds {
                marketGrid(odds)
            } else {
                resultRows
            }
        }
        .card(padding: 14)
    }

    // MARK: Status

    private var statusRow: some View {
        HStack(spacing: 8) {
            switch game.state {
            case .live:
                LiveBadge()
                Text(game.statusDetail)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            case .scheduled:
                Text(startText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            case .final:
                Text(game.statusDetail.isEmpty ? "Final" : game.statusDetail)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            case .postponed, .canceled:
                Label("\(game.state.rawValue.capitalized) · bets voided", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.warning)
            }
            Spacer()
            if model.feed.odds[game.id]?.suspended == true && game.state == .live {
                Label("Suspended", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            Text(game.league.title)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var startText: String {
        let calendar = Calendar.current
        let time = game.start.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(game.start) { return "Today · \(time)" }
        if calendar.isDateInTomorrow(game.start) { return "Tomorrow · \(time)" }
        return game.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " · \(time)"
    }

    // MARK: Markets

    private func marketGrid(_ odds: GameOdds) -> some View {
        let columns: [(String, [Selection])] = [
            (game.league.spreadLabel, odds.spread),
            ("Total", odds.total),
            ("Money", odds.moneyline.filter { $0.side != .draw }),
        ].filter { !$0.1.isEmpty }

        return VStack(spacing: 6) {
            // Column headers
            HStack(spacing: 6) {
                Spacer()
                ForEach(columns, id: \.0) { column in
                    Text(column.0)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: OddsButton.width)
                }
            }
            // Away row, then home row. Totals put Over on the away row and Under on the home row, like every book.
            ForEach(0..<2, id: \.self) { row in
                let team = row == 0 ? game.away : game.home
                let score = row == 0 ? game.awayScore : game.homeScore
                HStack(spacing: 6) {
                    teamLabel(team, score: score, leading: row == 0 ? game.awayScore > game.homeScore : game.homeScore > game.awayScore)
                    ForEach(columns, id: \.0) { column in
                        OddsButton(selection: column.1[row], game: game, suspended: odds.suspended)
                    }
                }
            }
            if let draw = odds.moneyline.first(where: { $0.side == .draw }) {
                HStack(spacing: 6) {
                    Text("Draw")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    OddsButton(selection: draw, game: game, suspended: odds.suspended)
                }
            }
        }
    }

    private func teamLabel(_ team: Team, score: Int, leading: Bool) -> some View {
        HStack(spacing: 8) {
            TeamBadge(team: team, size: 24)
            VStack(alignment: .leading, spacing: 0) {
                // Live rows also carry the score, so fall back to the abbreviation to keep things readable.
                Text(game.state == .live ? team.abbreviation : team.name)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let record = team.record, game.state == .scheduled {
                    Text(record)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            Spacer(minLength: 2)
            if game.state == .live {
                Text("\(score)")
                    .font(.display(score >= 100 ? 19 : 22, weight: .black))
                    .foregroundStyle(leading ? .white : Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
                    .padding(.trailing, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Finished games

    private var resultRows: some View {
        VStack(spacing: 8) {
            resultRow(game.away, score: game.awayScore, won: game.state == .final && game.awayScore > game.homeScore)
            resultRow(game.home, score: game.homeScore, won: game.state == .final && game.homeScore > game.awayScore)
        }
    }

    private func resultRow(_ team: Team, score: Int, won: Bool) -> some View {
        HStack(spacing: 8) {
            TeamBadge(team: team, size: 24)
            Text(team.name)
                .font(.system(size: 15, weight: won ? .heavy : .semibold))
                .foregroundStyle(won ? .white : Theme.textSecondary)
            Spacer()
            if game.state == .final {
                Text("\(score)")
                    .font(.display(22, weight: .black))
                    .foregroundStyle(won ? .white : Theme.textSecondary)
            }
        }
    }
}

struct OddsButton: View {
    static let width: CGFloat = 72

    @Environment(AppModel.self) private var model
    let selection: Selection
    let game: Game
    var suspended = false

    var body: some View {
        let selected = model.slip.contains(selection.id)
        let move = model.feed.movement[selection.id]
        Button {
            model.slip.toggle(selection, in: game)
        } label: {
            VStack(spacing: 1) {
                if suspended {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textMuted)
                } else {
                    if let lineText {
                        Text(lineText)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(selected ? .black : .white)
                    }
                    HStack(spacing: 2) {
                        if let move {
                            Image(systemName: move > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(selected ? .black : (move > 0 ? Theme.win : Theme.loss))
                        }
                        Text(Odds.format(selection.price))
                            .font(.system(size: lineText == nil ? 15 : 13, weight: .heavy))
                            .foregroundStyle(selected ? .black : Theme.accent)
                    }
                }
            }
            .frame(width: Self.width, height: 46)
            .background(selected ? Theme.accent : Theme.raised, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? .clear : Theme.stroke, lineWidth: 1))
            .contentTransition(.numericText())
            .animation(.snappy, value: selection.price)
        }
        .buttonStyle(.plain)
        .disabled(suspended)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var lineText: String? {
        switch selection.market {
        case .moneyline: nil
        case .spread: Odds.formatLine(selection.line ?? 0)
        case .total: "\(selection.side == .over ? "O" : "U") \(Odds.formatLine(selection.line ?? 0, signed: false))"
        }
    }

    private var accessibilityText: String {
        "\(selection.label(for: GameSnapshot(game))), \(Odds.format(selection.price))\(suspended ? ", suspended" : "")"
    }
}
