import Foundation
import Observation

nonisolated struct WalletState: Codable, Sendable {
    /// The local day this wallet's balance belongs to.
    var dayKey: String
    /// Minutes available to stake today.
    var balance: Int
    /// Set once the balance hits zero — no new bets until midnight (PRD).
    var lockedOut = false
    /// Net minutes won/lost by bets, keyed by the day they were *placed*. Feeds the next day's screen time limit.
    var netByDay: [String: Int] = [:]
    /// Emergency-override penalties, keyed by the day whose limit they reduce.
    var penaltyByDay: [String: Int] = [:]
    /// Number of emergency overrides used, keyed by the day they were used.
    var overridesByDay: [String: Int] = [:]
    /// Days on which betting was forfeited for revoking Screen Time access. Optional so older saves still decode.
    var forfeitDays: [String]?
    // Rewards (all optional for the same reason).
    /// Tier bonus minutes already added to `bonusDay`'s balance.
    var bonusDay: String?
    var bonusGranted: Int?
    var boostsByDay: [String: Int]?
    /// Parlay insurance used, keyed by ISO week.
    var insuranceByWeek: [String: Int]?
    /// Consecutive clean days (under the limit, no emergency unlock) and the last day counted.
    var streakDays: Int?
    var streakEvaluatedThrough: String?
}

nonisolated enum BetError: LocalizedError, Equatable {
    case notEnoughScreenTime(remaining: Int)
    case lockedOut
    case oddsChanged
    case marketClosed
    case tooManyLegs
    case invalidStake
    case missingFriendStake
    case emptySlip

    var errorDescription: String? {
        switch self {
        case .notEnoughScreenTime(let remaining): "Not enough screentime. You have \(remaining) min left."
        case .lockedOut: "You're out of screentime for today. Betting reopens at midnight."
        case .oddsChanged: "Odds changed. Review and accept the new odds to continue."
        case .marketClosed: "One of your picks is no longer available."
        case .tooManyLegs: "Parlays are limited to \(BetBook.maxLegs) legs."
        case .invalidStake: "Enter a stake of at least 1 minute."
        case .missingFriendStake: "Add what's on the line for your friend bet."
        case .emptySlip: "Add a pick to your bet slip."
        }
    }
}

/// Owns the screen-time wallet and every bet, and persists both.
@Observable
final class BetBook {
    nonisolated static let dailyAllowance = 60
    nonisolated static let maxLegs = 3
    nonisolated static let friendStakeLimit = 100
    nonisolated static let overrideMinutes = 15
    nonisolated static let overridePenalty = 30
    nonisolated static let maxOverridesPerDay = 2

    private(set) var bets: [Bet]
    private(set) var wallet: WalletState
    var lastStake: Int { didSet { save() } }

    private let persistence = Persistence()

    init(now: Date = .now) {
        let saved = persistence.load()
        bets = saved?.bets ?? []
        wallet = saved?.wallet ?? WalletState(dayKey: DayClock.key(for: now), balance: Self.dailyAllowance)
        lastStake = saved?.lastStake ?? 5
        rolloverIfNeeded(now: now)
    }

    // MARK: Derived state

    var openBets: [Bet] { bets.filter { $0.status == .open }.sorted { $0.placedAt > $1.placedAt } }
    var settledBets: [Bet] { bets.filter { $0.status != .open }.sorted { ($0.settledAt ?? $0.placedAt) > ($1.settledAt ?? $1.placedAt) } }
    var screenTimeBets: [Bet] { bets.filter { !$0.isFriendBet } }

    var balance: Int { wallet.balance }
    var isLockedOut: Bool { wallet.lockedOut }
    var todayKey: String { wallet.dayKey }

    /// Phone screen time allowed today: 60 + yesterday's net result − any override penalty.
    var todayLimit: Int {
        #if DEBUG
        if let debugTodayLimit { return debugTodayLimit }
        #endif
        return limit(for: wallet.dayKey)
    }

    #if DEBUG
    /// Temporarily replaces today's limit so the Screen Time lock can be tested in minutes, not an hour.
    var debugTodayLimit: Int?
    #endif

    /// Projected limit for tomorrow based on today's settled bets so far.
    var tomorrowLimit: Int { limit(for: DayClock.key(wallet.dayKey, offsetBy: 1)) }

    var todayNet: Int { wallet.netByDay[wallet.dayKey] ?? 0 }
    var minutesAtRisk: Int { openBets.filter { !$0.isFriendBet }.reduce(0) { $0 + $1.stake } }
    var overridesUsedToday: Int { wallet.overridesByDay[wallet.dayKey] ?? 0 }
    var canOverride: Bool { overridesUsedToday < Self.maxOverridesPerDay }

    // MARK: Rewards

