import SwiftUI
import UIKit

@Observable
final class ChallengesModel {
    static let shared = ChallengesModel()
    var tab = "open"
    var filter = "all"
}

enum ChallengeLogic {
    static func pickStanding(_ pick: Pick) -> String {
        if pick.result != "pending" { return pick.result }
        if pick.kind == "todo" { return "upcoming" }
        if pick.kind == "race" {
            guard let race = Races.shared.get(pick.raceId), race.status != "open" else { return "upcoming" }
            if race.status == "running" { return race.winnerId == pick.horseId ? "winning" : "losing" }
            return "even"
        }
        return Feed.liveStanding(pick)
    }

    static func overallStanding(_ challenge: Challenge) -> String {
        let sts = challenge.picks.filter { $0.result == "pending" }.map { pickStanding($0) }
        if sts.contains("losing") { return "losing" }
        if !sts.isEmpty && sts.allSatisfy({ $0 == "winning" }) { return "winning" }
        if sts.allSatisfy({ $0 == "upcoming" }) { return "upcoming" }
        return "even"
    }

    static func gamePick(_ pick: Pick) -> Bool { pick.kind == "race" || pick.kind == "game" || (pick.kind == "sports" && pick.gameId != nil) }

    static func isLive(_ challenge: Challenge) -> Bool {
        challenge.picks.contains { pick in
            pick.result == "pending" && (pick.kind == "race" ? Races.shared.get(pick.raceId)?.status == "running"
                                        : gamePick(pick) && pick.gameId.flatMap { Feed.game($0) }?.state == .live)
        }
    }
}

struct MyChallengesView: View {
    private var store: Store { .shared }
    private var live: LiveFeed { .shared }
    private var model: ChallengesModel { .shared }
    private var ui: UIState { .shared }
    private var app: AppModel { .shared }

    var body: some View {
        let _ = live.version
        let _ = live.detailsVersion
        let _ = app.tick
        let _ = Races.shared.version
        let challenges = (store.data?.challenges ?? []).filter { ($0.kind == "sports" || $0.kind == "race") && !$0.picks.isEmpty && $0.picks.allSatisfy { ChallengeLogic.gamePick($0) } }
        let open = challenges.filter { $0.status == "open" }.sorted { $0.placedAt > $1.placedAt }
        let liveNow = open.filter { ChallengeLogic.isLive($0) }
        let otherOpen = open.filter { !ChallengeLogic.isLive($0) }
        let allSettled = challenges.filter { $0.status != "open" }.sorted { ($0.resolvedAt ?? 0) > ($1.resolvedAt ?? 0) }
        let counts = (all: allSettled.count, won: allSettled.filter { $0.status == "won" }.count, lost: allSettled.filter { $0.status == "lost" }.count,
                      void: allSettled.filter { $0.status != "won" && $0.status != "lost" }.count)
        let resolved = model.filter == "all" ? allSettled : allSettled.filter { model.filter == "void" ? ($0.status == "void" || $0.status == "tie") : $0.status == model.filter }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    PageHead(title: "My Challenges", text: "Follow your open challenges live and see how every past challenge turned out.")
                    VStack(spacing: 14) {
                        RecordCard()
                        Seg {
                            SegButton(on: model.tab == "open", action: { model.tab = "open" }) {
                                Text("Open challenges"); CountPill(n: open.count, off: open.isEmpty).scaleEffect(0.9)
                            }
                            SegButton(on: model.tab == "history", action: { model.tab = "history" }) {
                                Text("Challenge history"); CountPill(n: counts.all, off: true).scaleEffect(0.9)
                            }
                        }
                        .gutter()
                        if model.tab == "open" {
                            if open.isEmpty {
                                EmptyState(icon: .ticket, title: "No open challenges", text: "Go to Home and tap any point value to start a challenge. It takes two taps: pick a price, then tap Place challenge.") {
                                    Button("Find a game") { ui.go("home") }.buttonStyle(.btn(.primary))
                                }
                            } else {
                                if !liveNow.isEmpty {
                                    HStack(spacing: 6) { LiveTag(text: ""); Text("Live now").eyebrow(); CountPill(n: liveNow.count) }
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 4)
                                    ForEach(liveNow) { ChallengeCard(challenge: $0).gutter() }
                                }
                                if !otherOpen.isEmpty {
                                    Text("Upcoming").eyebrow().frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 4)
                                    ForEach(otherOpen) { ChallengeCard(challenge: $0).gutter() }
                                }
                            }
                        } else {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    Chip(label: "All", on: model.filter == "all", n: counts.all, sm: true) { model.filter = "all" }
                                    Chip(label: "Won", on: model.filter == "won", n: counts.won, sm: true) { model.filter = "won" }
                                    Chip(label: "Lost", on: model.filter == "lost", n: counts.lost, sm: true) { model.filter = "lost" }
                                    Chip(label: "Voided", on: model.filter == "void", n: counts.void, sm: true) { model.filter = "void" }
                                }
                                .padding(.horizontal, 16)
                            }
                            .scrollIndicators(.hidden)
                            if resolved.isEmpty {
                                EmptyState(icon: .chart, title: challenges.isEmpty ? "No resolved challenges yet" : "Nothing here yet",
                                           text: "Challenges move here within a few minutes of their game ending, marked Won, Lost or Voided.") {
                                    if challenges.isEmpty { Button("Place your first challenge") { ui.go("home") }.buttonStyle(.btn(.primary)) }
                                }
                            } else {
                                ForEach(resolved) { ChallengeCard(challenge: $0).gutter() }
                            }
                        }
                    }
                }
                .padding(.bottom, 116)
            }
            .scrollIndicators(.hidden)
            .onChange(of: ui.scrollTopToken) { proxy.scrollTo("top", anchor: .top) }
        }
    }
}

