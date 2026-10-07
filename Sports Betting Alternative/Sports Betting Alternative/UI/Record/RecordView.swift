import Charts
import SwiftUI

/// PRD should-have: overall record and performance.
struct RecordView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = RecordStats(book: model.book)
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    hero(stats)
                    tiles(stats)
                    NetChart(days: stats.last14Days)
                    if !stats.byLeague.isEmpty { leagueBreakdown(stats) }
                    extras(stats)
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Record")
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }

    private func hero(_ stats: RecordStats) -> some View {
        VStack(spacing: 6) {
            Text("\(stats.wins)-\(stats.losses)\(stats.pushes > 0 ? "-\(stats.pushes)" : "")")
                .font(.display(56, weight: .black))
            Text("SCREEN TIME RECORD")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.textSecondary)
            Text("Net \(stats.net.signedMinutes) all time")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(stats.net > 0 ? Theme.win : stats.net < 0 ? Theme.loss : Theme.textSecondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
    }

    private func tiles(_ stats: RecordStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile("Win rate", stats.winRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
            tile("Streak", stats.streak)
            tile("Minutes staked", "\(stats.staked)")
            tile("Biggest win", stats.biggestWin > 0 ? "+\(stats.biggestWin) min" : "—")
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(.display(26, weight: .black))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private func leagueBreakdown(_ stats: RecordStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By league").font(.system(size: 16, weight: .heavy))
            ForEach(stats.byLeague, id: \.league) { row in
                HStack {
                    Image(systemName: row.league.symbol).foregroundStyle(Theme.textSecondary).frame(width: 22)
                    Text(row.league.title).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(row.wins)-\(row.losses)")
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                    Text(row.net.signedMinutes)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(row.net >= 0 ? Theme.win : Theme.loss)
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
        .card()
    }

    private func extras(_ stats: RecordStats) -> some View {
        VStack(spacing: 10) {
            row("person.2.fill", "Friend bets", "\(stats.friendWins)-\(stats.friendLosses)")
            Divider().overlay(Theme.stroke)
            row("exclamationmark.lock.fill", "Emergency unlocks used", "\(stats.overrides)")
            Divider().overlay(Theme.stroke)
            row("arrow.uturn.backward.circle.fill", "Voided / pushed", "\(stats.voids + stats.pushes)")
        }
        .card()
    }

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(Theme.textSecondary).frame(width: 22)
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            Text(value).font(.system(size: 15, weight: .bold)).monospacedDigit()
        }
    }
}

/// Net minutes per day for the last two weeks. Polarity is encoded twice: bar direction and color.
private struct NetChart: View {
    let days: [RecordStats.Day]
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 14 days").font(.system(size: 16, weight: .heavy))
                Spacer()
                if let day = days.first(where: { $0.key == selected }) {
                    Text("\(day.label): \(day.net.signedMinutes)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Net minutes by day placed")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
            }

            Chart {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Theme.stroke)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(days) { day in
                    BarMark(x: .value("Day", day.key), y: .value("Net", day.net), width: .ratio(0.7))
                        .foregroundStyle(day.net >= 0 ? Theme.chartGain : Theme.chartLoss)
                        .clipShape(.rect(cornerRadius: 4))
                        .opacity(selected == nil || selected == day.key ? 1 : 0.4)
                }
            }
            .chartXSelection(value: $selected)
            .chartXAxis {
                AxisMarks(values: days.enumerated().filter { $0.offset % 4 == 0 }.map { $0.element.key }) { value in
                    AxisValueLabel {
                        if let key = value.as(String.self), let day = days.first(where: { $0.key == key }) {
                            Text(day.label).font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke.opacity(0.5))
                    AxisValueLabel().foregroundStyle(Theme.textMuted)
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Net screen time minutes per day for the last 14 days")
        }
        .card()
    }
}

struct RecordStats {
    struct Day: Identifiable {
        var key: String
        var label: String
        var net: Int
        var id: String { key }
    }

    struct LeagueRow {
        var league: League
        var wins = 0
        var losses = 0
        var net = 0
    }

    var wins = 0, losses = 0, pushes = 0, voids = 0
    var net = 0, staked = 0, biggestWin = 0
    var streak = "—"
    var friendWins = 0, friendLosses = 0
    var overrides = 0
    var byLeague: [LeagueRow] = []
    var last14Days: [Day] = []

    var winRate: Double? { wins + losses > 0 ? Double(wins) / Double(wins + losses) : nil }

    init(book: BetBook) {
        let settled = book.settledBets
        var leagues: [League: LeagueRow] = [:]
        for bet in settled {
            if bet.isFriendBet {
                if bet.status == .won { friendWins += 1 }
                if bet.status == .lost { friendLosses += 1 }
                continue
            }
            staked += bet.stake
            net += bet.netMinutes
            switch bet.status {
            case .won: wins += 1; biggestWin = max(biggestWin, bet.netMinutes)
            case .lost: losses += 1
            case .push: pushes += 1
            case .void: voids += 1
            case .open: break
            }
            if !bet.isParlay, let league = bet.legs.first?.game.league, bet.status == .won || bet.status == .lost {
                var row = leagues[league] ?? LeagueRow(league: league)
                if bet.status == .won { row.wins += 1 } else { row.losses += 1 }
                row.net += bet.netMinutes
                leagues[league] = row
            }
        }
        byLeague = leagues.values.sorted { $0.wins + $0.losses > $1.wins + $1.losses }

        // Streak: consecutive wins or losses, most recent first.
        let decided = settled.filter { !$0.isFriendBet && ($0.status == .won || $0.status == .lost) }
        if let first = decided.first {
            let count = decided.prefix { $0.status == first.status }.count
            streak = "\(first.status == .won ? "W" : "L")\(count)"
        }

        overrides = book.wallet.overridesByDay.values.reduce(0, +)

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        last14Days = (0..<14).reversed().map { offset in
            let key = DayClock.key(book.todayKey, offsetBy: -offset)
            let label = DayClock.date(for: key).map(formatter.string(from:)) ?? key
            return Day(key: key, label: label, net: book.wallet.netByDay[key] ?? 0)
        }
    }
}
