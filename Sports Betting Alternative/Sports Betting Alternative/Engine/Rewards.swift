import Foundation

/// Lock tiers: the more of your real screen time you put behind the lock, the more perks you get.
///
/// Apps and websites are worth 1 lock point, whole categories (e.g. Social) 3. iOS never reveals *which* apps
/// were picked, so to stop "lock Calculator, get perks", tiers above Starter require the locked apps to see real
/// use (see `Rewards.qualifies`).
nonisolated enum Tier: Int, CaseIterable, Comparable, Sendable {
    case rookie, starter, allStar, mvp, hallOfFame

    static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .rookie: "Rookie"
        case .starter: "Starter"
        case .allStar: "All-Star"
        case .mvp: "MVP"
        case .hallOfFame: "Hall of Fame"
        }
    }

    var symbol: String {
        switch self {
        case .rookie: "figure.walk"
        case .starter: "star"
        case .allStar: "star.fill"
        case .mvp: "trophy.fill"
        case .hallOfFame: "crown.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .rookie: "8C96A8"
        case .starter: "4FB3FF"
        case .allStar: "22D66E"
        case .mvp: "FFC940"
        case .hallOfFame: "C58CFF"
        }
    }

    var minPoints: Int {
        switch self {
        case .rookie: 0
        case .starter: 1
        case .allStar: 4
        case .mvp: 8
        case .hallOfFame: 12
        }
    }

    /// Extra minutes added to the daily betting balance (betting minutes, not phone time).
    var bonusMinutes: Int {
        switch self {
        case .rookie: 0
        case .starter, .allStar: 5
        case .mvp, .hallOfFame: 10
        }
    }

    /// Odds boosts per day: +10% winnings on one bet each.
    var dailyBoosts: Int {
        switch self {
        case .rookie, .starter: 0
        case .allStar: 1
        case .mvp, .hallOfFame: 2
        }
    }

    /// Parlay insurance per week: a parlay that misses by exactly one leg refunds the stake.
    var weeklyInsurance: Int { self == .hallOfFame ? 1 : 0 }

    var next: Tier? { Tier(rawValue: rawValue + 1) }

    var perks: [String] {
        var list: [String] = []
        if bonusMinutes > 0 { list.append("+\(bonusMinutes) betting min a day") }
        if dailyBoosts > 0 { list.append("\(dailyBoosts) odds boost\(dailyBoosts == 1 ? "" : "s") a day") }
        if weeklyInsurance > 0 { list.append("Parlay insurance weekly") }
        return list.isEmpty ? ["Lock apps to earn perks"] : list
    }

    static func forPoints(_ points: Int) -> Tier {
        allCases.last { points >= $0.minPoints } ?? .rookie
    }
}

nonisolated enum Rewards {
    static let boostPercent = 0.10
    /// Locked apps must log this much use over 7 days to count beyond Starter.
    static let qualifyingWeeklyMinutes = 30
    static let graceDays = 7

    static func lockPoints(apps: Int, categories: Int, sites: Int) -> Int {
        apps + sites + categories * 3
    }

    /// Winnings multiplier from the clean streak.
    static func streakMultiplier(days: Int) -> Double {
        days >= 7 ? 1.25 : days >= 3 ? 1.1 : 1
    }

    static func nextStreakMilestone(after days: Int) -> (days: Int, multiplier: Double)? {
        days < 3 ? (3, 1.1) : days < 7 ? (7, 1.25) : nil
    }

    static func formatMultiplier(_ value: Double) -> String {
        value == value.rounded() ? "×\(Int(value))" : "×" + String(format: "%.2f", value).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    /// ISO week key, used to reset weekly perks.
    static func weekKey(for date: Date = .now) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }
}

/// Perks applied to a bet at placement.
nonisolated struct BetPerks: Sendable, Equatable {
    var boosted = false
    var insured = false
    var streakMultiplier = 1.0

    /// Combined multiplier on winnings.
    var winningsMultiplier: Double { streakMultiplier * (boosted ? 1 + Rewards.boostPercent : 1) }
}