struct RecordCard: View {
    var body: some View {
        let st = Store.shared.myStats
        let wl = Store.shared.wallet
        let sports = st.bySport.sorted { ($0.value.w + $0.value.l, $1.key) > ($1.value.w + $1.value.l, $0.key) }.prefix(5)
        let maxAbs = max(1, sports.map { abs($0.value.net) }.max() ?? 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your record").font(.barlow(17, 800))
                Spacer()
                if !st.recent.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(st.recent.enumerated()), id: \.offset) { _, x in
                            Text(x).font(.barlow(10, 900)).foregroundStyle(x == "W" ? Theme.accent : Theme.loss)
                                .frame(width: 18, height: 18)
                                .background(x == "W" ? Theme.accentSoft : Theme.lossSoft, in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
            }
            RecordBig(items: [
                ("\(st.w)-\(st.l)\(st.v > 0 ? "-\(st.v)" : "")", "Won-Lost\(st.v > 0 ? "-Void" : "")", Theme.text),
                (st.pct.map { "\($0)%" } ?? "—", "Win rate", Theme.text),
                (Fmt.signed(st.net), "Total minutes", st.net > 0 ? Theme.accent : st.net < 0 ? Theme.loss : Theme.text),
            ])
            if !sports.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(sports), id: \.key) { k, v in
                        HStack(spacing: 10) {
                            Text(leagueShort(k)).foregroundStyle(Theme.text2).frame(width: 70, alignment: .leading)
                            Bar(pct: Double(abs(v.net)) / Double(maxAbs) * 100, color: v.net < 0 ? Theme.loss : Theme.accent, height: 8)
                            Text(Fmt.signedMin(v.net)).foregroundStyle(v.net > 0 ? Theme.accent : v.net < 0 ? Theme.loss : Theme.text2).frame(width: 60, alignment: .trailing)
                        }
                        .font(.barlow(12.5, 700))
                    }
                }
            }
            HStack(spacing: 0) {
                Text("Today: ")
                Text(Fmt.signedMin(wl.todayNet)).font(.barlow(13, 700)).foregroundStyle(wl.todayNet > 0 ? Theme.accent : wl.todayNet < 0 ? Theme.loss : Theme.text)
                Text(" so far")
            }
            .font(.barlow(13)).foregroundStyle(Theme.text2)
        }
        .card()
        .gutter()
    }
}

func leagueShort(_ id: String) -> String {
    switch id {
    case "pred": return "PRED"
    case "todo": return "TO-DO"
    case "combo": return "Combo"
    case "race": return "RACE"
    default: return Sim.leagues[id]?.short ?? id.uppercased()
    }
}

/// `.record-big`: three stat tiles.
struct RecordBig: View {
    var items: [(String, String, Color)]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                VStack(spacing: 0) {
                    Text(items[i].0).font(.display(26, 900)).monospacedDigit().foregroundStyle(items[i].2).lineLimit(1).minimumScaleFactor(0.6)
                    Text(items[i].1).font(.barlow(11, 700)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            }
        }
    }
}

