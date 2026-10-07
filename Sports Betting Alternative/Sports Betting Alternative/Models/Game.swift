import Foundation

nonisolated struct Team: Codable, Hashable, Sendable {
    var id: String
    var abbreviation: String
    var name: String
    var fullName: String
    var colorHex: String
    var altColorHex: String?
    var logoURL: URL?
    var record: String?
}

nonisolated enum GameState: String, Codable, Sendable {
    case scheduled, live, final, postponed, canceled

    var isVoid: Bool { self == .postponed || self == .canceled }
}

nonisolated struct Game: Codable, Identifiable, Hashable, Sendable {
    /// Unique across leagues, e.g. "nfl-401872948".
    var id: String { "\(league.rawValue)-\(eventID)" }
    var eventID: String
    var league: League
    var start: Date
    var state: GameState
    var home: Team
    var away: Team
    var homeScore: Int
    var awayScore: Int
    var period: Int
    /// Seconds left in the period (for soccer, seconds elapsed in the match — that's how ESPN reports it).
    var clock: Double
    /// Short human-readable status, e.g. "5:00 - 3rd" or "Final".
    var statusDetail: String

    var isBettable: Bool { state == .scheduled || state == .live }
    var margin: Int { homeScore - awayScore }
    var totalScore: Int { homeScore + awayScore }

    /// Fraction of regulation still to play, 1 before kickoff and ~0 at the end.
    var remainingFraction: Double {
        switch state {
        case .scheduled, .postponed, .canceled: return 1
        case .final: return 0
        case .live: break
        }
        let floor = 0.01
        switch league.kind {
        case .baseball:
            // ESPN detail reads "Top 5th", "Mid 5th", "Bot 5th", "End 5th".
            let detail = statusDetail.lowercased()
            let halfDone: Double = detail.hasPrefix("top") ? 0 : detail.hasPrefix("end") ? 1 : 0.5
            let played = Double(max(period, 1) - 1) + halfDone
            return max((9 - played) / 9, floor)
        case .soccer:
            let total = league.periodSeconds * 2
            return max((total - clock) / total, floor)
        default:
            let total = league.periodSeconds * Double(league.periods)
            if period > league.periods {
                return max(clock / total, floor)
            }
            let remaining = Double(league.periods - period) * league.periodSeconds + clock
            return min(max(remaining / total, floor), 1)
        }
    }
}

/// The bits of a game a bet needs to remember, so bet history still reads well after the game leaves the feed.
nonisolated struct GameSnapshot: Codable, Hashable, Sendable {
    var gameID: String
    var eventID: String
    var league: League
    var start: Date
    var home: Team
    var away: Team

    init(_ game: Game) {
        gameID = game.id
        eventID = game.eventID
        league = game.league
        start = game.start
        home = game.home
        away = game.away
    }

    var matchup: String { "\(away.abbreviation) @ \(home.abbreviation)" }
    var longMatchup: String { "\(away.name) @ \(home.name)" }
}
