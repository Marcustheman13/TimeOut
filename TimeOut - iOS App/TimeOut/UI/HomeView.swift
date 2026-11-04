import SwiftUI

/// Home's view state (the web app keeps `feedDay` in home.js).
@Observable
final class HomeModel {
    static let shared = HomeModel()
    /// Which day the board shows: 0 = today, 1 = tomorrow. Live games are always today.
    var feedDay = 0
    /// Which market each game card has open, by game ID.
    var marketTab: [String: String] = [:]

    var followed: [String] {
        let s = Store.shared.data?.settings.sports ?? []
        return s.isEmpty ? Sim.realLeagues : s
    }

    /// The sport chip: "all" or a league.
    var activeFilter: String {
        let f = Store.shared.data?.feedFilter ?? "all"
        return ["pred", "todo", "sim", "live"].contains(f) ? "all" : f
    }

    /// The Live switch on its own line. It narrows whichever sport is picked.
    var liveOnly: Bool { Store.shared.data?.feedLive ?? false }

    var activeDay: Int { liveOnly ? 0 : feedDay }

    /// "NBA", or "all sports".
    var filterName: String {
        let f = activeFilter
        if f == "all" { return "all sports" }
        return f == "ncaaf" ? "College Football" : Sim.leagues[f]?.short ?? f
    }

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

    func setLive(_ on: Bool) {
        Store.shared.setFeedLive(on)
        LiveFeed.shared.setViewingDay(activeDay)
        UIState.shared.scrollToFilters()
    }

    static func myOpenChallenges(on ref: String) -> [Challenge] {
        (Store.shared.data?.challenges ?? []).filter { $0.status == "open" && $0.picks.contains { $0.gameId == ref || $0.predId == ref || $0.raceId == ref } }
    }