/// An open challenge (live standing, live box, pledge row) or a resolved one (result and picks).
struct ChallengeCard: View {
    var challenge: Challenge
    var compact = false

    var body: some View {
        Group {
            if challenge.status == "open" { open } else { history }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    // MARK: Open

    private var open: some View {
        let single = challenge.picks.count == 1
        let st = ChallengeLogic.overallStanding(challenge)
        let sub = single ? "\(challenge.picks[0].marketLabel) · \(challenge.picks[0].matchup)" : "Every pick must win"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ChallengeText.title(challenge)).font(.barlow(16, 800))
                    Text(sub).font(.barlow(13)).foregroundStyle(Theme.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(PointValueMath.fmt(challenge.american)).font(.display(18, 800)).monospacedDigit().foregroundStyle(Theme.text2)
            }
            if challenge.boosted || challenge.multiplier > 1 {
                HStack(spacing: 6) {
                    if challenge.boosted { Tag("Boosted", .blue, icon: .bolt) }
                    if challenge.multiplier > 1 && !challenge.boosted { Tag("\(Fmt.mult(challenge.multiplier)) streak", .green) }
                }
            }
            if single {
                LiveBox(pick: challenge.picks[0])
                HStack { StandingTag(st: st); Spacer(); NowPointValue(pick: challenge.picks[0]) }
            } else {
                ForEach(Array(challenge.picks.enumerated()), id: \.offset) { i, l in
                    if i > 0 { DashedRule() }
                    let ls = ChallengeLogic.pickStanding(l)
                    HStack(alignment: .top, spacing: 10) {
                        PickDot(state: ls)
                        VStack(alignment: .leading, spacing: 6) {
                            VStack(alignment: .leading, spacing: 0) {
                                (Text(l.label) + Text(" \(PointValueMath.fmt(l.price))").font(.barlow(14.5, 600)).foregroundStyle(Theme.muted)).font(.barlow(14.5, 700))
                                Text("\(l.marketLabel) · \(l.matchup)").font(.barlow(12.5)).foregroundStyle(Theme.text2)
                            }
                            if l.result == "pending" { LiveBox(pick: l) } else { Text(l.final ?? "").font(.barlow(12.5, 700)).foregroundStyle(Theme.text2) }
                        }
                    }
                }
                HStack { StandingTag(st: st); Spacer(); if challenge.insured { Tag("Insured", color: Theme.purple) } }
            }
            HStack(spacing: 0) {
                pledgeCell("\(challenge.pledgeMinutes)", "Min pledged", Theme.text)
                VRule()
                pledgeCell("+\(ChallengeText.toWin(challenge))", "Min to win", Theme.accent)
                VRule()
                pledgeCell(Fmt.time(challenge.placedAt), "Placed \(Fmt.day(challenge.placedAt).lowercased())", Theme.text)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 9).padding(.horizontal, 4)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            if !compact && challenge.kind != "todo" { shareButton }
        }
    }

