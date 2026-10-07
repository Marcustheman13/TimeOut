import Foundation
import Observation

/// Live board of games and odds. Refreshed by `AppModel` on a fixed interval (PRD: at least every 30 seconds).
@Observable
final class GameFeed {
    static let refreshInterval: Duration = .seconds(15)

    private(set) var games: [Game] = []
    private(set) var odds: [String: GameOdds] = [:]
    /// Selections whose price moved on the last refresh: +1 = longer (better payout), −1 = shorter.
    private(set) var movement: [String: Int] = [:]
    private(set) var lastUpdated: Date?
    private(set) var hasLoaded = false
    private(set) var offlineLeagues: Set<League> = []

    private var byID: [String: Game] = [:]

    func game(id: String) -> Game? { byID[id] }

    func games(in league: League) -> [Game] { games.filter { $0.league == league } }

    var liveGames: [Game] { games.filter { $0.state == .live } }

    /// Leagues that have something on the board, in display order.
    var activeLeagues: [League] {
        League.allCases.filter { league in games.contains { $0.league == league } }
    }

    /// Loads the followed leagues. Leagues you don't follow aren't fetched at all.
    func refresh(now: Date = .now, leagues followed: Set<League> = Set(League.allCases)) async {
        let realLeagues = League.allCases.filter { $0.espnPath != nil && followed.contains($0) }
        var fetched: [League: [Game]] = [:]
        var failed: Set<League> = []

        await withTaskGroup(of: (League, [Game]?).self) { group in
            for league in realLeagues {
                group.addTask {
                    (league, try? await ESPNClient.scoreboard(for: league))
                }
            }
            for await (league, result) in group {
                if let result { fetched[league] = result } else { failed.insert(league) }
            }
        }

        // Keep the last good data for any league whose request failed.
        var all: [Game] = []
        for league in realLeagues {
            all += fetched[league] ?? games.filter { $0.league == league }
        }
        if followed.contains(.sim) {
            all += SimLeague.games(now: now)
        }

        // Hide stale finals and far-future games to keep the board focused.
        let horizon = now.addingTimeInterval(8 * 24 * 3600)
        all = all.filter { game in
            switch game.state {
            case .live: true
            case .scheduled: game.start < horizon
            case .final, .postponed, .canceled: now.timeIntervalSince(game.start) < 18 * 3600
            }
        }

        all.sort { lhs, rhs in
            let rank: (GameState) -> Int = { [.live: 0, .scheduled: 1, .final: 2, .postponed: 3, .canceled: 3][$0] ?? 4 }
            if rank(lhs.state) != rank(rhs.state) { return rank(lhs.state) < rank(rhs.state) }
            return lhs.start < rhs.start
        }

        games = all
        byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newOdds = Dictionary(all.map { ($0.id, OddsEngine.odds(for: $0, now: now)) }, uniquingKeysWith: { a, _ in a })
        var moves: [String: Int] = [:]
        for (gameID, gameOdds) in newOdds {
            guard let old = odds[gameID] else { continue }
            for selection in gameOdds.all {
                guard let previous = old.selection(id: selection.id), previous.line == selection.line,
                      previous.price != selection.price else { continue }
                moves[selection.id] = selection.decimalOdds > previous.decimalOdds ? 1 : -1
            }
        }
        movement = moves
        odds = newOdds
        offlineLeagues = failed
        lastUpdated = now
        hasLoaded = true
    }

    /// Fetches games that open bets depend on but that are no longer on the board.
    func lookup(_ snapshots: [GameSnapshot], now: Date = .now) async -> [Game] {
        await withTaskGroup(of: Game?.self) { group in
            for snapshot in snapshots {
                group.addTask {
                    if snapshot.league == .sim {
                        return SimLeague.game(eventID: snapshot.eventID, now: now)
                    }
                    return try? await ESPNClient.game(eventID: snapshot.eventID, league: snapshot.league)
                }
            }
            var found: [Game] = []
            for await game in group { if let game { found.append(game) } }
            return found
        }
    }
}
