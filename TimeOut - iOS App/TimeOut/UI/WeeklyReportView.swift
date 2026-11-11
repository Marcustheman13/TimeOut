import SwiftUI

/// Menu > Weekly report. The server writes one review a week (supabase/functions/weekly-report); this only draws it.
struct WeeklyReportSection: View {
    private var reports: WeeklyReports { .shared }
    private var store: Store { .shared }
    @State private var selected = 0

    var body: some View {
        let list = reports.list
        VStack(alignment: .leading, spacing: 16) {
            if !store.usesServerSocial {
                note("Weekly reports are written for accounts that are signed in and synced. Log in to see yours.")
            } else if !reports.loaded {
                Text("Loading your reports…").font(.barlow(13)).foregroundStyle(Theme.text2)
            } else if list.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { Icon(.chart, 18).foregroundStyle(Theme.text2); H2("No report yet") }
                    Text("Every Monday morning TimeOut looks back at your week and writes you a short review: your challenge record, your net minutes and, once your phone has synced screen time, how you did against your limits. Your first one shows up here after a week with some activity.")
                        .font(.barlow(13)).foregroundStyle(Theme.text2)
                }
                .card()
            } else {
                let i = min(selected, list.count - 1)
                ReportCard(report: list[i])
                if list.count > 1 {
                    Text("Other weeks").eyebrow()
                    ListBox {
                        ForEach(Array(list.enumerated()).filter { $0.offset != i }, id: \.element.id) { item in
                            ListRow(item.element.headline, sub: AttributedString(item.element.range)) { EmptyView() } trailing: {
                                if !item.element.read { Tag("New", .green) }
                            }
                            .onTapGesture {
                                selected = item.offset
                                reports.markRead(item.element.week)
                            }
                        }
                    }
                }
            }
        }
        .task {
            selected = 0
            await reports.refresh(force: true)
            if let first = reports.list.first { reports.markRead(first.week) }
        }
    }

    private func note(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            H2("Weekly report")
            Text(text).font(.barlow(13)).foregroundStyle(Theme.text2)
        }
        .card()
    }
}

private struct ReportCard: View {
    var report: WeeklyReport

    private var tone: TagTone {
        switch report.weekType {
        case "crushed": return .green
        case "slipped": return .yellow
        case "risky": return .red
        default: return .blue
        }
    }

    private func statusColor(_ status: String) -> Color {
        status == "under" ? Theme.accent : status == "over" ? Theme.loss : Theme.muted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Tag(report.label, tone)
                Spacer()
                Text(report.range).font(.barlow(13)).foregroundStyle(Theme.text2)
            }
            Text(report.headline).font(.barlow(26, 800)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            Text(report.summary).font(.barlow(15)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)

            if !report.tiles.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(report.tiles, id: \.label) { t in
                        VStack(spacing: 4) {
                            Text(t.value).font(.barlow(20, 800)).monospacedDigit().foregroundStyle(Theme.text)
                            Text(t.label).font(.barlow(12)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                }
            }

            callout("Worth noticing", report.insight, Theme.accent)
            callout("Try this next week", report.suggestion, Theme.blue)

            if let days = report.days {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day by day").eyebrow()
                    ForEach(days, id: \.weekday) { d in
                        HStack {
                            Text(d.weekday).font(.barlow(14)).foregroundStyle(Theme.text)
                            Spacer()
                            Text(d.used.map { "\($0) min" } ?? "–").font(.barlow(14)).monospacedDigit().foregroundStyle(Theme.text)
                            Text("\(d.limit) min").font(.barlow(14)).monospacedDigit().foregroundStyle(Theme.muted).frame(width: 60, alignment: .trailing)
                            Text(d.status == "over" ? "Over" : d.status == "under" ? "Under" : "–")
                                .font(.barlow(14, 700)).foregroundStyle(statusColor(d.status)).frame(width: 46, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        HRule()
                    }
                }
            }

            Text("Written by an AI from your own numbers. TimeOut pledges phone minutes, never money.")
                .font(.barlow(11.5)).foregroundStyle(Theme.muted)
        }
        .card()
    }

    private func callout(_ title: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).eyebrow()
                Text(text).font(.barlow(15)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