    private func pledgeCell(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 0) {
            Text(v).font(.display(18, 800)).monospacedDigit().foregroundStyle(c)
            Text(l).font(.barlow(11, 700)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var shareButton: some View {
        Button { UIState.shared.openSheet(.share(challenge.id)) } label: { BtnLabel("Share", icon: .share, iconSize: 16) }
            .buttonStyle(.btn(.ghost, .sm, full: true))
    }

    // MARK: History

    private var history: some View {
        let single = challenge.picks.count == 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        StatusPill(status: challenge.status)
                        if !single { Tag(challenge.kind == "todo" ? "To-do" : "Combo") }
                    }
                    Text(ChallengeText.title(challenge)).font(.barlow(16, 800))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(PointValueMath.fmt(challenge.american)).font(.display(16, 800)).foregroundStyle(Theme.text2)
                    switch challenge.status {
                    case "won": Text("+\(challenge.reward - challenge.pledgeMinutes) min").font(.display(22, 800)).foregroundStyle(Theme.accent)
                    case "lost": Text("−\(challenge.pledgeMinutes) min").font(.display(22, 800)).foregroundStyle(Theme.loss)
                    default: Text("\(challenge.insurancePaid == true ? "Insurance refund" : "Pledge returned") · \(challenge.pledgeMinutes) min").font(.barlow(13, 700)).foregroundStyle(Theme.text2)
                    }
                }
            }
            ForEach(Array(challenge.picks.enumerated()), id: \.offset) { i, l in
                if i > 0 { DashedRule() }
                HStack(alignment: .top, spacing: 10) {
                    PickDot(state: l.result)
                    VStack(alignment: .leading, spacing: 0) {
                        (Text(l.label) + Text(" \(PointValueMath.fmt(l.price))").font(.barlow(14.5, 600)).foregroundStyle(Theme.muted)).font(.barlow(14.5, 700))
                        (Text(l.kind == "todo" ? l.marketLabel : l.matchup) + Text(l.final == nil ? "" : " · ") + Text(l.final ?? "").font(.barlow(12.5, 700)))
                            .font(.barlow(12.5)).foregroundStyle(Theme.text2)
                    }
                }
            }
            if challenge.status == "void" {
                Note(.warn, icon: .info, challenge.kind == "todo" ? "" : "The game was postponed or cancelled, so this challenge was voided and your full pledge came back.")
            }
            HStack {
                Text("\(challenge.pledgeMinutes) min pledgedd · placed \(Fmt.day(challenge.placedAt)) \(Fmt.time(challenge.placedAt))")
                Spacer()
                Text("Resolved \(Fmt.ago(challenge.resolvedAt ?? challenge.placedAt))")
            }
            .font(.barlow(11.5, 700)).foregroundStyle(Theme.muted)
            if !compact && challenge.kind != "todo" { shareButton }
        }
    }
}

struct DashedRule: View {
    var body: some View {
        Line().stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
    }
    private struct Line: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
    }
}

struct PickDot: View {
    var state: String
    var body: some View {
        let icon: IconName = ["won": .check, "lost": .x, "void": .minus, "tie": .minus, "winning": .trend, "losing": .trend][state] ?? .clock
        let (bg, fg): (Color, Color) = {
            switch state {
            case "won": return (Theme.accent, Theme.accentInk)
            case "lost": return (Theme.loss, .white)
            case "void", "tie": return (Theme.muted, .white)
            case "winning": return (Theme.accentSoft, Theme.accent)
            case "losing": return (Theme.lossSoft, Theme.loss)
            default: return (Theme.raised, Theme.text2)
            }
        }()
        Icon(icon, 12).foregroundStyle(fg).frame(width: 20, height: 20).background(bg, in: Circle()).padding(.top, 1)
    }
}

struct StandingTag: View {
    var st: String
    var body: some View {
        let map: [String: (String, IconName, Color)] = [
            "winning": ("Winning right now", .trend, Theme.accent), "losing": ("Losing right now", .trend, Theme.loss),
            "even": ("Too close to call", .minus, Theme.text2), "upcoming": ("Not started", .clock, Theme.text2), "void": ("Voided", .x, Theme.text2),
        ]
        let (t, ic, c) = map[st] ?? map["upcoming"]!
        HStack(spacing: 5) { Icon(ic, 13); Text(t) }.font(.barlow(12, 800)).foregroundStyle(c)
    }
}

struct NowPointValue: View {
    var pick: Pick
    var body: some View {
        if pick.result == "pending" && pick.kind != "todo", let cur = Feed.currentSelection(pick.selId), let sel = cur.sel {
            if !cur.open {
                Tag("Challenging closed")
            } else if sel.price == pick.price && sel.line == pick.line {
                Tag("Point value now \(PointValueMath.fmt(sel.price))")
            } else {
                let better = PointValueMath.decimal(sel.price) < PointValueMath.decimal(pick.price)
                let line = sel.market == "margin" || sel.market == "total" ? "\(PointValueMath.fmtLine(sel.line ?? 0, signed: sel.market == "margin")) " : ""
                Tag("Point value now \(line)\(PointValueMath.fmt(sel.price))", better ? .green : .red)
            }
        }
    }
}

/// Live score and key stats for a pick, so users can follow a challenge without leaving My Challenges.
struct LiveBox: View {
    var pick: Pick

