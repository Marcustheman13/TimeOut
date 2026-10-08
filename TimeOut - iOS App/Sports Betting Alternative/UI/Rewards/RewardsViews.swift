import SwiftUI

struct TierBadge: View {
    let tier: Tier
    var compact = false

    var body: some View {
        let color = Color(hex: tier.colorHex)
        HStack(spacing: 5) {
            Image(systemName: tier.symbol)
            Text(tier.title.uppercased())
        }
        .font(.system(size: compact ? 10 : 12, weight: .black))
        .foregroundStyle(tier == .rookie ? .white : .black)
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(tier == .rookie ? Theme.raised : color, in: .capsule)
        .accessibilityLabel("\(tier.title) tier")
    }
}

/// Tier, streak and boosts under the wallet on Home. Tap for details in Account.
struct StatusStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let book = model.book
        let tier = model.tier
        Button {
            model.tab = .account
        } label: {
            HStack(spacing: 10) {
                TierBadge(tier: tier)
                pill(icon: "flame.fill", text: book.streakDays > 0 ? "\(book.streakDays)-day streak" : "No streak",
                     color: book.streakDays > 0 ? Theme.warning : Theme.textMuted)
                if book.streakMultiplier > 1 {
                    pill(icon: "arrow.up.right", text: "\(Rewards.formatMultiplier(book.streakMultiplier)) wins",
                         color: Theme.accent)
                }
                if tier.dailyBoosts > 0 {
                    pill(icon: "bolt.fill", text: "\(book.boostsLeft(for: tier)) boost\(book.boostsLeft(for: tier) == 1 ? "" : "s")",
                         color: Color(hex: "4FB3FF"))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func pill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(color)
        .lineLimit(1)
    }
}

/// Full status on the Account page: tier ladder, what's needed for the next tier, perks and streak.
struct StatusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let screenTime = model.screenTime
        let tier = model.tier
        let points = screenTime.isEnforcing ? screenTime.lockPoints : 0

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your status").font(.system(size: 16, weight: .heavy))
                Spacer()
                TierBadge(tier: tier)
            }

            // Progress toward the next tier.
            if let next = tier.next {
                let from = tier.minPoints, to = next.minPoints
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(points) lock point\(points == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                        Text(model.earnedTier > tier ? "Blocked, see below" : "\(max(to - points, 0)) more for \(next.title)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ProgressView(value: Double(min(max(points - from, 0), to - from)), total: Double(to - from))
                        .tint(Color(hex: next.colorHex))
                }
            } else {
                Text("Top tier. \(points) lock points.")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: tier.colorHex))
            }

            if !screenTime.isEnforcing {
                note("Connect Screen Time and lock apps to start climbing.", color: Theme.warning)
            } else if model.earnedTier > tier {
                note("Your lock points earn \(model.earnedTier.title), but your locked apps logged under \(Rewards.qualifyingWeeklyMinutes) min this week. Lock the apps you actually use.", color: Theme.warning)
            }

            // Ladder
            VStack(spacing: 8) {
                ForEach(Tier.allCases.dropFirst(), id: \.self) { rung in
                    ladderRow(rung, current: tier)
                }
            }

            Text("Apps and websites are 1 point, whole categories (like Social) are 3. Removing apps lowers your tier at midnight.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)

            Divider().overlay(Theme.stroke)
            streak
        }
        .card()
    }

    private func ladderRow(_ rung: Tier, current: Tier) -> some View {
        let reached = current >= rung
        let color = Color(hex: rung.colorHex)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: reached ? "checkmark.circle.fill" : rung.symbol)
                .font(.system(size: 16))
                .foregroundStyle(reached ? color : Theme.textMuted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rung.title).font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(reached ? .white : Theme.textSecondary)
                    Text("\(rung.minPoints)+ pts")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
                Text(rung.perks.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(reached ? Theme.textSecondary : Theme.textMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private var streak: some View {
        let book = model.book
        let days = book.streakDays
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(days > 0 ? Theme.warning : Theme.textMuted)
                Text(days > 0 ? "\(days)-day clean streak" : "No clean streak yet")
                    .font(.system(size: 15, weight: .heavy))
                Spacer()
                if book.streakMultiplier > 1 {
                    Text("Wins \(Rewards.formatMultiplier(book.streakMultiplier))")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accent, in: .capsule)
                }
            }
            if let milestone = Rewards.nextStreakMilestone(after: days) {
                ProgressView(value: Double(days), total: Double(milestone.days))
                    .tint(Theme.warning)
                Text("\(milestone.days - days) more clean day\(milestone.days - days == 1 ? "" : "s") for \(Rewards.formatMultiplier(milestone.multiplier)) winnings.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("A clean day: limits on, stayed under your limit, no emergency unlock. An emergency unlock resets the streak.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private func note(_ text: String, color: Color) -> some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.1), in: .rect(cornerRadius: 10))
    }
}
