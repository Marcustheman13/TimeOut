import Foundation
import Observation

struct Toast: Identifiable, Equatable {
    enum Style { case win, loss, neutral }
    let id = UUID()
    var title: String
    var message: String
    var style: Style
}

enum AppTab: Hashable {
    case home, bets, record, account
}

/// Wires the feed, the bet book, the slip and Screen Time together and runs the refresh loop.
@Observable
final class AppModel {
    let feed = GameFeed()
    let book = BetBook()
    let slip = BetSlip()
    let screenTime = ScreenTimeManager()
    let sports = SportsPreferences()

    var tab: AppTab = .home
    var toast: Toast?
    /// Shown when Screen Time access was revoked while limits were on.
    var showForfeitNotice = false
    /// Bet currently open in the share sheet.
    var sharing: Bet?

    private var loop: Task<Void, Never>?

    init() {
        slip.stake = book.lastStake
    }

    // MARK: Rewards

    /// Lock tier from what's locked. Above Starter, the locked apps must see real use (or be in the first week).
    var tier: Tier {
        guard screenTime.isEnforcing else { return .rookie }
        let earned = Tier.forPoints(screenTime.lockPoints)
        return tierQualifies ? earned : min(earned, .starter)
    }

    /// Tier the lock points would earn if usage qualified.
    var earnedTier: Tier { screenTime.isEnforcing ? Tier.forPoints(screenTime.lockPoints) : .rookie }

    var tierQualifies: Bool {
        screenTime.inGracePeriod || screenTime.weeklyUsage >= Rewards.qualifyingWeeklyMinutes
    }

    // MARK: Refresh loop

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: GameFeed.refreshInterval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func tick(now: Date = .now) async {
        if book.rolloverIfNeeded(now: now) {
            show(Toast(title: "New day, fresh 60", message: "Your betting balance reset to \(BetBook.dailyAllowance) min.", style: .neutral))
        }

        await feed.refresh(now: now, leagues: sports.followed)

        // Settle open bets — from the board when possible, otherwise by looking the game up directly.
        var games: [String: Game] = [:]
        var missing: [GameSnapshot] = []
        for snapshot in book.pendingGames {
            if let game = feed.game(id: snapshot.gameID) {
                games[game.id] = game
            } else {
                missing.append(snapshot)
            }
        }
        if !missing.isEmpty {
            for game in await feed.lookup(missing, now: now) { games[game.id] = game }
        }
        for bet in book.settle(using: games, now: now) {
            announce(bet)
        }

        slip.sync(with: feed)
        syncScreenTime(now: now)
    }

    /// Runs when iOS wakes the app in the background: settle what can be settled, then update Screen Time.
    func backgroundRefresh(now: Date = .now) async {
        book.rolloverIfNeeded(now: now)
        let pending = book.pendingGames
        if !pending.isEmpty {
            let games = await feed.lookup(pending, now: now)
            let byID = Dictionary(games.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for bet in book.settle(using: byID, now: now) {
                Notifier.betSettled(bet)
            }
        }
        syncScreenTime(now: now)
        BackgroundSettlement.schedule(hasOpenBets: !book.openBets.isEmpty)
    }

    func didEnterBackground() {
        stop()
        BackgroundSettlement.schedule(hasOpenBets: !book.openBets.isEmpty)
    }

    func syncScreenTime(now: Date = .now) {
        let decided = book.screenTimeBets.filter { $0.status == .won || $0.status == .lost }
        let wins = decided.filter { $0.status == .won }.count
        ScreenTimeShared.defaults.set(decided.isEmpty ? nil : "\(wins)-\(decided.count - wins)", forKey: ScreenTimeShared.recordKey)

        screenTime.refreshStatus()
        if screenTime.consumeRevocation() {
            book.forfeitToday(now: now)
            showForfeitNotice = true
        }

        screenTime.sync(
            todayKey: book.todayKey,
            todayLimit: book.todayLimit,
            tomorrowKey: DayClock.key(book.todayKey, offsetBy: 1),
            tomorrowLimit: book.tomorrowLimit,
            now: now
        )

        // Rewards: tier bonus minutes for today, and score any finished days toward the clean streak.
        book.grantTierBonus(tier)
        let screenTime = screenTime
        book.evaluateStreak(through: DayClock.key(book.todayKey, offsetBy: -1)) { day in
            screenTime.wasEnforced(on: day) && !screenTime.reachedLimit(on: day)
        }
    }

    // MARK: Actions

    /// Places whatever is on the slip. Returns the error to show inline, or nil on success.
    func placeBet() -> BetError? {
        slip.sync(with: feed)
        if slip.hasClosedLegs { return .marketClosed }
        if slip.hasOddsChanges { return .oddsChanged }

        let friendStake = slip.mode == .friend ? slip.friendStake : nil
        do {
            let bet = try book.place(legs: slip.betLegs(), stake: slip.stake, friendStake: friendStake, perks: slipPerks)
            slip.clear()
            slip.isPresented = false
            slip.stake = book.lastStake
            // First bet is the natural moment to ask: notifications tell you when bets settle in the background.
            Task { await Notifier.requestPermissionIfNeeded() }
            if bet.isFriendBet {
                sharing = bet
            } else {
                let message = "\(bet.stake) min on \(bet.title) · to win \(bet.potentialWinnings) min"
                show(Toast(title: "Bet placed", message: message, style: .neutral))
            }
            return nil
        } catch {
            return error
        }
    }

    /// Perks that would apply to the current slip.
    var slipPerks: BetPerks {
        guard slip.mode == .screenTime else { return BetPerks() }
        return BetPerks(
            boosted: slip.useBoost && book.boostsLeft(for: tier) > 0,
            insured: slip.useInsurance && slip.legs.count > 1 && book.insuranceLeft(for: tier) > 0,
            streakMultiplier: book.streakMultiplier
        )
    }

    func emergencyUnlock() -> String? {
        guard book.canOverride else { return "You've used both emergency unlocks today." }
        do {
            try screenTime.emergencyUnlock()
            book.recordOverride()
            syncScreenTime()
            show(Toast(
                title: "Unlocked for \(BetBook.overrideMinutes) min",
                message: "−\(BetBook.overridePenalty) min from tomorrow's screen time.",
                style: .loss
            ))
            return nil
        } catch {
            return "Couldn't unlock: \(error.localizedDescription)"
        }
    }

    func show(_ toast: Toast) {
        self.toast = toast
        let id = toast.id
        Task {
            try? await Task.sleep(for: .seconds(4))
            if self.toast?.id == id { self.toast = nil }
        }
    }

    private func announce(_ bet: Bet) {
        let friend = bet.friendStake.map { " · \($0)" } ?? ""
        switch bet.status {
        case .won:
            let detail = bet.isFriendBet ? "You won the friend bet\(friend)" : "\(bet.title) · \(bet.netMinutes.signedMinutes) to tomorrow"
            show(Toast(title: "Winner!", message: detail, style: .win))
        case .lost:
            let detail = bet.isFriendBet ? "You lost the friend bet\(friend)" : "\(bet.title) · \(bet.netMinutes.signedMinutes) from tomorrow"
            show(Toast(title: "Bet lost", message: detail, style: .loss))
        case .void:
            show(Toast(title: "Bet voided", message: "Game postponed or canceled. \(bet.stake) min refunded.", style: .neutral))
        case .push:
            show(Toast(title: "Push", message: "\(bet.title) · stake refunded.", style: .neutral))
        case .open:
            break
        }
    }
}