    var body: some View {
        content
            .padding(.vertical, 10).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    @ViewBuilder private var content: some View {
        if pick.kind == "race" {
            let race = Races.shared.get(pick.raceId)
            let horse = Races.shared.horse(pick.horseId)
            let status = race == nil ? "Race result unavailable" : race!.status == "open" ? "Challenges open" : race!.status == "running" ? "Race in progress" : "Race #\(race!.number) finished"
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(horse.name) · \(pick.matchup)").font(.barlow(13, 700))
                    Spacer()
                    if race?.status == "running" { LiveTag(text: status.uppercased()) } else { Text(status).font(.barlow(13)).foregroundStyle(Theme.text2) }
                }
                if race?.status == "running", let w = race?.winnerId {
                    Text("Current leader: \(Races.shared.horse(w).name)").font(.barlow(13)).foregroundStyle(Theme.text2)
                }
            }
        } else if let id = pick.gameId, let g = Feed.game(id) {
            Button { GameModel.open(g.id) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    head(g)
                    let stats = g.eventID != nil ? Array(LiveFeed.shared.stats(g).prefix(3)) : []
                    if !stats.isEmpty && g.state == .live {
                        HStack(spacing: 12) {
                            ForEach(stats, id: \.self) { r in
                                (Text("\(r.label) ") + Text("\(r.awayValue)–\(r.homeValue)").foregroundStyle(Theme.text).font(.barlow(12, 700)))
                            }
                        }
                        .font(.barlow(12, 600)).foregroundStyle(Theme.text2)
                    }
                }
            }
            .buttonStyle(.press)
            .onAppear { if g.eventID != nil { LiveFeed.shared.loadDetails(g.id) } }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(pick.matchup.isEmpty ? "Sports game" : pick.matchup).font(.barlow(13, 700))
                Text("Loading the latest score…").font(.barlow(13)).foregroundStyle(Theme.text2)
            }
        }
    }

    @ViewBuilder private func head(_ g: Game) -> some View {
        switch g.state {
        case .live, .final:
            HStack(spacing: 8) {
                TeamBadge(team: g.away, size: 22)
                Text(g.away.abbr)
                Text("\(g.awayScore)").font(.display(20, 900)).monospacedDigit()
                Text("–").foregroundStyle(Theme.muted)
                Text("\(g.homeScore)").font(.display(20, 900)).monospacedDigit()
                Text(g.home.abbr)
                TeamBadge(team: g.home, size: 22)
                Spacer(minLength: 0)
                if g.state == .live { HStack(spacing: 4) { LiveTag(); Text(g.clock) }.font(.barlow(13)) }
                else { Text(g.statusText).font(.barlow(13)).foregroundStyle(Theme.text2) }
            }
            .font(.barlow(14, 700)).lineLimit(1)
        case .postponed, .canceled:
            HStack { Text("\(g.away.name) @ \(g.home.name)").font(.barlow(14, 700)); Spacer(); Tag("Postponed", .yellow) }
        case .scheduled:
            HStack(spacing: 8) {
                TeamBadge(team: g.away, size: 22)
                Text("\(g.away.abbr) @ \(g.home.abbr)")
                TeamBadge(team: g.home, size: 22)
                Spacer(minLength: 0)
                Text("\(Fmt.day(g.start)) \(Fmt.time(g.start)) · in \(Fmt.inTime(g.start - TO.now()))").font(.barlow(13)).foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            }
            .font(.barlow(14, 700))
        }
    }
}

// MARK: - Share

struct ShareSheet: View {
    var challengeId: String
    @State private var image: UIImage?

    var body: some View {
        let challenge = Store.shared.data?.challenges.first { $0.id == challengeId }
        SheetFrame("Share challenge", close: { UIState.shared.closeSheet(.share(challengeId)) }) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                    .accessibilityLabel("Challenge card image showing the teams, pick, point value and pledge")
            } else {
                Text("Creating image…").font(.barlow(13)).foregroundStyle(Theme.text2).card()
            }
            Text("Save the image and post it anywhere.").font(.barlow(13)).foregroundStyle(Theme.text2)
        } foot: {
            if let image, let challenge {
                ShareLink(item: Image(uiImage: image), subject: Text("My TimeOut challenge"), message: Text(ShareCard.text(challenge)),
                          preview: SharePreview("My TimeOut challenge", image: Image(uiImage: image))) {
                    BtnLabel("Share image", icon: .share)
                }
                .buttonStyle(.btn(.primary, full: true))
            }
            Button {
                if let challenge, Clipboard.copy(ShareCard.text(challenge)) { UIState.shared.toast(.win, "Challenge copied", "Paste it into any chat.") }
            } label: { BtnLabel("Copy challenge text", icon: .copy, iconSize: 16) }
            .buttonStyle(.btn(.ghost, full: true))
        }
        .task {
            if let challenge { image = ShareCard.render(challenge) }
        }
    }
}

