import Foundation

nonisolated enum Settlement {
    /// Grades one leg against the latest state of its game. Returns `.pending` while the game is unfinished.
    static func grade(_ selection: Selection, in game: Game) -> LegResult {
        if game.state.isVoid { return .void }
        guard game.state == .final else { return .pending }

        let margin = game.margin
        switch selection.market {
        case .moneyline:
            switch selection.side {
            case .draw: return margin == 0 ? .won : .lost
            case .home, .away:
                let mine = selection.side == .home ? margin : -margin
                if mine > 0 { return .won }
                if mine < 0 { return .lost }
                return game.league.allowsDraw ? .lost : .push
            case .over, .under: return .void
            }
        case .spread:
            let mine = Double(selection.side == .home ? margin : -margin) + (selection.line ?? 0)
            return mine > 0 ? .won : mine < 0 ? .lost : .push
        case .total:
            let diff = Double(game.totalScore) - (selection.line ?? 0)
            if diff == 0 { return .push }
            let overWins = diff > 0
            return (selection.side == .over) == overWins ? .won : .lost
        }
    }

    /// Combines leg results into a bet outcome. A parlay loses as soon as any leg loses; pushed or voided legs drop out.
    static func outcome(for bet: Bet) -> (status: BetStatus, payout: Int) {
        let results = bet.legs.map(\.result)
        if results.contains(.lost) { return (.lost, 0) }
        if results.contains(.pending) { return (.open, 0) }
        if results.allSatisfy({ $0 == .void }) { return (.void, bet.stake) }

        let winners = bet.legs.filter { $0.result == .won }
        if winners.isEmpty { return (.push, bet.stake) }
        let odds = winners.reduce(1.0) { $0 * $1.selection.decimalOdds }
        return (.won, Int((Double(bet.stake) * odds).rounded()))
    }

    static func scoreLine(_ game: Game) -> String {
        "\(game.away.abbreviation) \(game.awayScore) – \(game.home.abbreviation) \(game.homeScore)"
    }
}
