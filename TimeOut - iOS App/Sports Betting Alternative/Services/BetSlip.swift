import Foundation
import Observation

/// The in-progress bet. Tracks the odds the user saw and flags any change before they confirm (PRD: re-confirm on odds change).
@Observable
final class BetSlip {
    enum Mode: String, CaseIterable {
        case screenTime = "Screen Time"
        case friend = "Friend Bet"
    }

    struct Leg: Identifiable, Hashable {
        /// Odds the user has accepted.
        var selection: Selection
        var game: GameSnapshot
        /// Latest odds from the feed, if they differ from what was accepted.
        var latest: Selection?
        var closed = false

        var id: String { selection.id }
        var hasChanged: Bool { latest.map { !$0.hasSameTerms(as: selection) } ?? false }
    }

    private(set) var legs: [Leg] = []
    var stake: Int = 5
    var mode: Mode = .screenTime
    var friendStake = ""
    var isPresented = false
    var useBoost = false
    var useInsurance = false
    var notice: String?

    var isEmpty: Bool { legs.isEmpty }
    var hasOddsChanges: Bool { legs.contains(where: \.hasChanged) }
    var hasClosedLegs: Bool { legs.contains(where: \.closed) }
    var decimalOdds: Double { legs.reduce(1.0) { $0 * $1.selection.decimalOdds } }
    var americanOdds: Int { Odds.american(fromDecimal: decimalOdds) }
    var potentialPayout: Int { payout(multiplier: 1) }

    /// Stake plus winnings, with perks applied to the winnings.
    func payout(multiplier: Double) -> Int {
        stake + Int((Double(stake) * (decimalOdds - 1) * multiplier).rounded())
    }

    func contains(_ selectionID: String) -> Bool {
        legs.contains { $0.id == selectionID }
    }

    /// Adds a pick, removes it if it's already on the slip, or swaps it for another pick from the same game.
    func toggle(_ selection: Selection, in game: Game) {
        notice = nil
        if let index = legs.firstIndex(where: { $0.id == selection.id }) {
            legs.remove(at: index)
            if legs.isEmpty { isPresented = false }
            return
        }
        let leg = Leg(selection: selection, game: GameSnapshot(game))
        if let index = legs.firstIndex(where: { $0.game.gameID == game.id }) {
            legs[index] = leg
        } else if legs.count >= BetBook.maxLegs {
            notice = BetError.tooManyLegs.errorDescription
            isPresented = true
            return
        } else {
            legs.append(leg)
        }
        isPresented = true
    }

    func remove(_ leg: Leg) {
        legs.removeAll { $0.id == leg.id }
        if legs.isEmpty { isPresented = false }
    }

    func clear() {
        legs = []
        friendStake = ""
        notice = nil
        useBoost = false
        useInsurance = false
        mode = .screenTime
    }

    /// Compares every leg with the latest board and flags moved or closed markets.
    func sync(with feed: GameFeed) {
        for index in legs.indices {
            let gameID = legs[index].game.gameID
            guard let odds = feed.odds[gameID], let current = odds.selection(id: legs[index].id) else {
                legs[index].closed = feed.hasLoaded && feed.game(id: gameID) == nil ? true : legs[index].closed
                continue
            }
            legs[index].closed = odds.suspended
            legs[index].latest = current.hasSameTerms(as: legs[index].selection) ? nil : current
        }
    }

    /// The user confirmed the new prices.
    func acceptChanges() {
        for index in legs.indices {
            if let latest = legs[index].latest {
                legs[index].selection = latest
                legs[index].latest = nil
            }
        }
        notice = nil
    }

    func betLegs() -> [BetLeg] {
        legs.map { BetLeg(selection: $0.selection, game: $0.game) }
    }
}