/// The 1080×1350 share image (teams, pick, point value and pledge), drawn like the web demo's canvas.
enum ShareCard {
    static func text(_ challenge: Challenge) -> String {
        let picks = challenge.picks.map { "\($0.label) (\(PointValueMath.fmt($0.price))) · \($0.matchup)" }.joined(separator: "\n")
        return "My TimeOut \(challenge.picks.count > 1 ? "combo" : "challenge"):\n\(picks)\nOdds \(PointValueMath.fmt(challenge.american)) · \(challenge.pledgeMinutes) min of screen time to earn \(ChallengeText.toWin(challenge)) min"
    }

    static func render(_ challenge: Challenge) -> UIImage {
        let W: CGFloat = 1080, H: CGFloat = 1350
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: format).image { ctx in
            let c = ctx.cgContext
            func ui(_ hex: String) -> UIColor { UIColor(Color(hex: hex)) }
            func display(_ size: CGFloat, _ weight: Int = 900, italic: Bool = false) -> UIFont {
                let name = weight >= 900 ? (italic ? "BarlowCondensed-BlackItalic" : "BarlowCondensed-Black") : (italic ? "BarlowCondensed-ExtraBoldItalic" : "BarlowCondensed-ExtraBold")
                return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .black)
            }
            func body(_ size: CGFloat, _ weight: Int = 700) -> UIFont {
                UIFont(name: weight >= 800 ? "Barlow-ExtraBold" : weight >= 700 ? "Barlow-Bold" : "Barlow-SemiBold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
            }
            /// Draws text with its baseline at y (canvas fillText semantics).
            func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ font: UIFont, _ color: UIColor, align: NSTextAlignment = .left) -> CGFloat {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let size = (s as NSString).size(withAttributes: attrs)
                let ox = align == .center ? x - size.width / 2 : align == .right ? x - size.width : x
                (s as NSString).draw(at: CGPoint(x: ox, y: y - font.ascender), withAttributes: attrs)
                return size.width
            }
            func width(_ s: String, _ font: UIFont) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
            func wrap(_ s: String, _ x: CGFloat, _ yIn: CGFloat, _ maxW: CGFloat, _ lineH: CGFloat, _ maxLines: Int, _ font: UIFont, _ color: UIColor) -> CGFloat {
                let words = s.split(separator: " ").map(String.init)
                var line = "", lines = 0, y = yIn
                var i = 0
                while i < words.count {
                    let test = line.isEmpty ? words[i] : "\(line) \(words[i])"
                    if width(test, font) > maxW && !line.isEmpty {
                        _ = text(line, x, y, font, color); y += lineH; line = words[i]; lines += 1
                        if lines >= maxLines - 1 { line = words[i...].joined(separator: " "); break }
                    } else { line = test }
                    i += 1
                }
                _ = text(line, x, y, font, color)
                return y + lineH
            }

