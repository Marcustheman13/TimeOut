import SwiftUI

/// Home's view state (the web demo keeps `feedDay` in home.js).
@Observable
final class HomeModel {
    static let shared = HomeModel()
    /// Which day the board shows: 0 = today, 1 = tomorrow. Live games are always today.
    var feedDay = 0

    var followed: [String] {
        let s = Store.shared.data?.settings.sports ?? []
        return s.isEmpty ? Sim.realLeagues : s
    }

    var activeFilter: String {
        let f = Store.shared.data?.feedFilter ?? "all"
        return ["pred", "todo", "sim"].contains(f) ? "all" : f
    }

    var activeDay: Int { activeFilter == "live" ? 0 : feedDay }

    func boardGames(_ day: Int? = nil) -> [Game] {
        let leagues = Sim.leagueOrder.filter { $0 != "sim" && followed.contains($0) }
        return Feed.board(TO.now(), day: day ?? activeDay, leagues: leagues).filter { !$0.simulated && $0.league != "sim" }
    }

    func dayLabel(_ offset: Int) -> String {
        if offset == 0 { return "Today" }
        if offset == 1 { return "Tomorrow" }
        let t = TO.now() + Double(offset) * TO.DAY
        let c = Calendar.current.dateComponents([.month, .day], from: TO.date(t))
        return "\(Fmt.weekday(t)) \(c.month ?? 0)/\(c.day ?? 0)"
    }

    func setDay(_ day: Int) {
        feedDay = day
        LiveFeed.shared.setViewingDay(activeDay)
        UIState.shared.scrollToFilters()
    }

    func setFilter(_ f: String) {
        Store.shared.setFeedFilter(f)
        LiveFeed.shared.setViewingDay(activeDay)
        UIState.shared.scrollToFilters()
    }

    static func myOpenBets(on ref: String) -> [Bet] {
        (Store.shared.data?.bets ?? []).filter { $0.status == "open" && $0.legs.contains { $0.gameId == ref || $0.predId == ref || $0.raceId == ref } }
    }

    static func sportsOnly(_ bet: Bet) -> Bool {
        bet.kind == "race" || (bet.kind == "sports" && bet.legs.allSatisfy { leg in leg.gameId != nil && Feed.game(leg.gameId!)?.league != "sim" })
    }
}

struct HomeView: View {
    private var store: Store { .shared }
    private var live: LiveFeed { .shared }
    private var home: HomeModel { .shared }
    private var ui: UIState { .shared }
    private var app: AppModel { .shared }

    var body: some View {
        let _ = live.version
        let _ = app.tick
        let wl = store.wallet
        let games = home.boardGames()
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
                    Color.clear.frame(height: 0).id("top")
                    WalletCard(wl: wl)
                    if wl.appsLocked { AppLockBanner(wl: wl) }
                    StatusStrip(wl: wl)
                    OpenBetsStrip()
                    Section {
                        VStack(spacing: 12) {
                            BuildParlayControl()
                            if live.offline {
                                Note(.blue, icon: .info, "Live ESPN odds can't be reached here, so these are simulated games with real team names. Everything else works the same.").gutter()
                            }
                            FeedList(games: games)
                        }
                    } header: {
                        FilterBar(games: games).id("filters")
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 116)
            }
            .scrollIndicators(.hidden)
            .refreshable { live.refresh(force: true) }
            .onChange(of: ui.scrollTopToken) { proxy.scrollTo("top", anchor: .top) }
            .onChange(of: ui.scrollFilterToken) { withAnimation { proxy.scrollTo("filters", anchor: .top) } }
        }
        .onAppear { live.setViewingDay(home.activeDay) }
    }
}

// MARK: - Wallet header

struct WalletCard: View {
    var wl: WalletView

