import Foundation

/// A simulated basketball league so there's always something to bet on — even on days without real games.
///
/// Every 10 minutes a new slate of 3 games tips off (staggered 2 minutes apart). Each game lasts 8 real minutes
/// (four 2-minute quarters). Scores are a pure function of the game ID and the elapsed time, so nothing needs to
/// be stored and every launch sees the same results.
nonisolated enum SimLeague {
    static let slotLength: TimeInterval = 600
    static let gamesPerSlot = 3
    static let stagger: TimeInterval = 120
    static let duration: TimeInterval = 480
    static let stepLength: TimeInterval = 5
    static var steps: Int { Int(duration / stepLength) }

    static let teams: [Team] = [
        team("NCV", "Volts", "Neon City Volts", "00B8D4"),
        team("HBK", "Kraken", "Harbor Kraken", "1E5EB8"),
        team("DSC", "Scorpions", "Desert Scorpions", "E09A00"),
        team("SMY", "Yetis", "Summit Yetis", "7E8CC7"),
        team("BYG", "Gators", "Bayou Gators", "2E7D32"),
        team("MTC", "Comets", "Metro Comets", "D93A3A"),
        team("PRS", "Storm", "Prairie Storm", "8E3FB5"),
        team("IBA", "Anchors", "Iron Bay Anchors", "4F6572"),
    ]

    /// Games worth showing on the board right now: recent finals, live games and the next few slates.
    static func games(now: Date = .now) -> [Game] {
        let slot = Int(now.timeIntervalSince1970 / slotLength)
        return (slot - 1...slot + 2).flatMap { s in
            (0..<gamesPerSlot).compactMap { i in
                let game = makeGame(slot: s, index: i, now: now)
                if game.state == .final, now.timeIntervalSince(game.start) > duration + 300 { return nil }
                return game
            }
        }
    }

    /// Recreates any sim game from its event ID ("<slot>-<index>"), used for settling bets.
    static func game(eventID: String, now: Date = .now) -> Game? {
        let parts = eventID.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return makeGame(slot: parts[0], index: parts[1], now: now)
    }

    private static func makeGame(slot: Int, index: Int, now: Date) -> Game {
        let eventID = "\(slot)-\(index)"
        let gameID = "\(League.sim.rawValue)-\(eventID)"
        let start = Date(timeIntervalSince1970: Double(slot) * slotLength + Double(index) * stagger)

        // Pair teams off from a per-slot shuffle.
        var shuffleRNG = SplitMix64(seed: Seeded.hash("slot-\(slot)"))
        let order = teams.indices.shuffled(using: &shuffleRNG)
        let home = teams[order[index * 2]]
        let away = teams[order[index * 2 + 1]]

        var game = Game(
            eventID: eventID, league: .sim, start: start, state: .scheduled,
            home: home, away: away, homeScore: 0, awayScore: 0,
            period: 0, clock: League.sim.periodSeconds, statusDetail: ""
        )

        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= 0 else { return game }

        if Seeded.hash("ppd-\(gameID)") % 25 == 0 {
            game.state = .postponed
            game.statusDetail = "Postponed"
            return game
        }

        let finished = elapsed >= duration
        let stepsPlayed = finished ? steps : Int(elapsed / stepLength)
        let (h, a, overtime) = score(gameID: gameID, stepsPlayed: stepsPlayed, finished: finished)
        game.homeScore = h
        game.awayScore = a

        if finished {
            game.state = .final
            game.period = 4
            game.clock = 0
            game.statusDetail = overtime ? "Final/OT" : "Final"
        } else {
            let quarterLength = duration / 4
            let quarter = min(Int(elapsed / quarterLength), 3)
            let scale = League.sim.periodSeconds / quarterLength
            let clock = (quarterLength - elapsed.truncatingRemainder(dividingBy: quarterLength)) * scale
            game.state = .live
            game.period = quarter + 1
            game.clock = clock
            game.statusDetail = "Q\(quarter + 1) \(Int(clock) / 60):\(String(format: "%02d", Int(clock) % 60))"
        }
        return game
    }

    /// Replays the seeded scoring sequence. Team scoring rates are tied to the same expected margin and total
    /// the odds engine uses, so the posted odds are fair.
    private static func score(gameID: String, stepsPlayed: Int, finished: Bool) -> (Int, Int, Bool) {
        let league = League.sim
        let mu = OddsEngine.seedStrength(gameID: gameID) * league.marginSigma + league.homeEdge
        let total = league.baseTotal * (1 + 0.06 * Seeded.unit("total-\(gameID)"))
        let perTeamBase = 1.19 * Double(steps)
        let homeRate = (total / 2 + mu / 2) / perTeamBase
        let awayRate = (total / 2 - mu / 2) / perTeamBase

        var rng = SplitMix64(seed: Seeded.hash("score-\(gameID)"))
        var home = 0, away = 0
        func points(_ rate: Double) -> Int {
            guard Double.random(in: 0..<1, using: &rng) < 0.55 * rate else { return 0 }
            let r = Double.random(in: 0..<0.55, using: &rng)
            return r < 0.03 ? 1 : r < 0.43 ? 2 : 3
        }
        for _ in 0..<stepsPlayed {
            home += points(homeRate)
            away += points(awayRate)
        }
        var overtime = false
        if finished && home == away {
            overtime = true
            if Bool.random(using: &rng) { home += 2 } else { away += 2 }
        }
        return (home, away, overtime)
    }

    private static func team(_ abbr: String, _ name: String, _ full: String, _ color: String) -> Team {
        Team(id: "sim-\(abbr)", abbreviation: abbr, name: name, fullName: full, colorHex: color, altColorHex: nil, logoURL: nil, record: nil)
    }
}