            ui("#0a0d12").setFill(); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor(red: 34 / 255, green: 214 / 255, blue: 110 / 255, alpha: 0.28).cgColor, UIColor(red: 34 / 255, green: 214 / 255, blue: 110 / 255, alpha: 0).cgColor] as CFArray,
                                  locations: [0, 1])!
            c.drawRadialGradient(glow, startCenter: CGPoint(x: W * 0.85, y: 60), startRadius: 10, endCenter: CGPoint(x: W * 0.85, y: 60), endRadius: 700, options: [])

            // Wordmark
            let tw = text("Time", 80, 150, display(84, 900, italic: true), ui("#f2f5f9"))
            _ = text("Out", 80 + tw, 150, display(84, 900, italic: true), ui("#22d66e"))
            _ = text("@\(Store.shared.account?.username ?? "")'s challenge", 80, 200, body(30), ui("#8c96a8"))

            // Status pill
            let status = challenge.status.uppercased()
            let pillColor = ["OPEN": "#1d2430", "WON": "#22d66e", "LOST": "#ff5a5f", "VOID": "#5e687a", "TIE": "#5e687a"][status] ?? "#1d2430"
            let pw = width(status, body(30, 900)) + 48
            ui(pillColor).setFill()
            UIBezierPath(roundedRect: CGRect(x: W - 80 - pw, y: 104, width: pw, height: 56), cornerRadius: 28).fill()
            _ = text(status, W - 80 - pw + 24, 143, body(30, 900), status == "WON" ? ui("#03140a") : .white)

            // Card
            let card = UIBezierPath(roundedRect: CGRect(x: 60, y: 260, width: W - 120, height: 800), cornerRadius: 44)
            ui("#141922").setFill(); card.fill()
            ui("#283141").setStroke(); card.lineWidth = 3; card.stroke()

            var y: CGFloat = 340
            if challenge.picks.count == 1 && challenge.picks[0].kind == "game", let g = challenge.picks[0].gameId.flatMap({ Feed.game($0) }) {
                func disc(_ team: Team, _ cx: CGFloat) {
                    let circle = UIBezierPath(arcCenter: CGPoint(x: cx, y: y + 90), radius: 90, startAngle: 0, endAngle: .pi * 2, clockwise: true)
                    ui(team.color).setFill(); circle.fill()
                    UIColor.white.withAlphaComponent(0.15).setStroke(); circle.lineWidth = 6; circle.stroke()
                    _ = text(team.abbr, cx, y + 112, display(team.abbr.count > 3 ? 52 : 64), .white, align: .center)
                    _ = text(team.name, cx, y + 240, body(34), ui("#f2f5f9"), align: .center)
                }
                disc(g.away, 300); disc(g.home, W - 300)
                _ = text(g.state == .live || g.state == .final ? "\(g.awayScore) – \(g.homeScore)" : "@", W / 2, y + 112, display(60), ui("#5e687a"), align: .center)
                let sub = g.state == .live ? "LIVE · \(g.clock)" : g.state == .final ? g.statusText : g.state == .postponed ? "Postponed" : "\(Fmt.day(g.start)) \(Fmt.time(g.start))"
                _ = text(sub, W / 2, y + 160, body(26), ui("#8c96a8"), align: .center)
                y += 320
                ui("#283141").setFill(); c.fill(CGRect(x: 110, y: y - 20, width: W - 220, height: 3))
                _ = text("\(challenge.picks[0].marketLabel.uppercased()) · MY PICK", 110, y + 40, body(30), ui("#8c96a8"))
                y = wrap(challenge.picks[0].label, 110, y + 130, W - 220, 90, 2, display(88), ui("#f2f5f9"))
            } else {
                _ = text(challenge.picks.count > 1 ? "\(challenge.picks.count)-PICK COMBO" : "MY PICK", 110, y + 10, body(30), ui("#8c96a8"))
                y += 80
                for l in challenge.picks {
                    _ = text(l.label, 110, y + 30, display(60), ui("#f2f5f9"))
                    y = wrap("\(l.marketLabel) · \(l.matchup)", 110, y + 76, W - 360, 34, 2, body(28, 600), ui("#8c96a8"))
                    _ = text(PointValueMath.fmt(l.price), W - 110, y - 60, display(50), ui("#22d66e"), align: .right)
                    y += 30
                }
            }

            // Bottom stats
            let by: CGFloat = 900
            ui("#283141").setFill(); c.fill(CGRect(x: 110, y: by - 30, width: W - 220, height: 3))
            func col(_ label: String, _ value: String, _ x: CGFloat, _ color: String) {
                _ = text(label, x, by + 20, body(26), ui("#8c96a8"))
                _ = text(value, x, by + 100, display(76), ui(color))
            }
            col("VALUE", PointValueMath.fmt(challenge.american), 110, "#f2f5f9")
            col("PLEDGE", "\(challenge.pledgeMinutes) min", 420, "#f2f5f9")
            col(challenge.status == "lost" ? "LOST" : challenge.status == "won" ? "WON" : "TO WIN",
                challenge.status == "lost" ? "−\(challenge.pledgeMinutes)" : "+\(challenge.status == "won" ? challenge.reward - challenge.pledgeMinutes : ChallengeText.toWin(challenge))", 730,
                challenge.status == "lost" ? "#ff5a5f" : "#22d66e")

            _ = text("Challenging screen time, not money.", W / 2, 1160, body(30, 600), ui("#8c96a8"), align: .center)
            _ = text("TimeOut", W / 2, 1230, display(40, 900, italic: true), ui("#22d66e"), align: .center)
        }
    }
}
