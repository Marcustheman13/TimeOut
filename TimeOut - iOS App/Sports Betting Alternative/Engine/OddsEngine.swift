import Foundation

/// Generates fair odds (no house edge) for any game from a simple normal model of the final margin and total.
///
/// Before kickoff the expected margin comes from team records, home advantage and a stable per-game seed.
/// Once a game is live the model blends the current score with the expected margin over the time remaining,
/// so prices move with every score update from the feed.
nonisolated enum OddsEngine {
    /// Markets close in the final ~1.5% of a game so nobody can bet on a result that's already decided.
    static let suspendBelowRemaining = 0.015

    static func odds(for game: Game, now: Date = .now) -> GameOdds {
        let league = game.league
        let rem = game.remainingFraction
        let suspended = !game.isBettable || (game.state == .live && rem < suspendBelowRemaining)

        let mu0 = expectedMargin(for: game, now: now)
        let minSD = league.isDiscreteScoring ? 0.35 : 0.8
        let mu: Double
        let sd: Double
        if game.state == .live {
            mu = Double(game.margin) + mu0 * rem
            sd = max(league.marginSigma * pow(rem, 0.4), minSD)
        } else {
            mu = mu0
            sd = league.marginSigma
        }

        // Moneyline
        var moneyline: [Selection] = []
        if league.allowsDraw {
            let pHome = 1 - Stats.phi((0.5 - mu) / sd)
            let pAway = Stats.phi((-0.5 - mu) / sd)
            let pDraw = max(1 - pHome - pAway, 0.02)
            moneyline = [
                sel(game, .moneyline, .away, nil, pAway),
                sel(game, .moneyline, .draw, nil, pDraw),
                sel(game, .moneyline, .home, nil, pHome),
            ]
        } else {
            let pHome = Stats.phi(mu / sd)
            moneyline = [
                sel(game, .moneyline, .away, nil, 1 - pHome),
                sel(game, .moneyline, .home, nil, pHome),
            ]
        }

        // Spread / run line / puck line
        var spread: [Selection] = []
        if league.hasSpread {
            let homeLine = league.fixedSpread ? (mu >= 0 ? -1.5 : 1.5) : -Stats.hook(mu)
            let pHomeCovers = 1 - Stats.phi((-homeLine - mu) / sd)
            spread = [
                sel(game, .spread, .away, -homeLine, 1 - pHomeCovers),
                sel(game, .spread, .home, homeLine, pHomeCovers),
            ]
        }

        // Total
        let baseTotal = league.baseTotal * (1 + 0.06 * Seeded.unit("total-\(game.id)"))
        let projected: Double
        let sdT: Double
        if game.state == .live {
            projected = Double(game.totalScore) + baseTotal * rem
            sdT = max(league.totalSigma * pow(rem, 0.4), minSD)
        } else {
            projected = baseTotal
            sdT = league.totalSigma
        }
        let totalLine = Stats.hook(projected)
        let pOver = 1 - Stats.phi((totalLine - projected) / sdT)
        let total = [
            sel(game, .total, .over, totalLine, pOver),
            sel(game, .total, .under, totalLine, 1 - pOver),
        ]

        return GameOdds(moneyline: moneyline, spread: spread, total: total, suspended: suspended)
    }

    /// Expected final margin (home minus away) before the game starts.
    static func expectedMargin(for game: Game, now: Date = .now) -> Double {
        let league = game.league
        let noise = seedStrength(gameID: game.id)
        var strength = 0.0
        if let home = winPct(game.home.record), let away = winPct(game.away.record) {
            let weight = min(Double(min(home.games, away.games)) / 10, 1)
            strength = (home.pct - away.pct) * 0.9 * weight
        }
        // Small drift every 10 minutes before kickoff so pre-game lines feel alive.
        var drift = 0.0
        if game.state == .scheduled {
            let tick = Int(now.timeIntervalSince1970 / 600)
            drift = 0.04 * Seeded.unit("drift-\(game.id)-\(tick)")
        }
        return (noise + strength + drift) * league.marginSigma + league.homeEdge
    }

    /// Stable per-game strength offset, in units of the league's margin sigma.
    static func seedStrength(gameID: String) -> Double {
        0.45 * Seeded.unit("margin-\(gameID)")
    }

    private static func winPct(_ record: String?) -> (pct: Double, games: Int)? {
        guard let record else { return nil }
        let parts = record.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        let games = parts.reduce(0, +)
        guard games > 0 else { return nil }
        let ties = parts.count > 2 ? Double(parts[2]) * 0.5 : 0
        return ((Double(parts[0]) + ties) / Double(games), games)
    }

    private static func sel(_ game: Game, _ market: MarketType, _ side: Side, _ line: Double?, _ p: Double) -> Selection {
        Selection(gameID: game.id, market: market, side: side, line: line, price: Odds.american(fromProbability: p))
    }
}