    var streakDays: Int { wallet.streakDays ?? 0 }
    var streakMultiplier: Double { Rewards.streakMultiplier(days: streakDays) }
    var boostsUsedToday: Int { wallet.boostsByDay?[wallet.dayKey] ?? 0 }

    func boostsLeft(for tier: Tier) -> Int { max(tier.dailyBoosts - boostsUsedToday, 0) }

    func insuranceLeft(for tier: Tier, now: Date = .now) -> Int {
        max(tier.weeklyInsurance - (wallet.insuranceByWeek?[Rewards.weekKey(for: now)] ?? 0), 0)
    }

    /// Tops up today's betting balance with the tier bonus. Only ever adds the difference, so moving up a tier
    /// mid-day pays the extra once. No bonus while locked out.
    func grantTierBonus(_ tier: Tier) {
        if wallet.bonusDay != wallet.dayKey {
            wallet.bonusDay = wallet.dayKey
            wallet.bonusGranted = 0
        }
        let owed = tier.bonusMinutes - (wallet.bonusGranted ?? 0)
        guard owed > 0, !wallet.lockedOut else { return }
        wallet.balance += owed
        wallet.bonusGranted = tier.bonusMinutes
        save()
    }

    /// Counts clean days up to and including `yesterday`. A day is clean when limits were on, the limit
    /// wasn't reached and no emergency unlock was used.
    func evaluateStreak(through yesterday: String, isClean: (String) -> Bool) {
        var day = wallet.streakEvaluatedThrough.map { DayClock.key($0, offsetBy: 1) } ?? yesterday
        guard day <= yesterday else { return }
        var streak = wallet.streakDays ?? 0
        var steps = 0
        while day <= yesterday && steps < 60 {
            let clean = isClean(day) && (wallet.overridesByDay[day] ?? 0) == 0
            streak = clean ? streak + 1 : 0
            wallet.streakEvaluatedThrough = day
            day = DayClock.key(day, offsetBy: 1)
            steps += 1
        }
        wallet.streakDays = streak
        save()
    }

    func limit(for dayKey: String) -> Int {
        let previous = DayClock.key(dayKey, offsetBy: -1)
        let net = wallet.netByDay[previous] ?? 0
        let penalty = wallet.penaltyByDay[dayKey] ?? 0
        return max(Self.dailyAllowance + net - penalty, 0)
    }

    // MARK: Day rollover

    /// Resets the betting balance at local midnight. Returns true if a new day started.
    @discardableResult
    func rolloverIfNeeded(now: Date = .now) -> Bool {
        let today = DayClock.key(for: now)
        guard today != wallet.dayKey else { return false }
        wallet.dayKey = today
        wallet.balance = Self.dailyAllowance
        wallet.lockedOut = false
        pruneHistory()
        save()
        return true
    }

    // MARK: Placing bets

    func validate(stake: Int, isFriendBet: Bool) throws(BetError) {
        if isFriendBet { return }
        if wallet.lockedOut || wallet.balance <= 0 { throw .lockedOut }
        guard stake >= 1 else { throw .invalidStake }
        guard stake <= wallet.balance else { throw .notEnoughScreenTime(remaining: wallet.balance) }
    }

    func place(legs: [BetLeg], stake: Int, friendStake: String?, perks: BetPerks = BetPerks(), now: Date = .now) throws(BetError) -> Bet {
        rolloverIfNeeded(now: now)
        guard !legs.isEmpty else { throw .emptySlip }
        guard legs.count <= Self.maxLegs else { throw .tooManyLegs }

        let trimmed = friendStake?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isFriendBet = friendStake != nil
        if isFriendBet && (trimmed ?? "").isEmpty { throw .missingFriendStake }
        try validate(stake: stake, isFriendBet: isFriendBet)

        let odds = legs.reduce(1.0) { $0 * $1.selection.decimalOdds }
        var bet = Bet(
            placedAt: now,
            dayKey: wallet.dayKey,
            stake: isFriendBet ? 0 : stake,
            legs: legs,
            decimalOdds: odds,
            friendStake: isFriendBet ? String(trimmed!.prefix(Self.friendStakeLimit)) : nil
        )
        if !isFriendBet {
            let multiplier = perks.winningsMultiplier
            bet.winningsMultiplier = multiplier == 1 ? nil : multiplier
            if perks.boosted {
                bet.boosted = true
                wallet.boostsByDay = (wallet.boostsByDay ?? [:]).merging([wallet.dayKey: boostsUsedToday + 1]) { $1 }
            }
            if perks.insured && legs.count > 1 {
                bet.insured = true
                let week = Rewards.weekKey(for: now)
                var weeks = wallet.insuranceByWeek ?? [:]
                weeks[week, default: 0] += 1
                wallet.insuranceByWeek = weeks
            }
        }
        bets.append(bet)
        if !isFriendBet {
            wallet.balance -= stake
            lastStake = stake
            if wallet.balance <= 0 {
                wallet.balance = 0
                wallet.lockedOut = true
            }
        }
        save()
        return bet
    }

