import Foundation
import Observation

/// The challenge slip (Screen 3). A port of the web demo's slip.js state and actions.
@Observable
final class Slip {
    static let shared = Slip()

    var picks: [SlipPick] = []
    /// Picks stack up only in combo mode; otherwise a new pick replaces the old one.
    var comboMode = false
    var pledgeMinutes: String?
    var boost = false
    var insure = false
    var error: String?
    var capped = false

    func has(_ id: String) -> Bool { picks.contains { $0.selId == id } }

    func clear() {
        picks = []; comboMode = false; pledgeMinutes = nil; boost = false; insure = false; error = nil; capped = false
    }

    private static func refOf(_ sel: Selection) -> String { sel.gameId ?? sel.predId ?? sel.raceId ?? "" }

    private var ui: UIState { .shared }

    /// Tap on a point-value button. Outside combo mode the pick replaces whatever is on the slip and opens it;
    /// in combo mode it's added, or swapped for a second pick on the same game.
    func toggle(_ selId: String) {
        if has(selId) {
            picks.removeAll { $0.selId == selId }
            afterChange()
            return
        }
        guard let cur = Feed.currentSelection(selId), let sel = cur.sel, cur.open else {
            ui.toast(.warn, "This pick is closed")
            return
        }
        let hasRace = picks.contains { $0.ref.hasPrefix("race-") }
        if comboMode && (sel.kind == "race" || hasRace) {
            ui.toast(.warn, "Virtual races are single picks", "Place a virtual race challenge on its own, outside a combo.")
            return
        }
        let pick = SlipPick(selId: sel.id, price: sel.price, line: sel.line, ref: Self.refOf(sel))
        if !comboMode {
            picks = [pick]
            error = nil
            open()
            afterChange()
            return
        }
        if let same = picks.firstIndex(where: { $0.ref == pick.ref }) {
            picks[same] = pick
            ui.toast(.info, "Pick swapped", "A combo can only have one pick per game.", ms: 2600)
        } else {
            if picks.count >= Rules.maxPicks {
                ui.toast(.warn, "Combos are limited to \(Rules.maxPicks) picks", "Remove a pick to add another.")
                return
            }
            picks.append(pick)
        }
        error = nil
        afterChange()
    }

    func toggleComboMode() {
        comboMode.toggle()
        picks = []
        error = nil
        ui.closeSheet(.slip, silent: true) // not discard(): that would also switch combo mode back off
        ui.closePage(.combo, silent: true)
    }

    private func afterChange() {
        if picks.isEmpty {
            ui.closeSheet(.slip)
            ui.closePage(.combo, silent: true)
        }
    }

    /// Closing the slip (X or tapping outside) throws the picks away, so nothing lingers on Home.
    func discard() {
        clear()
        ui.closePage(.combo, silent: true)
    }

    func open() {
        if !ui.sheetOpen(.slip) { ui.openSheet(.slip) }
    }

    func remove(_ selId: String) {
        picks.removeAll { $0.selId == selId }
        afterChange()
    }

    struct PickState { var sel: Selection?; var closed: Bool; var changed: Bool }

    func pickState(_ pick: SlipPick) -> PickState {
        let cur = Feed.currentSelection(pick.selId)
        let closed = cur == nil || cur?.sel == nil || cur?.open != true
        let changed = !closed && (cur!.sel!.price != pick.price || cur!.sel!.line != pick.line)
        return PickState(sel: cur?.sel, closed: closed, changed: changed)
    }

    func status() -> (states: [PickState], closed: Bool, changed: Bool) {
        let states = picks.map(pickState)
        return (states, states.contains { $0.closed }, states.contains { $0.changed })
    }

    var decimal: Double { picks.reduce(1.0) { $0 * PointValueMath.decimal($1.price) } }

    struct Numbers { var wl: WalletView; var pledgeMinutes: Int?; var dec: Double; var american: Int; var mult: Double; var winnings: Int; var valid: Bool }

    func numbers() -> Numbers {
        let wl = Store.shared.wallet
        let pledgeMinutes = pledgeMinutes.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let dec = decimal
        var mult = wl.multiplier
        if boost && wl.boostsLeft > 0 { mult *= 1 + Rules.boostPercent }
        let s = pledgeMinutes ?? 0
        let winnings = jsRoundInt(Double(jsRoundInt(Double(s) * dec) - s) * mult)
        let valid = pledgeMinutes != nil && pledgeMinutes! >= 1 && pledgeMinutes! <= wl.balance && Net.shared.online
        return Numbers(wl: wl, pledgeMinutes: pledgeMinutes, dec: dec, american: PointValueMath.fromDecimal(dec), mult: mult, winnings: winnings, valid: valid)
    }

    /// The pledge shown when the slip opens: the last pledge, capped to the balance.
    func preparePledge() {
        if pledgeMinutes == nil {
            let wl = Store.shared.wallet
            pledgeMinutes = String(max(1, min(Store.shared.data?.lastPledge ?? 5, max(wl.balance, 1))))
        }
    }

    // MARK: Actions

    func addMore() {
        comboMode = true
        ui.closeSheet(.slip, silent: true) // hide it without discarding the picks
        ui.openPage(.combo)
    }

    func quick(_ v: Int) { pledgeMinutes = String(v); error = nil; capped = false }

    func step(_ d: Int) {
        let v = (Int(pledgeMinutes ?? "") ?? 0) + d
        let max = Store.shared.wallet.balance
        capped = v > max
        pledgeMinutes = String(Swift.max(1, Swift.min(v, max)))
        error = nil
    }

    /// The pledge can't go above today's challenging balance: a bigger number snaps back to it.
    func typed(_ value: String) -> String {
        let max = Store.shared.wallet.balance
        let digits = value.filter(\.isNumber)
        // Closing the keyboard re-sends the same text; keep the "not enough screentime" note up.
        if digits == pledgeMinutes { return digits }
        let n = Int(digits)
        capped = n != nil && n! > max
        let result = capped ? String(max) : digits
        pledgeMinutes = result
        error = nil
        return result
    }

    func acceptNewPointValue() {
        for i in picks.indices {
            if let cur = Feed.currentSelection(picks[i].selId), let sel = cur.sel {
                picks[i].price = sel.price
                picks[i].line = sel.line
            }
        }
        error = nil
    }

    func place() {
        guard Net.shared.online else { return }
        let n = numbers()
        do {
            let challenge = try Store.shared.placeChallenge(picks: picks, pledgeMinutes: n.pledgeMinutes, boost: boost, insure: insure)
            let label = challenge.picks.count > 1 ? "\(challenge.picks.count)-pick combo" : challenge.picks[0].label
            let win = jsRoundInt(Double(jsRoundInt(Double(challenge.pledgeMinutes) * challenge.decimal) - challenge.pledgeMinutes) * challenge.multiplier)
            ui.toast(.win, "Challenge placed", "\(label) · \(challenge.pledgeMinutes) min to earn \(win) min. It's in My Challenges.")
            clear()
            ui.closeSheet(.slip, silent: true)
            ui.closePage(.combo, silent: true)
        } catch let e as AppError {
            error = e.code == "value_changed" ? nil : e.message
            if e.code == "value_changed" { ui.toast(.warn, "Point value changed", "Review the new point value and confirm again.") }
        } catch {}
    }
}
