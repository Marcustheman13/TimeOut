import Foundation

nonisolated enum SportKind: String, Codable, Sendable {
    case football, basketball, baseball, hockey, soccer
}

/// Every league the feed knows about. `sim` is the app's own simulated league for days without sports.
nonisolated enum League: String, Codable, CaseIterable, Identifiable, Sendable {
    case nfl, ncaaf, nba, wnba, mlb, nhl, mls, epl, sim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nfl: "NFL"
        case .ncaaf: "NCAAF"
        case .nba: "NBA"
        case .wnba: "WNBA"
        case .mlb: "MLB"
        case .nhl: "NHL"
        case .mls: "MLS"
        case .epl: "EPL"
        case .sim: "Sim Hoops"
        }
    }

    /// Path segment for ESPN's public scoreboard API. `nil` for leagues generated on-device.
    var espnPath: String? {
        switch self {
        case .nfl: "football/nfl"
        case .ncaaf: "football/college-football"
        case .nba: "basketball/nba"
        case .wnba: "basketball/wnba"
        case .mlb: "baseball/mlb"
        case .nhl: "hockey/nhl"
        case .mls: "soccer/usa.1"
        case .epl: "soccer/eng.1"
        case .sim: nil
        }
    }

    var kind: SportKind {
        switch self {
        case .nfl, .ncaaf: .football
        case .nba, .wnba, .sim: .basketball
        case .mlb: .baseball
        case .nhl: .hockey
        case .mls, .epl: .soccer
        }
    }

    var symbol: String {
        switch self {
        case .sim: "cpu"
        default:
            switch kind {
            case .football: "football.fill"
            case .basketball: "basketball.fill"
            case .baseball: "baseball.fill"
            case .hockey: "hockey.puck.fill"
            case .soccer: "soccerball"
            }
        }
    }

    // MARK: Model parameters used by the odds engine

    /// Standard deviation of the final home-minus-away margin.
    var marginSigma: Double {
        switch self {
        case .nfl: 13.5
        case .ncaaf: 16
        case .nba: 12
        case .wnba: 11
        case .sim: 15.5
        case .mlb: 4.2
        case .nhl: 2.3
        case .mls, .epl: 1.6
        }
    }

    /// Typical combined score, used as the base for totals.
    var baseTotal: Double {
        switch self {
        case .nfl: 44
        case .ncaaf: 52
        case .nba: 224
        case .wnba: 162
        case .sim: 229
        case .mlb: 8.5
        case .nhl: 6
        case .mls: 2.9
        case .epl: 2.7
        }
    }

    /// Standard deviation of the combined score.
    var totalSigma: Double {
        switch self {
        case .nfl: 13
        case .ncaaf: 15
        case .nba: 18
        case .wnba: 15
        case .sim: 15.7
        case .mlb: 4.3
        case .nhl: 2.4
        case .mls, .epl: 1.6
        }
    }

    /// Home advantage in points/goals/runs.
    var homeEdge: Double {
        switch self {
        case .nfl: 1.5
        case .ncaaf: 2.5
        case .nba, .wnba: 2
        case .sim: 1.5
        case .mlb: 0.15
        case .nhl: 0.15
        case .mls, .epl: 0.3
        }
    }

    /// Soccer moneylines are three-way (home / draw / away).
    var allowsDraw: Bool { kind == .soccer }

    /// Low-scoring sports use a fixed ±1.5 run/puck line instead of a derived spread. Soccer has no spread.
    var hasSpread: Bool { kind != .soccer }
    var fixedSpread: Bool { kind == .baseball || kind == .hockey }

    var isDiscreteScoring: Bool { kind == .baseball || kind == .hockey || kind == .soccer }

    /// Regulation layout for converting period + clock into "fraction of game remaining".
    var periods: Int {
        switch kind {
        case .football, .basketball: 4
        case .hockey: 3
        case .soccer: 2
        case .baseball: 9
        }
    }

    var periodSeconds: Double {
        switch self {
        case .nfl, .ncaaf: 900
        case .nba, .sim: 720
        case .wnba: 600
        case .nhl: 1200
        case .mls, .epl: 2700
        case .mlb: 0
        }
    }

    var spreadLabel: String {
        switch kind {
        case .baseball: "Run Line"
        case .hockey: "Puck Line"
        default: "Spread"
        }
    }
}
