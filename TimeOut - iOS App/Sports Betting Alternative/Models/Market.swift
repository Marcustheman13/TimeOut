import Foundation

nonisolated enum MarketType: String, Codable, Sendable {
    case moneyline, spread, total
}

nonisolated enum Side: String, Codable, Sendable {
    case home, away, draw, over, under
}

/// One clickable price on the board.
nonisolated struct Selection: Codable, Hashable, Identifiable, Sendable {
    var gameID: String
    var market: MarketType
    var side: Side
    /// Spread for the chosen side, or the total. `nil` for moneylines.
    var line: Double?
    /// American odds, e.g. -135 or +120.
    var price: Int

    /// Identity ignores line and price so a selection can be tracked while its odds move.
    var id: String { "\(gameID)|\(market.rawValue)|\(side.rawValue)" }

    var decimalOdds: Double { Odds.decimal(fromAmerican: price) }

    func hasSameTerms(as other: Selection) -> Bool {
        price == other.price && line == other.line
    }
}

/// All markets for a single game at a moment in time.
nonisolated struct GameOdds: Hashable, Sendable {
    var moneyline: [Selection]   // away, (draw), home
    var spread: [Selection]      // away, home — empty for soccer
    var total: [Selection]       // over, under
    var suspended: Bool

    var all: [Selection] { moneyline + spread + total }

    func selection(id: String) -> Selection? {
        all.first { $0.id == id }
    }
}

nonisolated enum Odds {
    static func decimal(fromAmerican price: Int) -> Double {
        price > 0 ? 1 + Double(price) / 100 : 1 + 100 / Double(abs(price))
    }

    static func american(fromDecimal decimal: Double) -> Int {
        guard decimal > 1 else { return -10000 }
        return decimal >= 2 ? Int(((decimal - 1) * 100).rounded()) : Int((-100 / (decimal - 1)).rounded())
    }

    /// Fair (no house edge) American price for a win probability, rounded to sportsbook-looking steps.
    static func american(fromProbability rawP: Double) -> Int {
        // Capped at roughly ±2500, where real books stop quoting meaningful prices.
        let p = min(max(rawP, 0.038), 0.962)
        let raw = p >= 0.5 ? -100 * p / (1 - p) : 100 * (1 - p) / p
        let step = abs(raw) >= 300 ? 25.0 : 5.0
        var rounded = Int((raw / step).rounded() * step)
        if rounded > -100 && rounded < 100 { rounded = rounded < 0 ? -100 : 100 }
        return rounded
    }

    static func format(_ price: Int) -> String {
        price > 0 ? "+\(price)" : "\(price)"
    }

    static func formatLine(_ line: Double, signed: Bool = true) -> String {
        let body = line == line.rounded() ? String(Int(line)) : String(format: "%.1f", line)
        guard signed else { return body }
        return line > 0 ? "+\(body)" : body
    }
}

nonisolated extension Selection {
    /// e.g. "GB -3.5", "Over 44.5", "ATL ML", "Draw".
    func label(for snapshot: GameSnapshot) -> String {
        let team: Team? = side == .home ? snapshot.home : side == .away ? snapshot.away : nil
        switch market {
        case .moneyline:
            return team.map { "\($0.name) ML" } ?? "Draw"
        case .spread:
            return "\(team?.name ?? "") \(Odds.formatLine(line ?? 0))"
        case .total:
            return "\(side == .over ? "Over" : "Under") \(Odds.formatLine(line ?? 0, signed: false))"
        }
    }

    var marketLabel: String {
        switch market {
        case .moneyline: "Moneyline"
        case .spread: "Spread"
        case .total: "Total"
        }
    }
}
