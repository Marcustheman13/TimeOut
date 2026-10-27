import Foundation
import Observation

/// The bet slip (Screen 3). A port of the web demo's slip.js state and actions.
@Observable
final class Slip {
    static let shared = Slip()

    var legs: [SlipLeg] = []
    /// Picks stack up only in parlay mode; otherwise a new pick replaces the old one.
    var parlayMode = false
    var stake: String?
    var boost = false
    var insure = false
    var error: String?
    var capped = false

    func has(_ id: String) -> Bool { legs.contains { $0.selId == id } }

    func clear() {
        legs = []; parlayMode = false; stake = nil; boost = false; insure = false; error = nil; capped = false
    }

    private static func refOf(_ sel: Selection) -> String { sel.gameId ?? sel.predId ?? sel.raceId ?? "" }

    private var ui: UIState { .shared }

    /// Tap on an odds button. Outside parlay mode the pick replaces whatever is on the slip and opens it;
    /// in parlay mode it's added, or swapped for a second pick on the same game.
    func toggle(_ selId: String) {
        if has(selId) {
            legs.removeAll { $0.selId == selId }
            afterChange()
            return
        }
        guard let cur = Feed.currentSelection(selId), let sel = cur.sel, cur.open else {
            ui.toast(.warn, "Betting is closed on this pick")
            return
        }
        let hasRace = legs.contains { $0.ref.hasPrefix("race-") }
        if parlayMode && (sel.kind == "race" || hasRace) {
            ui.toast(.warn, "Virtual races are single picks", "Place a virtual race bet on its own, outside a parlay.")
            return
        }
        let leg = SlipLeg(selId: sel.id, price: sel.price, line: sel.line, ref: Self.refOf(sel))
        if !parlayMode {
            legs = [leg]
            error = nil
            open()
            afterChange()
            return
        }
        if let same = legs.firstIndex(where: { $0.ref == leg.ref }) {
            legs[same] = leg
            ui.toast(.info, "Pick swapped", "A parlay can only have one pick per game.", ms: 2600)
        } else {
            if legs.count >= Rules.maxLegs {
                ui.toast(.warn, "Parlays are limited to \(Rules.maxLegs) picks", "Remove a pick to add another.")
                return
            }
            legs.append(leg)
        }
        error = nil
        afterChange()
    }

    func toggleParlayMode() {
        parlayMode.toggle()
        legs = []
        error = nil
        ui.closeSheet(.slip, silent: true) // not discard(): that would also switch parlay mode back off
        ui.closePage(.parlay, silent: true)
    }

    private func afterChange() {
        if legs.isEmpty {
            ui.closeSheet(.slip)
            ui.closePage(.parlay, silent: true)
        }
    }

    /// Closing the slip (X or tapping outside) throws the picks away, so nothing lingers on Home.
    func discard() {
        clear()
        ui.closePage(.parlay, silent: true)
    }

    func open() {
        if !ui.sheetOpen(.slip) { ui.openSheet(.slip) }
    }

    func remove(_ selId: String) {
        legs.removeAll { $0.selId == selId }
        afterChange()
    }

    struct LegState { var sel: Selection?; var closed: Bool; var changed: Bool }

    func legState(_ leg: SlipLeg) -> LegState {
        let cur = Feed.currentSelection(leg.selId)
        let closed = cur == nil || cur?.sel == nil || cur?.open != true
        let changed = !closed && (cur!.sel!.price != leg.price || cur!.sel!.line != leg.line)
        return LegState(sel: cur?.sel, closed: closed, changed: changed)
    }

    func status() -> (states: [LegState], closed: Bool, changed: Bool) {
        let states = legs.map(legState)
        return (states, states.contains { $0.closed }, states.contains { $0.changed })
    }

    var decimal: Double { legs.reduce(1.0) { $0 * OddsMath.decimal($1.price) } }

    struct Numbers { var wl: WalletView; var stake: Int?; var dec: Double; var american: Int; var mult: Double; var winnings: Int; var valid: Bool }

    func numbers() -> Numbers {
        let wl = Store.shared.wallet
        let stake = stake.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let dec = decimal
        var mult = wl.multiplier
        if boost && wl.boostsLeft > 0 { mult *= 1 + Rules.boostPercent }
        let s = stake ?? 0
        let winnings = jsRoundInt(Double(jsRoundInt(Double(s) * dec) - s) * mult)
        let valid = stake != nil && stake! >= 1 && stake! <= wl.balance && Net.shared.online
        return Numbers(wl: wl, stake: stake, dec: dec, american: OddsMath.fromDecimal(dec), mult: mult, winnings: winnings, valid: valid)
    }

    /// The stake shown when the slip opens: the last stake, capped to the balance.
    func prepareStake() {
        if stake == nil {
            let wl = Store.shared.wallet
            stake = String(max(1, min(Store.shared.data?.lastStake ?? 5, max(wl.balance, 1))))
        }
    }

    // MARK: Actions

    func addMore() {
        parlayMode = true
        ui.closeSheet(.slip, silent: true) // hide it without discarding the picks
        ui.openPage(.parlay)
    }

    func quick(_ v: Int) { stake = String(v); error = nil; capped = false }

    func step(_ d: Int) {
        let v = (Int(stake ?? "") ?? 0) + d
        let max = Store.shared.wallet.balance
        capped = v > max
        stake = String(Swift.max(1, Swift.min(v, max)))
        error = nil
    }

    /// The stake can't go above today's betting balance: a bigger number snaps back to it.
    func typed(_ value: String) -> String {
        let max = Store.shared.wallet.balance
        let digits = value.filter(\.isNumber)
        let n = Int(digits)
        capped = n != nil && n! > max
        let result = capped ? String(max) : digits
        stake = result
        error = nil
        return result
    }

    func acceptNewOdds() {
        for i in legs.indices {
            if let cur = Feed.currentSelection(legs[i].selId), let sel = cur.sel {
                legs[i].price = sel.price
                legs[i].line = sel.line
            }
        }
        error = nil
    }

    func place() {
        guard Net.shared.online else { return }
        let n = numbers()
        do {
            let bet = try Store.shared.placeBet(picks: legs, stake: n.stake, boost: boost, insure: insure)
            let label = bet.legs.count > 1 ? "\(bet.legs.count)-pick parlay" : bet.legs[0].label
            let win = jsRoundInt(Double(jsRoundInt(Double(bet.stake) * bet.decimal) - bet.stake) * bet.multiplier)
            ui.toast(.win, "Bet placed", "\(label) · \(bet.stake) min to win \(win) min. It's in My Bets.")
            clear()
            ui.closeSheet(.slip, silent: true)
            ui.closePage(.parlay, silent: true)
        } catch let e as AppError {
            error = e.code == "odds_changed" ? nil : e.message
            if e.code == "odds_changed" { ui.toast(.warn, "Odds changed", "Review the new odds and confirm again.") }
        } catch {}
    }
}
