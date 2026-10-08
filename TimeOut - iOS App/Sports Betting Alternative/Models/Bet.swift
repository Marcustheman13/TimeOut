import Foundation

nonisolated enum LegResult: String, Codable, Sendable {
    case pending, won, lost, push, void
}

nonisolated enum BetStatus: String, Codable, Sendable {
    case open, won, lost, push, void

    var title: String {
        switch self {
        case .open: "Open"
        case .won: "Won"
        case .lost: "Lost"
        case .push: "Push"
        case .void: "Void"
        }
    }
}

nonisolated struct BetLeg: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var selection: Selection
    var game: GameSnapshot
    var result: LegResult = .pending
    /// Final score text once settled, e.g. "ATL 17 – GB 24".
    var finalScore: String?

    var label: String { selection.label(for: game) }
}

nonisolated struct Bet: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var placedAt: Date
    /// Local calendar day the bet was placed ("yyyy-MM-dd"). Results feed the *next* day's screen time.
    var dayKey: String
    /// Minutes staked. Zero for friend bets.
    var stake: Int
    var legs: [BetLeg]
    /// Combined decimal odds locked in at placement.
    var decimalOdds: Double
    var status: BetStatus = .open
    var settledAt: Date?
    /// Minutes returned on settlement (stake + winnings for a win, stake for a push/void).
    var payout: Int = 0
    /// Custom reward/punishment for a bet with a friend, used instead of screen time.
    var friendStake: String?
    // Perks (optional so bets saved before perks existed still decode).
    /// Winnings multiplier locked in at placement: clean streak × odds boost.
    var winningsMultiplier: Double?
    var boosted: Bool?
    var insured: Bool?
    /// Set when parlay insurance refunded this bet.
    var insurancePaid: Bool?

    var multiplier: Double { winningsMultiplier ?? 1 }
    var isBoosted: Bool { boosted ?? false }
    var isInsured: Bool { insured ?? false }

    var isFriendBet: Bool { friendStake != nil }
    var isParlay: Bool { legs.count > 1 }
    var americanOdds: Int { Odds.american(fromDecimal: decimalOdds) }

    var potentialPayout: Int { stake + Int((Double(stake) * (decimalOdds - 1) * multiplier).rounded()) }
    var potentialWinnings: Int { potentialPayout - stake }

    /// Net effect on screen time once settled.
    var netMinutes: Int {
        switch status {
        case .won: payout - stake
        case .lost: -stake
        case .open, .push, .void: 0
        }
    }

    var title: String {
        if isParlay { return "\(legs.count)-Leg Parlay" }
        return legs.first?.label ?? "Bet"
    }
}