    // MARK: Settlement

    /// Snapshots of games that open bets are waiting on.
    var pendingGames: [GameSnapshot] {
        var seen = Set<String>()
        return openBets.flatMap(\.legs).filter { $0.result == .pending }.map(\.game).filter { seen.insert($0.gameID).inserted }
    }

    /// Grades open bets against the latest game states. Returns bets that settled in this pass.
    func settle(using games: [String: Game], now: Date = .now) -> [Bet] {
        var settled: [Bet] = []
        for index in bets.indices where bets[index].status == .open {
            var bet = bets[index]
            var changed = false
            for legIndex in bet.legs.indices where bet.legs[legIndex].result == .pending {
                guard let game = games[bet.legs[legIndex].game.gameID] else { continue }
                let result = Settlement.grade(bet.legs[legIndex].selection, in: game)
                if result != .pending {
                    bet.legs[legIndex].result = result
                    bet.legs[legIndex].finalScore = game.state.isVoid ? game.state.rawValue.capitalized : Settlement.scoreLine(game)
                    changed = true
                }
            }
            guard changed else { continue }

            var (status, payout) = Settlement.outcome(for: bet)
            if bet.isInsured && status == .lost {
                // Insured parlays wait for every leg, then refund if exactly one leg missed.
                if bet.legs.contains(where: { $0.result == .pending }) {
                    status = .open
                } else if bet.legs.filter({ $0.result == .lost }).count == 1 {
                    status = .push
                    payout = bet.stake
                    bet.insurancePaid = true
                }
            }
            if status == .won {
                payout = bet.stake + Int((Double(payout - bet.stake) * bet.multiplier).rounded())
            }
            if status != .open {
                bet.status = status
                bet.payout = bet.isFriendBet ? 0 : payout
                bet.settledAt = now
                apply(bet)
                settled.append(bet)
            }
            bets[index] = bet
        }
        if !settled.isEmpty { save() }
        return settled
    }

    private func apply(_ bet: Bet) {
        guard !bet.isFriendBet else { return }
        wallet.netByDay[bet.dayKey, default: 0] += bet.netMinutes
        // Winnings and refunds go back into today's betting balance only if the bet was placed today;
        // stakes from earlier days are already reflected in today's screen time limit.
        if bet.dayKey == wallet.dayKey {
            wallet.balance += bet.payout
        }
    }

    // MARK: Emergency override

    /// Records an emergency unlock and charges the penalty against tomorrow's limit.
    func recordOverride(now: Date = .now) {
        rolloverIfNeeded(now: now)
        let tomorrow = DayClock.key(wallet.dayKey, offsetBy: 1)
        wallet.overridesByDay[wallet.dayKey, default: 0] += 1
        wallet.penaltyByDay[tomorrow, default: 0] += Self.overridePenalty
        wallet.streakDays = 0
        save()
    }

    // MARK: Commitment lock

    /// Revoking Screen Time access mid-day forfeits the rest of the day's betting.
    func forfeitToday(now: Date = .now) {
        rolloverIfNeeded(now: now)
        wallet.balance = 0
        wallet.lockedOut = true
        var days = wallet.forfeitDays ?? []
        if !days.contains(wallet.dayKey) { days.append(wallet.dayKey) }
        wallet.forfeitDays = days
        save()
    }

    var forfeitCount: Int { wallet.forfeitDays?.count ?? 0 }

    // MARK: Persistence

    private func pruneHistory() {
        let cutoff = DayClock.key(wallet.dayKey, offsetBy: -60)
        wallet.netByDay = wallet.netByDay.filter { $0.key >= cutoff }
        wallet.penaltyByDay = wallet.penaltyByDay.filter { $0.key >= cutoff }
        wallet.overridesByDay = wallet.overridesByDay.filter { $0.key >= cutoff }
        wallet.boostsByDay = wallet.boostsByDay?.filter { $0.key >= cutoff }
    }

    private func save() {
        persistence.save(.init(bets: bets, wallet: wallet, lastStake: lastStake))
    }

    #if DEBUG
    /// Wipes all local data. Exposed in the Account screen for demos and testing.
    func resetAll(now: Date = .now) {
        bets = []
        wallet = WalletState(dayKey: DayClock.key(for: now), balance: Self.dailyAllowance)
        lastStake = 5
        save()
    }
    #endif
}

private nonisolated struct Persistence {
    struct Snapshot: Codable {
        var bets: [Bet]
        var wallet: WalletState
        var lastStake: Int
    }

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("staketime.json")
    }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