    static func sportsOnly(_ challenge: Challenge) -> Bool {
        challenge.kind == "race" || (challenge.kind == "sports" && challenge.picks.allSatisfy { pick in pick.gameId != nil && Feed.game(pick.gameId!)?.league != "sim" })
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
                    ScreenTimeSetupBanner()
                    WalletCard(wl: wl)
                    if wl.appsLocked && ScreenTime.shared.isEnforcing { AppLockBanner(wl: wl) }
                    StatusStrip(wl: wl)
                    OpenChallengesStrip()
                    Section {
                        VStack(spacing: 12) {
                            BuildComboControl()
                            if live.offline {
                                Note(.blue, icon: .info, "Live matchup targets can't be reached here, so these are simulated games with real team names. Everything else works the same.").gutter()
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
                HStack(spacing: 6) { Icon(.lock, 14); Text("OUT OF PLEDGE MINUTES").font(.barlow(12, 900)).tracking(0.72) }
                    .foregroundStyle(Theme.loss)
                Text("Pledges are paused. They reopen at midnight.").font(.barlow(16, 700)).padding(.top, 8)
                Countdown(target: TO.nextMidnight()).font(.display(46, 900)).padding(.top, 6)
                Text("Active challenges still resolve and update tomorrow's phone time.").font(.barlow(13)).foregroundStyle(Theme.text2).padding(.top, 4)
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
                            Text("Available minutes today").eyebrow()
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
                    HStack(spacing: 6) { Icon(.info, 14); Text("Pledges use tomorrow's phone time. How it works") }
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
                stat(ScreenTime.shared.isEnforcing ? "\(wl.phoneLeft) min" : "Off", "Phone time left", pColor)
                VRule()
                stat("\(wl.atRisk) min", "Committed to active challenges", wl.atRisk > 0 ? Theme.warn : Theme.text)
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
            Text(label).font(.barlow(11, 700)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
    }
}

/// The big prompt at the top of Home until Screen Time can really block apps. Tapping it opens the setup sheet.
struct ScreenTimeSetupBanner: View {
    private var st: ScreenTime { .shared }

    var body: some View {
        let step = st.setupStep
        if step != .done {
            Button { UIState.shared.openSheet(.screenTimeApps) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Icon(.shield, 20).foregroundStyle(Theme.accentInk)
                            .frame(width: 38, height: 38)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(step)).font(.barlow(16, 800)).foregroundStyle(Theme.text)
                            Text(detail(step)).font(.barlow(13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Text(action(step)).font(.barlow(14, 800)).foregroundStyle(Theme.accentInk)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
                .padding(14)
                .background(LinearGradient(colors: [Theme.accent.opacity(0.17), Theme.accent.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.press)
            .padding(.top, 4)
            .gutter()
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }

    private func title(_ step: ScreenTime.SetupStep) -> String {
        switch step {
        case .allow: return st.status == .denied ? "Screen Time access is off" : "Set up Screen Time"
        case .pick: return "Choose the apps to block"
        default: return "App limits are off"
        }
    }

    private func detail(_ step: ScreenTime.SetupStep) -> String {
        switch step {
        case .allow: return "TimeOut can't block anything yet. Allow Screen Time, pick your apps, and your limits become real. It takes about 30 seconds."
        case .pick: return "One step left. Pick the apps TimeOut locks when today's phone time runs out."
        default: return "Your apps won't lock when your phone time runs out, and your tier stays at Rookie."
        }
    }

    private func action(_ step: ScreenTime.SetupStep) -> String {
        switch step {
        case .allow: return "Set up in 30 seconds"
        case .pick: return "Choose apps"
        default: return "Turn limits back on"
        }
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

struct OpenChallengesStrip: View {
    var body: some View {
        let open = (Store.shared.data?.challenges ?? []).filter { $0.status == "open" && !$0.picks.isEmpty && HomeModel.sportsOnly($0) }.sorted { $0.placedAt > $1.placedAt }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("Active challenges").font(.barlow(17, 800))
                    CountPill(n: open.count, off: open.isEmpty)
                }
                Spacer(minLength: 0)
                if !open.isEmpty {
                    Button("See all") { UIState.shared.go("challenges") }.font(.barlow(13.5, 700)).foregroundStyle(Theme.accent).buttonStyle(.press)
                }
            }
            .gutter()
            if open.isEmpty {
                Text("No active challenges. Choose a matchup target below to begin.").font(.barlow(13)).foregroundStyle(Theme.text2)
                    .card(12).gutter()
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { ForEach(open) { MiniChallenge(challenge: $0) } }.padding(.horizontal, 16).padding(.bottom, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct MiniChallenge: View {
    var challenge: Challenge
    var body: some View {
        let title = challenge.kind == "todo" ? "To-do Combo Goal (\(challenge.picks.count))" : challenge.picks.count > 1 ? "\(challenge.picks.count)-pick Combo Goal" : (challenge.picks.first?.label ?? "")
        let pick = challenge.picks.first { $0.result == "pending" } ?? challenge.picks.first ?? Pick(selId: "", kind: "game", market: "winner", price: 100, label: "", marketLabel: "", matchup: "")
        let win = ChallengeText.toWin(challenge)
        Button { UIState.shared.go("challenges") } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.barlow(14, 800)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(PointValueMath.multiplierText(PointValueMath.fromDecimal(challenge.decimal))).font(.display(15, 800)).foregroundStyle(Theme.text2).lineLimit(1).fixedSize()
                }
                line(pick).font(.barlow(13, 600)).foregroundStyle(Theme.text2).lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text("\(challenge.pledgeMinutes) min").foregroundStyle(Theme.text2)
                    Icon(.chevR, 12)
                    if win > 0 { Text("win \(win) min").foregroundStyle(Theme.accent) }
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

    @ViewBuilder private func line(_ pick: Pick) -> some View {
        if challenge.kind == "todo" {
            Text("\(challenge.picks.filter { $0.result == "won" }.count)/\(challenge.picks.count) done · due midnight")
        } else if pick.kind == "pred" {
            Text("Resolves in \(Fmt.inTime((pick.start ?? 0) - TO.now()))")
        } else if pick.kind == "race" {
            let race = Races.shared.get(pick.raceId)
            if race?.status == "running" {
                HStack(spacing: 4) { LiveTag(); Text("Virtual Race #\(race!.number)") }
            } else {
                Text("Virtual Race #\((pick.raceId ?? "").replacingOccurrences(of: "race-", with: "")) · \(race?.status == "final" ? "Finished" : "Starting soon")")
            }
        } else if let g = pick.gameId.flatMap({ Feed.game($0) }) {
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
        let on = home.liveOnly
        // With Live on, each sport's number is how many games it has live right now.
        let today = home.boardGames(0)
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Chip(label: "All", on: f == "all", icon: .grid) { home.setFilter("all") }
                    ForEach(Sim.leagueOrder.filter { $0 != "sim" && home.followed.contains($0) }, id: \.self) { l in
                        Chip(label: l == "ncaaf" ? "College Football" : Sim.leagues[l]!.short, on: f == l,
                             n: on ? today.filter { $0.league == l && $0.state == .live }.count : games.filter { $0.league == l && $0.state != .final }.count) { home.setFilter(l) }
                    }
                    Chip(label: "Edit", icon: .sliders, dashed: true) { SettingsModel.open("sports") }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            LiveTile(games: today).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10).gutter()
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

/// The small red Live tile, on its own line. It filters whichever sport is picked above it.
struct LiveTile: View {
    var games: [Game]
    private var home: HomeModel { .shared }

    var body: some View {
        let on = home.liveOnly
        let f = home.activeFilter
        let n = games.filter { $0.state == .live && (f == "all" || $0.league == f) }.count
        Button { home.setLive(!on) } label: {
            HStack(spacing: 6) {
                Circle().fill(on ? .white : Theme.live).frame(width: 7, height: 7)
                Text("Live").font(.barlow(13, 800))
                if n > 0 { Text("\(n)").font(.barlow(12, 800)).monospacedDigit().opacity(0.8) }
            }
            .foregroundStyle(on ? .white : Theme.live)
            .padding(.horizontal, 10).frame(height: 30)
            .background(on ? Theme.live : Theme.live.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.live.opacity(on ? 0 : 0.55), lineWidth: 1))
            .fixedSize()
        }
        .buttonStyle(.press)
        .accessibilityLabel("Live games only, \(n) live now in \(home.filterName)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Today and tomorrow. Counts are games still to be played that day, in the sports being shown.
struct DayBar: View {
    var inset = true
    private var home: HomeModel { .shared }
    private var live: LiveFeed { .shared }

    var body: some View {
        let f = home.activeFilter
        if !home.liveOnly && !live.offline {
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

struct BuildComboControl: View {
    private var slip: Slip { .shared }
    var body: some View {
        if !slip.comboMode {
            Button { slip.toggleComboMode() } label: {
                HStack(spacing: 12) {
                    Icon(.target, 18).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Build a Combo Goal").font(.barlow(14, 700))
                        Text("Link choices from up to four matchups").font(.barlow(12)).foregroundStyle(Theme.muted)
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
                LrIcon(icon: .target, size: 34, iconSize: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose Combo Goal picks").font(.barlow(14, 700))
                    Text("\(slip.picks.count) of \(Rules.maxMatchupPicks) choices · one per matchup").font(.barlow(12)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { slip.toggleComboMode() }.font(.barlow(13.5, 700)).foregroundStyle(Theme.accent).buttonStyle(.press)
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
        let inSport = f == "all" ? games : games.filter { $0.league == f }
        let list = home.liveOnly ? inSport.filter { $0.state == .live } : inSport
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
        let isLive = home.liveOnly
        let when = day == 0 ? "today" : day == 1 ? "tomorrow" : "on \(home.dayLabel(day))"
        let loading = day > 0 && live.upcomingIsLoading
        let liveTitle = filter == "all" ? "No live games right now" : "No live \(home.filterName) games right now"
        let title = isLive ? liveTitle : loading ? "Loading the schedule…" : "Sorry, no games are happening for this sport \(when)."
        let next: Int? = !isLive && !loading
            ? (0...LiveFeed.upcomingDays).first { i in i != day && home.boardGames(i).contains { filter == "all" || $0.league == filter } }
            : nil
        if live.failed {
            EmptyState(icon: .alert, title: "Sports couldn’t load", text: "Check your connection and try again.") {
                Button("Try again") { live.refresh(force: true) }.buttonStyle(.btn(.primary))
            }
        } else {
            EmptyState(icon: loading ? .clock : .target, title: title, text: isLive ? "Check back when a game is underway." : nil) {
                if isLive {
                    Button("Show all games") { home.setLive(false) }.buttonStyle(.btn(.primary))
                } else if let next {
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
            HStack(spacing: 6) { Icon(.alert, 13); Text("Canceled · all challenges cancelled, committed minutes returned") }.foregroundStyle(Theme.warn)
        case .postponed:
            HStack(spacing: 6) { Icon(.alert, 13); Text("Postponed · all challenges cancelled, committed minutes returned") }.foregroundStyle(Theme.warn)
        }
    }
}

struct GameCard: View {
    var game: Game
    private var live: LiveFeed { .shared }

    var body: some View {
        let _ = live.version
        let g = game
        let o = Feed.pointValue(g.id)
        let open = (g.state == .live || g.state == .scheduled) && !o.suspended
        let mine = HomeModel.myOpenChallenges(on: g.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                GameStatusText(g: g).lineLimit(1)
                if o.suspended && g.state == .live { Tag("Challenges closed", icon: .lock) }
                Spacer(minLength: 0)
                Text(g.otherConferenceLive ? "LIVE · \(g.conferenceName.isEmpty ? "UNRANKED" : g.conferenceName)" : g.simulated ? "SIMULATED" : Sim.leagues[g.league]?.short ?? "")
                    .font(.barlow(11, 800)).tracking(0.44).foregroundStyle(Theme.muted)
            }
            .font(.barlow(12, 700))
            .foregroundStyle(Theme.text2)
            .frame(minHeight: 18)
            .padding(.bottom, 8)

            if open {
                MatchupBody(g: g, o: o)
            } else {
                VStack(spacing: 0) {
                    closedRow(g.away, g.awayScore, g.awayScore >= g.homeScore, g)
                    closedRow(g.home, g.homeScore, g.homeScore >= g.awayScore, g)
                }
                if g.state == .postponed {
                    Note(.warn, icon: .info, "This game was postponed. Any related pledge will be returned.").padding(.top, 6)
                }
            }

            HStack {
                if !mine.isEmpty {
                    HStack(spacing: 4) { Icon(.target, 14); Text("\(mine.count) active challenge\(mine.count == 1 ? "" : "s") here") }
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 0)
                Button { GameModel.open(g.id) } label: {
                    HStack(spacing: 6) { Text("Stats & challenge details"); Icon(.chevR, 14) }.font(.barlow(12.5, 700)).foregroundStyle(Theme.accent)
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

    private func closedRow(_ team: Team, _ score: Int, _ leading: Bool, _ g: Game) -> some View {
        Button { GameModel.open(g.id) } label: {
            HStack(spacing: 8) {
                TeamBadge(team: team)
                Text(team.name).font(.barlow(14.5, 700)).foregroundStyle(leading ? Theme.text : Theme.text2).lineLimit(1)
                Spacer(minLength: 0)
                if g.state == .final || g.state == .live {
                    Text("\(score)").font(.display(23, 900)).monospacedDigit().foregroundStyle(leading ? Theme.text : Theme.text2).padding(.trailing, 2)
                }
            }
            .frame(height: 46)
        }
        .buttonStyle(.press)
    }
}

/// The open game card: both teams, then Match Winner / Margin / Total Points tabs with two choices.
struct MatchupBody: View {
    var g: Game
    var o: PointValueBoard

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                team(g.away, g.awayScore)
                Text("@").font(.barlow(12, 700)).foregroundStyle(Theme.text2)
                team(g.home, g.homeScore)
            }
            .padding(.top, 8).padding(.bottom, 4)
            Group {
                if g.state == .live {
                    HStack(spacing: 4) { LiveTag(); Text("· \(g.awayScore)–\(g.homeScore) · \(g.clock)") }
                } else {
                    Text("\(Fmt.day(g.start)) · \(Fmt.time(g.start))")
                }
            }
            .font(.barlow(12, 700)).foregroundStyle(Theme.text2)
            .padding(.top, 4).padding(.bottom, 4)
            ChallengeChoices(g: g, o: o, title: { sel in MatchupText.cardLabel(sel, g) })
        }
    }

    private func team(_ t: Team, _ score: Int) -> some View {
        Button { GameModel.open(g.id) } label: {
            HStack(spacing: 7) {
                TeamBadge(team: t, size: 30)
                Text(t.name).font(.barlow(14, 750)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if g.state == .live {
                    Text("\(score)").font(.barlow(19, 800)).monospacedDigit()
                        .contentTransition(.numericText()).animation(.easeOut(duration: 0.6), value: score)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.press)
        .accessibilityLabel("Open \(t.name) game stats")
    }
}

enum MatchupText {
    /// The label on a Home card, same as the web app.
    static func cardLabel(_ sel: Selection, _ g: Game) -> String {
        let team = sel.side == "away" ? g.away.name : g.home.name
        switch sel.market {
        case "winner": return "\(team) to win"
        case "margin": return marginText(team, sel.line ?? 0)
        default: return "Combined score \(sel.side == "higher" ? "above" : "below") \(PointValueMath.fmtLine(sel.line ?? 0, signed: false))"
        }
    }

    /// The label on the game page, same as the web app.
    static func detailLabel(_ sel: Selection, _ g: Game) -> String {
        let team = sel.side == "away" ? g.away.name : g.home.name
        switch sel.market {
        case "winner": return "\(team) · Outright Winner"
        case "margin": return marginText(team, sel.line ?? 0)
        default: return "\(sel.side == "higher" ? "Total Score Over" : "Total Score Under") \(PointValueMath.fmtLine(sel.line ?? 0, signed: false))"
        }
    }

    private static func marginText(_ team: String, _ line: Double) -> String {
        line < 0 ? "\(team) to win by \(Int(abs(line).rounded(.up)))+" : "\(team) to stay within \(Int(line.rounded(.down)))"
    }
}

/// Tabs for each market a game has, and the two choices in the open one.
struct ChallengeChoices: View {
    var g: Game
    var o: PointValueBoard
    var title: (Selection) -> String
    private var home: HomeModel { .shared }

    var body: some View {
        let tabs: [(String, String, [Selection])] = [("winner", "Match Winner", o.winner), ("margin", "Margin", o.margin), ("total", "Total Points", o.total)]
            .map { ($0.0, $0.1, $0.2.filter { $0.side != "draw" }) }
            .filter { $0.2.count >= 2 }
        let current = tabs.first { $0.0 == home.marketTab[g.id] } ?? tabs.first
        if let current {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    ForEach(tabs, id: \.0) { tab in
                        let on = tab.0 == current.0
                        Button { home.marketTab[g.id] = tab.0 } label: {
                            Text(tab.1).font(.barlow(12, 750)).lineLimit(1).minimumScaleFactor(0.8)
                                .foregroundStyle(on ? Theme.accentInk : Theme.text2)
                                .frame(maxWidth: .infinity).frame(minHeight: 34)
                                .background(on ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.press)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                HStack(spacing: 7) {
                    ForEach(Array(current.2.prefix(2)), id: \.id) { sel in
                        ChallengeChoiceButton(sel: sel, suspended: o.suspended, big: true, label: title(sel))
                    }
                }
            }
            .padding(.top, 4)
        } else {
            Text("Challenge targets are not available for this game yet.").font(.barlow(12)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        }
    }
}