    var body: some View {
        if wl.lockedOut || wl.balance <= 0 {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) { Icon(.lock, 14); Text("OUT OF BETTING MINUTES").font(.barlow(12, 900)).tracking(0.72) }
                    .foregroundStyle(Theme.loss)
                Text("Betting is locked. It reopens at midnight.").font(.barlow(16, 700)).padding(.top, 8)
                Countdown(target: TO.nextMidnight()).font(.display(46, 900)).padding(.top, 6)
                Text("Your open bets still settle and count toward tomorrow's phone time.").font(.barlow(13)).foregroundStyle(Theme.text2).padding(.top, 4)
                WalletStats(wl: wl)
            }
            .card(16, border: Theme.loss.opacity(0.45))
            .padding(.top, 4).gutter()
        } else {
            let pct = min(100, Double(wl.balance) / Double(Rules.daily + wl.bonusToday) * 100)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Betting balance today").eyebrow()
                            if wl.bonusToday > 0 { Text("+\(wl.bonusToday) min \(wl.tier.title) bonus included").font(.barlow(11.5, 700)).foregroundStyle(Theme.accent) }
                        }
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text("\(wl.balance)").font(.display(54, 900)).monospacedDigit()
                            Text("min").font(.display(22, 700)).opacity(0.85)
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Resets in").eyebrow(Theme.muted)
                        Countdown(target: TO.nextMidnight()).font(.display(19, 700)).foregroundStyle(Theme.text2)
                    }
                }
                Bar(pct: pct).padding(.top, 12)
                WalletStats(wl: wl)
                Button { HowItWorks.open() } label: {
                    HStack(spacing: 6) { Icon(.info, 14); Text("You bet with tomorrow's phone time. How it works") }
                        .font(.barlow(12.5, 600)).foregroundStyle(Theme.text2)
                }
                .buttonStyle(.press)
                .padding(.top, 12)
            }
            .card(16)
            .padding(.top, 4).gutter()
        }
    }
}

