#if DEBUG
import Foundation

/// Fills the signed-in account with realistic activity for App Store screenshots.
/// Debug builds only: launch with `-seed-screenshots`. Everything goes through the normal app paths,
/// so sports bets and the team save to Supabase like any other.
enum ScreenshotSeed {
    private static var started = false

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seed-screenshots"), !started, AppModel.shared.inShell else { return }
        started = true
        Task { await run() }
    }

    private static func run() async {
        let store = Store.shared, ui = UIState.shared
        ui.toast(.info, "Adding screenshot data…", "This takes about a minute.")

        // Lock a few apps: All-Star tier, a daily bonus and an odds boost.
        if store.data?.settings.lockedApps.isEmpty ?? true {
            store.setLockedApps(["instagram", "tiktok", "youtube", "cat-social"])
        }

        // Friends (the demo profiles accept within seconds) and one incoming request.
        for u in ["mike_t", "jess.plays", "lily_k", "coach_dan", "coop_24"] where store.relation(u) == "none" {
            store.sendFriendRequest(u)
        }
        if var d = store.data, store.relation("priya_p") == "none" {
            d.requestsIn.append(FriendRequest(id: TO.uid("fr"), from: "priya_p", at: TO.now() - 20 * TO.MIN))
            store.data = d
            store.save()
        }

        // Wait for scores and odds.
        for _ in 0..<30 where Feed.board().filter({ !Feed.odds($0.id).all.isEmpty }).count < 3 {
            try? await Task.sleep(for: .seconds(1))
        }

        // Sports bets on today's open games: three singles and a two-pick parlay.
        var used = Set(store.data?.bets.flatMap { $0.legs.compactMap(\.gameId) } ?? [])
        let games = (Feed.board(day: 0) + Feed.board(day: 1)).filter { g in
            (g.state == .scheduled || g.state == .live) && !Feed.odds(g.id).suspended && !Feed.odds(g.id).all.isEmpty
        }
        func pick(_ choose: (OddsBoard) -> Selection?) -> SlipLeg? {
            for g in games where !used.contains(g.id) {
                if let sel = choose(Feed.odds(g.id)) {
                    used.insert(g.id)
                    return SlipLeg(selId: sel.id, price: sel.price, line: sel.line, ref: g.id)
                }
            }
            return nil
        }
        let singles: [(SlipLeg?, Int)] = [
            (pick { $0.moneyline.first { $0.side == "home" } }, 10),
            (pick { $0.spread.first { $0.side == "away" } }, 5),
            (pick { $0.total.first { $0.side == "over" } }, 5),
        ]
        for (leg, stake) in singles {
            guard let leg else { continue }
            _ = try? store.placeBet(picks: [leg], stake: stake, boost: false, insure: false)
        }
        if let a = pick({ $0.moneyline.first { $0.side == "away" } }), let b = pick({ $0.total.first { $0.side == "under" } }) {
            _ = try? store.placeBet(picks: [a, b], stake: 5, boost: false, insure: false)
        }

        // A team with three of the friends.
        let today = TO.dayKey()
        if !(store.data?.teams.contains { $0.name == "Sunday Squad" } ?? false) {
            _ = try? store.createTeam(name: "Sunday Squad", start: TO.addDays(today, -2), end: TO.addDays(today, 5),
                                      members: ["mike_t", "jess.plays", "lily_k"])
        }

        // Settled history right away: three virtual races (12 seconds each).
        for horse in [1, 3, 2] {
            let race = Races.shared.current
            guard race.status == "open" else { break }
            let sel = Races.shared.selection(race, Races.shared.horse(horse))
            guard (try? store.placeBet(picks: [SlipLeg(selId: sel.id, price: sel.price, line: nil, ref: "race-\(race.number)")],
                                       stake: 3, boost: false, insure: false)) != nil else { break }
            try? await Task.sleep(for: .seconds(13))
            AppModel.shared.tickNow(force: true)
            try? await Task.sleep(for: .seconds(1))
        }

        AppModel.shared.tickNow(force: true)
        ui.toast(.win, "Screenshot data added", "Open bets, race results, friends and a team are ready.")
    }
}
#endif