struct WalletStats: View {
    var wl: WalletView
    var body: some View {
        let s = Store.shared.data?.settings
        let delta = wl.tomorrowLimit - Rules.daily
        let tColor = delta > 0 ? Theme.accent : delta < 0 ? Theme.loss : Theme.text
        let pColor = wl.appsLocked ? Theme.loss : wl.phoneLeft <= (s?.lowWarn ?? 10) ? Theme.warn : Theme.text
        VStack(spacing: 0) {
            HRule()
            HStack(spacing: 0) {
                stat(s?.enforce == true ? "\(wl.phoneLeft) min" : "Off", "Phone time left", pColor)
                VRule()
                stat("\(wl.atRisk) min", "In open bets", wl.atRisk > 0 ? Theme.warn : Theme.text)
                VRule()
                stat("\(wl.tomorrowLimit) min", "Tomorrow's limit", tColor)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
        }
        .padding(.top, 14)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.display(20, 800)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.barlow(11, 700)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AppLockBanner: View {
    var wl: WalletView
    var body: some View {
        Button { SettingsModel.open("screentime") } label: {
            HStack(spacing: 12) {
                Icon(.phone, 22).foregroundStyle(Theme.loss)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your locked apps are blocked").font(.barlow(15, 700)).foregroundStyle(Theme.loss)
                    Text("You've used all \(wl.todayLimit) min of today's phone time. Emergency unlocks are in Settings.").font(.barlow(13)).foregroundStyle(Theme.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon(.chevR, 16).foregroundStyle(Theme.text)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(Theme.lossSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.loss.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.press)
        .gutter()
    }
}

struct StatusStrip: View {
    var wl: WalletView
    var body: some View {
        Button { SettingsModel.open("status") } label: {
            // The row clips at the edge like the web's `overflow: hidden`, without widening the card.
            Color.clear.frame(maxWidth: .infinity).frame(height: 24).overlay(alignment: .leading) { strip }
            .clipped()
            .overlay(alignment: .trailing) {
                Icon(.chevR, 16).foregroundStyle(Theme.muted).padding(.leading, 6).background(Theme.surface)
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.press)
        .gutter()
    }

    private var strip: some View {
            HStack(spacing: 12) {
                TierBadge(tierId: wl.tier.id)
                HStack(spacing: 4) { Icon(.flame, 14); Text(wl.streak > 0 ? "\(wl.streak)-day streak" : "No streak yet") }
                    .font(.barlow(12.5, 700)).foregroundStyle(wl.streak > 0 ? Theme.warn : Theme.muted).fixedSize()
                if wl.multiplier > 1 {
                    HStack(spacing: 4) { Icon(.trend, 14); Text("\(Fmt.mult(wl.multiplier)) wins") }.font(.barlow(12.5, 700)).foregroundStyle(Theme.accent).fixedSize()
                }
                if wl.boostsLeft > 0 {
                    HStack(spacing: 4) { Icon(.bolt, 14); Text("\(wl.boostsLeft) boost\(wl.boostsLeft == 1 ? "" : "s")") }.font(.barlow(12.5, 700)).foregroundStyle(Theme.blue).fixedSize()
                }
            }
            .fixedSize()
    }
}

struct OpenBetsStrip: View {
    var body: some View {
        let open = (Store.shared.data?.bets ?? []).filter { $0.status == "open" && HomeModel.sportsOnly($0) }.sorted { $0.placedAt > $1.placedAt }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("Open bets").font(.barlow(17, 800))
                    CountPill(n: open.count, off: open.isEmpty)
                }
                Spacer(minLength: 0)
                if !open.isEmpty {
                    Button("See all") { UIState.shared.go("bets") }.font(.barlow(13.5, 700)).foregroundStyle(Theme.accent).buttonStyle(.press)
                }
            }
            .gutter()
            if open.isEmpty {
                Text("No open bets. Tap any odds below to start one.").font(.barlow(13)).foregroundStyle(Theme.text2)
                    .card(12).gutter()
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { ForEach(open) { MiniBet(bet: $0) } }.padding(.horizontal, 16).padding(.bottom, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct MiniBet: View {
    var bet: Bet
    var body: some View {
        let title = bet.kind == "todo" ? "To-do parlay (\(bet.legs.count))" : bet.legs.count > 1 ? "\(bet.legs.count)-pick parlay" : (bet.legs.first?.label ?? "")
        let leg = bet.legs.first { $0.result == "pending" } ?? bet.legs[0]
        let win = jsRoundInt(Double(bet.stake) * bet.decimal) - bet.stake
        Button { UIState.shared.go("bets") } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.barlow(14, 800)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(OddsMath.fmt(bet.american)).font(.display(15, 800)).foregroundStyle(Theme.text2)
                }
                line(leg).font(.barlow(13, 600)).foregroundStyle(Theme.text2).lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text("\(bet.stake) min").foregroundStyle(Theme.text2)
                    Icon(.chevR, 12)
                    if win > 0 { Text("win \(BetText.toWin(bet)) min").foregroundStyle(Theme.accent) }
                }
                .font(.barlow(13, 700))
            }
            .padding(12)
            .frame(width: 222, alignment: .leading)
            .frame(minHeight: 96)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.press)
    }

    @ViewBuilder private func line(_ leg: Leg) -> some View {
        if bet.kind == "todo" {
            Text("\(bet.legs.filter { $0.result == "won" }.count)/\(bet.legs.count) done · due midnight")
        } else if leg.kind == "pred" {
            Text("Resolves in \(Fmt.inTime((leg.start ?? 0) - TO.now()))")
        } else if leg.kind == "race" {
            let race = Races.shared.get(leg.raceId)
            if race?.status == "running" {
                HStack(spacing: 4) { LiveTag(); Text("Virtual Race #\(race!.number)") }
            } else {
                Text("Virtual Race #\((leg.raceId ?? "").replacingOccurrences(of: "race-", with: "")) · \(race?.status == "final" ? "Finished" : "Starting soon")")
            }
        } else if let g = leg.gameId.flatMap({ Feed.game($0) }) {
            switch g.state {
            case .live: HStack(spacing: 4) { LiveTag(); Text("\(g.away.abbr) \(g.awayScore) – \(g.home.abbr) \(g.homeScore) · \(g.clock)") }
            case .scheduled: Text("\(g.away.abbr) @ \(g.home.abbr) · \(Fmt.time(g.start))")
            default: Text("\(g.away.abbr) \(g.awayScore) – \(g.home.abbr) \(g.homeScore) · \(g.statusText)")
            }
        } else {
            Text("Loading the latest score…")
        }
    }
}

// MARK: - Filters

struct FilterBar: View {
    var games: [Game]
    private var home: HomeModel { .shared }
    private var live: LiveFeed { .shared }

    var body: some View {
        let f = home.activeFilter
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Chip(label: "Live", on: f == "live", n: games.filter { $0.state == .live }.count, icon: .radio) { home.setFilter("live") }
                    Chip(label: "All", on: f == "all", icon: .grid) { home.setFilter("all") }
                    ForEach(Sim.leagueOrder.filter { $0 != "sim" && home.followed.contains($0) }, id: \.self) { l in
                        Chip(label: l == "ncaaf" ? "College Football" : Sim.leagues[l]!.short, on: f == l,
                             n: games.filter { $0.league == l && $0.state != .final }.count) { home.setFilter(l) }
                    }
                    Chip(label: "Edit", icon: .sliders, dashed: true) { SettingsModel.open("sports") }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            DayBar().padding(.top, 10)
            if (f == "ncaaf" || f == "all") && !live.offline {
                Text("COLLEGE FOOTBALL").font(.barlow(11, 800)).tracking(0.55).foregroundStyle(Theme.muted)
                    .padding(.top, 9).padding(.bottom, 4).gutter()
                Menu {
                    Picker("College football conference", selection: Binding(get: { live.cfbGroup }, set: { live.setGroup($0) })) {
                        ForEach(LiveFeed.cfbGroups, id: \.0) { Text($0.1).tag($0.0) }
                    }
                } label: {
                    HStack {
                        Text(LiveFeed.cfbGroups.first { $0.0 == live.cfbGroup }?.1 ?? "All College Football").font(.barlow(15, 700))
                        Spacer()
                        Icon(.chevD, 16).foregroundStyle(Theme.text2)
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10).frame(height: 38)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .accessibilityLabel("College football conference")
                .gutter()
            }
        }
        .padding(.vertical, 10)
        .background(Theme.bg)
    }
}

/// Today and tomorrow. Counts are games still to be played that day, in the sports being shown.
struct DayBar: View {
    var inset = true
    private var home: HomeModel { .shared }
    private var live: LiveFeed { .shared }

    var body: some View {
        let f = home.activeFilter
        if f != "live" && !live.offline {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(0...LiveFeed.upcomingDays, id: \.self) { i in
                        let n = home.boardGames(i).filter { $0.state != .final && (f == "all" || $0.league == f) }.count
                        Chip(label: home.dayLabel(i), on: home.feedDay == i, n: n, sm: true) { home.setDay(i) }
                    }
                }
                .padding(.horizontal, inset ? 16 : 0)
            }
            .scrollIndicators(.hidden)
            .accessibilityLabel("Pick a day")
        }
    }
}

struct BuildParlayControl: View {
    private var slip: Slip { .shared }
    var body: some View {
        if !slip.parlayMode {
            Button { slip.toggleParlayMode() } label: {
                HStack(spacing: 12) {
                    Icon(.ticket, 18).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Build parlay").font(.barlow(14, 700))
                        Text("Select picks from multiple games").font(.barlow(12)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Icon(.chevR, 18).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.text)
                .padding(.vertical, 10).padding(.horizontal, 14)
                .frame(minHeight: 58)
                .background(LinearGradient(colors: [Theme.accent.opacity(0.13), Theme.accent.opacity(0.05)], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.press)
            .gutter()
        } else {
            HStack(spacing: 12) {
                LrIcon(icon: .ticket, size: 34, iconSize: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose your parlay picks").font(.barlow(14, 700))
                    Text("\(slip.legs.count) of \(Rules.maxLegs) picks · choose one bet per game").font(.barlow(12)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { slip.toggleParlayMode() }.font(.barlow(13.5, 700)).foregroundStyle(Theme.accent).buttonStyle(.press)
            }
            .padding(.vertical, 10).padding(.horizontal, 14)
            .frame(minHeight: 58)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .gutter()
        }
    }
}

// MARK: - Feed

struct LeagueHead: View {
    var league: String
    var count: String
    var inset = true
    var body: some View {
        HStack(spacing: 8) {
            Text(Sim.leagues[league]?.title ?? league).font(.barlow(18, 800))
            if Sim.leagues[league]?.simulated == true { Tag("Simulated") }
            Spacer()
            Text(count).font(.barlow(12, 600)).foregroundStyle(Theme.muted)
        }
        .padding(.top, 6)
        .padding(.horizontal, inset ? 16 : 0)
    }
}

struct FeedList: View {
    var games: [Game]
    private var home: HomeModel { .shared }

    var body: some View {
        let f = home.activeFilter
        let list = f == "live" ? games.filter { $0.state == .live } : f == "all" ? games : games.filter { $0.league == f }
        if list.isEmpty {
            EmptyBoard(filter: f)
        } else if f == "all" {
            ForEach(Sim.leagueOrder.filter { l in l != "sim" && list.contains { $0.league == l } }, id: \.self) { l in
                let lg = list.filter { $0.league == l }
                LeagueHead(league: l, count: "\(lg.filter { $0.state == .live }.count) live · \(lg.count) games")
                ForEach(lg) { GameCard(game: $0).gutter() }
            }
        } else {
            ForEach(list) { GameCard(game: $0).gutter() }
        }
    }
}

struct EmptyBoard: View {
    var filter: String
    private var home: HomeModel { .shared }
    private var live: LiveFeed { .shared }

    var body: some View {
        let day = home.activeDay
        let when = day == 0 ? "today" : day == 1 ? "tomorrow" : "on \(home.dayLabel(day))"
        let loading = day > 0 && live.upcomingIsLoading
        let title = filter == "live" ? "No live games right now" : loading ? "Loading the schedule…" : "Sorry, no games are happening for this sport \(when)."
        let next: Int? = filter != "live" && !loading
            ? (0...LiveFeed.upcomingDays).first { i in i != day && home.boardGames(i).contains { filter == "all" || $0.league == filter } }
            : nil
        if live.failed {
            EmptyState(icon: .alert, title: "Sports couldn’t load", text: "Check your connection and try again.") {
                Button("Try again") { live.refresh(force: true) }.buttonStyle(.btn(.primary))
            }
        } else {
            EmptyState(icon: loading ? .clock : .target, title: title, text: filter == "live" ? "Check back when a game is underway." : nil) {
                if let next {
                    Button("See games \(next == 1 ? "tomorrow" : "on \(home.dayLabel(next))")") { home.setDay(next) }.buttonStyle(.btn(.primary))
                }
            }
        }
    }
}

/// Game status line: LIVE + clock, start time, or final/postponed.
struct GameStatusText: View {
    var g: Game
    var body: some View {
        switch g.state {
        case .live:
            HStack(spacing: 8) { LiveTag(); Text(g.clock).foregroundStyle(Theme.text) }
        case .scheduled:
            let mins = jsRoundInt((g.start - TO.now()) / TO.MIN)
            HStack(spacing: 4) {
                Text("\(Fmt.day(g.start)) · \(Fmt.time(g.start))")
                if mins <= 60 { Text("· starts in \(mins < 1 ? "<1" : String(mins)) min").foregroundStyle(Theme.muted) }
            }
        case .final:
            Text(g.statusText)
        case .canceled:
            HStack(spacing: 6) { Icon(.alert, 13); Text("Canceled · all bets voided, stakes returned") }.foregroundStyle(Theme.warn)
        case .postponed:
            HStack(spacing: 6) { Icon(.alert, 13); Text("Postponed · all bets voided, stakes returned") }.foregroundStyle(Theme.warn)
        }
    }
}

struct GameCard: View {
    var game: Game
    private var live: LiveFeed { .shared }

    var body: some View {
        let _ = live.version
        let g = game
        let o = Feed.odds(g.id)
        let bettable = g.state == .live || g.state == .scheduled
        let mine = HomeModel.myOpenBets(on: g.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                GameStatusText(g: g).lineLimit(1)
                if o.suspended && g.state == .live { Tag("Betting closed", icon: .lock) }
                Spacer(minLength: 0)
                Text(g.otherConferenceLive ? "LIVE · \(g.conferenceName.isEmpty ? "UNRANKED" : g.conferenceName)" : g.simulated ? "SIMULATED" : Sim.leagues[g.league]?.short ?? "")
                    .font(.barlow(11, 800)).tracking(0.44).foregroundStyle(Theme.muted)
            }
            .font(.barlow(12, 700))
            .foregroundStyle(Theme.text2)
            .frame(minHeight: 18)
            .padding(.bottom, 8)

            if bettable {
                if g.eventID != nil { espnBody(g, o) } else { simBody(g, o) }
            } else {
                VStack(spacing: 0) {
                    finalRow(g.away, g.awayScore, g.awayScore > g.homeScore, g)
                    finalRow(g.home, g.homeScore, g.homeScore > g.awayScore, g)
                }
                if g.state == .postponed {
                    Note(.warn, icon: .info, "This game was postponed. Every bet on it is void and the full stake goes back to the bettor.").padding(.top, 6)
                }
            }

            HStack {
                if !mine.isEmpty {
                    HStack(spacing: 4) { Icon(.ticket, 14); Text("You have \(mine.count == 1 ? "a bet" : "\(mine.count) bets") on this game") }
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 0)
                Button { GameModel.open(g.id) } label: {
                    HStack(spacing: 6) { Text("Stats & all odds"); Icon(.chevR, 14) }.font(.barlow(12.5, 700)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.press)
            }
            .font(.barlow(12, 700))
            .padding(.top, 8)
        }
        .padding(.top, 12).padding(.bottom, 12).padding(.leading, 12).padding(.trailing, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func finalRow(_ team: Team, _ score: Int, _ won: Bool, _ g: Game) -> some View {
        Button { GameModel.open(g.id) } label: {
            HStack(spacing: 8) {
                TeamBadge(team: team)
                Text(team.name).font(.barlow(14.5, 700)).foregroundStyle(won ? Theme.text : Theme.text2).lineLimit(1)
                Spacer(minLength: 0)
                if g.state == .final {
                    Text("\(score)").font(.display(23, 900)).monospacedDigit().foregroundStyle(won ? Theme.text : Theme.text2).padding(.trailing, 2)
                }
            }
            .frame(height: 46)
        }
        .buttonStyle(.press)
    }

    /// ESPN layout: teams and scores on the left, a 2-column grid of every price on the right.
    @ViewBuilder private func espnBody(_ g: Game, _ o: OddsBoard) -> some View {
        let picks: [(Selection?, String, Bool)] = {
            var p: [(Selection?, String, Bool)] = [
                (o.spread.first { $0.side == "away" }, "Away · \(g.away.abbr)", false),
                (o.spread.first { $0.side == "home" }, "Home · \(g.home.abbr)", false),
                (o.total.first { $0.side == "over" }, "Over", false),
                (o.total.first { $0.side == "under" }, "Under", false),
                (o.moneyline.first { $0.side == "away" }, "Away ML · \(g.away.abbr)", true),
                (o.moneyline.first { $0.side == "home" }, "Home ML · \(g.home.abbr)", true),
            ]
            if g.sport == "soccer" { p.append((o.moneyline.first { $0.side == "draw" }, "Draw", true)) }
            return p
        }()
        FrColumns(left: 0.9, right: 1.2, minLeft: 112, spacing: 9) {
            VStack(spacing: 0) {
                liveTeam(g, g.away, g.awayScore, g.homeScore, "away")
                liveTeam(g, g.home, g.homeScore, g.awayScore, "home")
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                ForEach(picks.indices, id: \.self) { i in
                    let (sel, label, ml) = picks[i]
                    if let sel {
                        OddsButton(sel: sel, suspended: o.suspended, move: o.move[sel.id], big: true, label: label, compact: true)
                    } else {
                        UnavailableOdds(label: label, text: ml ? "N/A" : "—", compact: true)
                    }
                }
            }
        }
    }

    private func liveTeam(_ g: Game, _ team: Team, _ score: Int, _ opponent: Int, _ side: String) -> some View {
        HStack(spacing: 5) {
            Button { GameModel.open(g.id) } label: {
                HStack(spacing: 7) {
                    LiveLogo(team: team)
                    Text(team.name).font(.barlow(12, 700)).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.press)
            .accessibilityLabel("Open \(team.name) game stats")
            Text(g.state == .scheduled ? "–" : "\(score)")
                .font(.display(23, 900)).monospacedDigit()
                .foregroundStyle(g.state == .live && score < opponent ? Theme.text2 : Theme.text)
                .frame(minWidth: 23, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.6), value: score)
        }
        .frame(height: 48)
    }

    /// Simulated layout: a grid with spread / total / money columns.
    @ViewBuilder private func simBody(_ g: Game, _ o: OddsBoard) -> some View {
        let Sp = Sim.sports[g.sport]!
        let cols: [(String, [Selection])] = [
            o.spread.count == 2 ? (Sp.spreadLabel, o.spread) : nil,
            o.total.count == 2 ? ("Total", o.total) : nil,
            o.moneyline.filter { $0.side != "draw" }.count == 2 ? ("Money", o.moneyline.filter { $0.side != "draw" }) : nil,
        ].compactMap { $0 }
        let w: CGFloat = cols.count == 2 ? 66 : 60
        let draw = o.moneyline.first { $0.side == "draw" }
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Spacer(minLength: 0)
                ForEach(cols.indices, id: \.self) { i in
                    Text(cols[i].0.uppercased()).font(.barlow(10, 800)).tracking(0.4).foregroundStyle(Theme.muted).frame(width: w)
                }
            }
            ForEach(["away", "home"], id: \.self) { side in
                let team = side == "away" ? g.away : g.home
                let row = side == "away" ? 0 : 1
                let score = side == "home" ? g.homeScore : g.awayScore
                let opp = side == "home" ? g.awayScore : g.homeScore
                HStack(spacing: 5) {
                    Button { GameModel.open(g.id) } label: {
                        HStack(spacing: 8) {
                            TeamBadge(team: team)
                            Text(g.state == .live ? team.abbr : team.name).font(.barlow(14.5, 700)).lineLimit(1)
                            Spacer(minLength: 0)
                            if g.state == .live {
                                Text("\(score)").font(.display(23, 900)).monospacedDigit().foregroundStyle(score < opp ? Theme.text2 : Theme.text)
                                    .padding(.trailing, 2).contentTransition(.numericText()).animation(.easeOut(duration: 0.6), value: score)
                            }
                        }
                        .frame(height: 46)
                    }
                    .buttonStyle(.press)
                    ForEach(cols.indices, id: \.self) { i in
                        let sel = cols[i].1[row]
                        OddsButton(sel: sel, suspended: o.suspended, move: o.move[sel.id], label: team.name).frame(width: w)
                    }
                }
            }
            if let draw {
                HStack(spacing: 5) {
                    Text("Draw").font(.barlow(14.5, 700)).foregroundStyle(Theme.text2).frame(maxWidth: .infinity, alignment: .leading).frame(height: 40)
                    OddsButton(sel: draw, suspended: o.suspended, move: o.move[draw.id], label: "Draw").frame(width: w)
                }
            }
            if cols.isEmpty {
                Text("Betting lines are not available for this game yet.").font(.barlow(11.5)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6).padding(.horizontal, 2)
            }
        }
    }
}

/// Two columns sized like CSS `minmax(minLeft, left fr) minmax(0, right fr)`.
struct FrColumns: Layout {
    var left: CGFloat
    var right: CGFloat
    var minLeft: CGFloat
    var spacing: CGFloat

    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let free = max(0, total - spacing)
        var l = free * left / (left + right)
        if l < minLeft { l = min(minLeft, free) }
        return (l, free - l)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 360
        let (l, r) = widths(total)
        let h = subviews.enumerated().map { i, s in s.sizeThatFits(ProposedViewSize(width: i == 0 ? l : r, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (l, r) = widths(bounds.width)
        for (i, s) in subviews.enumerated() {
            let w = i == 0 ? l : r
            let size = s.sizeThatFits(ProposedViewSize(width: w, height: nil))
            let x = i == 0 ? bounds.minX : bounds.minX + l + spacing
            s.place(at: CGPoint(x: x, y: bounds.midY - size.height / 2), proposal: ProposedViewSize(width: w, height: size.height))
        }
    }
}
