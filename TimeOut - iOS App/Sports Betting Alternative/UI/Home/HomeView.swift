import SwiftUI

/// Board filter chips. "Live" and "All" plus one per league with games on the board.
enum BoardFilter: Hashable {
    case live, all
    case league(League)

    var storageKey: String {
        switch self {
        case .live: "live"
        case .all: "all"
        case .league(let league): league.rawValue
        }
    }

    init(storageKey: String) {
        switch storageKey {
        case "live": self = .live
        case "all": self = .all
        default: self = League(rawValue: storageKey).map(BoardFilter.league) ?? .all
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("boardFilter") private var filterKey = "all"

    @State private var editingSports = false

    /// A league filter for a sport the user stopped following falls back to "All".
    private var filter: BoardFilter {
        let filter = BoardFilter(storageKey: filterKey)
        if case .league(let league) = filter, !model.sports.isFollowing(league) { return .all }
        return filter
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    WalletHeader()
                    StatusStrip()
                    OpenBetsStrip()

                    Section {
                        board
                    } header: {
                        FilterBar(filterKey: $filterKey) { editingSports = true }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .refreshable { await model.tick() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass.bottomhalf.filled")
                            .foregroundStyle(Theme.accent)
                        Text(Theme.brand)
                            .font(.display(22, weight: .black))
                            .italic()
                    }
                    .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    BalancePill()
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .sheet(isPresented: $editingSports) {
                SportsPickerView()
                    .presentationBackground(Theme.background)
            }
        }
    }

    @ViewBuilder
    private var board: some View {
        let games = visibleGames
        if !model.feed.hasLoaded {
            ProgressView("Loading the board…")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if games.isEmpty {
            EmptyBoard(filter: filter) {
                if !model.sports.isFollowing(.sim) {
                    model.sports.save(model.sports.followed.union([.sim]))
                    Task { await model.tick() }
                }
                filterKey = BoardFilter.league(.sim).storageKey
            }
        } else if case .league = filter {
            gameList(games)
        } else {
            ForEach(League.allCases) { league in
                let leagueGames = games.filter { $0.league == league }
                if !leagueGames.isEmpty {
                    LeagueHeader(league: league, count: leagueGames.count)
                    gameList(leagueGames)
                }
            }
        }
    }

    private func gameList(_ games: [Game]) -> some View {
        ForEach(games) { game in
            GameCard(game: game)
                .padding(.horizontal, 16)
        }
    }

    private var visibleGames: [Game] {
        switch filter {
        case .live: model.feed.liveGames
        case .all: model.feed.games.filter { $0.state != .final || $0.league == .sim }
        case .league(let league): model.feed.games(in: league)
        }
    }
}

// MARK: - Wallet header

/// PRD: current bets and screen time at the top of the home screen.
private struct WalletHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let book = model.book
        VStack(alignment: .leading, spacing: 14) {
            if book.isLockedOut {
                lockedOut
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BETTING BALANCE")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Theme.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(book.balance)")
                                .font(.display(48, weight: .black))
                                .foregroundStyle(Theme.accent)
                                .contentTransition(.numericText())
                            Text("min")
                                .font(.display(20, weight: .bold))
                                .foregroundStyle(Theme.accent.opacity(0.8))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("RESETS IN")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Theme.textMuted)
                        MidnightCountdown(font: .display(17, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                ProgressView(value: Double(min(book.balance, BetBook.dailyAllowance)), total: Double(BetBook.dailyAllowance))
                    .tint(Theme.accent)
            }

            HStack(spacing: 0) {
                phoneStat
                Divider().frame(height: 30).overlay(Theme.stroke)
                stat("At risk", "\(book.minutesAtRisk) min", book.minutesAtRisk > 0 ? Theme.warning : Theme.textSecondary)
                Divider().frame(height: 30).overlay(Theme.stroke)
                stat("Tomorrow", "\(book.tomorrowLimit) min", tomorrowColor)
            }
        }
        .card(padding: 16)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(.snappy, value: book.balance)
    }

    /// Time left on limited apps when Screen Time is enforcing, otherwise just today's limit.
    @ViewBuilder
    private var phoneStat: some View {
        let screenTime = model.screenTime
        let limit = model.book.todayLimit
        if screenTime.isEnforcing {
            let left = screenTime.isShieldActive ? 0 : max(limit - screenTime.usedToday, 0)
            stat("Phone time left", "\(left) min", left == 0 ? Theme.loss : left <= 10 ? Theme.warning : Theme.textSecondary)
        } else {
            stat("Phone limit today", "\(limit) min", Theme.textSecondary)
        }
    }

    private var tomorrowColor: Color {
        let delta = model.book.tomorrowLimit - BetBook.dailyAllowance
        return delta > 0 ? Theme.win : delta < 0 ? Theme.loss : Theme.textSecondary
    }

    private var lockedOut: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("OUT OF SCREENTIME", systemImage: "lock.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Theme.loss)
            Text("Betting reopens at midnight")
                .font(.system(size: 15, weight: .semibold))
            MidnightCountdown(font: .display(40, weight: .black))
                .foregroundStyle(.white)
            Text("Open bets still settle and count toward tomorrow.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.display(18, weight: .bold)).foregroundStyle(color)
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BalancePill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let book = model.book
        HStack(spacing: 5) {
            Image(systemName: book.isLockedOut ? "lock.fill" : "hourglass")
            Text(book.isLockedOut ? "Locked" : "\(book.balance) min")
                .contentTransition(.numericText())
        }
        .font(.system(size: 14, weight: .heavy))
        .foregroundStyle(book.isLockedOut ? Theme.loss : .black)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(book.isLockedOut ? Theme.raised : Theme.accent, in: .capsule)
        .accessibilityLabel(book.isLockedOut ? "Betting locked until midnight" : "\(book.balance) minutes available to bet")
    }
}

// MARK: - Open bets strip

private struct OpenBetsStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let open = model.book.openBets
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Open Bets")
                    .font(.system(size: 17, weight: .heavy))
                Text("\(open.count)")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(open.isEmpty ? Theme.textMuted : Theme.accent, in: .capsule)
                Spacer()
                if !open.isEmpty {
                    Button("See all") { model.tab = .bets }
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .padding(.horizontal, 16)

            if open.isEmpty {
                Text("No open bets. Tap any odds below to start one.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 12)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(open) { bet in
                            MiniBetCard(bet: bet)
                                .onTapGesture { model.tab = .bets }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct MiniBetCard: View {
    @Environment(AppModel.self) private var model
    let bet: Bet

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bet.title)
                    .font(.system(size: 14, weight: .heavy))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Odds.format(bet.americanOdds))
                    .font(.display(14))
                    .foregroundStyle(Theme.textSecondary)
            }
            if let leg = bet.legs.first {
                let game = model.feed.game(id: leg.game.gameID)
                HStack(spacing: 6) {
                    if game?.state == .live { LiveBadge() }
                    Text(game.map(scoreText) ?? leg.game.matchup)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let friend = bet.friendStake {
                Label(friend, systemImage: "person.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .lineLimit(1)
            } else {
                HStack(spacing: 4) {
                    Text("\(bet.stake) min").foregroundStyle(Theme.textSecondary)
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                    Text("\(bet.potentialPayout) min").foregroundStyle(Theme.accent)
                }
                .font(.system(size: 13, weight: .bold))
            }
        }
        .frame(width: 220, height: 92, alignment: .topLeading)
        .card(padding: 12)
    }

    private func scoreText(_ game: Game) -> String {
        switch game.state {
        case .scheduled: return "\(game.away.abbreviation) @ \(game.home.abbreviation) · \(game.start.formatted(date: .omitted, time: .shortened))"
        default: return "\(game.away.abbreviation) \(game.awayScore) – \(game.home.abbreviation) \(game.homeScore) · \(game.statusDetail)"
        }
    }
}

// MARK: - Filters

private struct FilterBar: View {
    @Environment(AppModel.self) private var model
    @Binding var filterKey: String
    let editSports: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(.live, title: "Live", icon: "dot.radiowaves.left.and.right", count: model.feed.liveGames.count)
                chip(.all, title: "All", icon: "square.grid.2x2.fill", count: nil)
                ForEach(leagues) { league in
                    chip(.league(league), title: league.title, icon: league.symbol, count: model.feed.games(in: league).count)
                }
                Button(action: editSports) {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(Theme.textSecondary)
                        .overlay(Capsule().strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit your sports")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
    }

    /// Followed leagues, with ones that have games right now first.
    private var leagues: [League] {
        let active = Set(model.feed.activeLeagues)
        return model.sports.ordered.sorted { (active.contains($0) ? 0 : 1) < (active.contains($1) ? 0 : 1) }
    }

    private func chip(_ filter: BoardFilter, title: String, icon: String, count: Int?) -> some View {
        let selected = filterKey == filter.storageKey
        return Button {
            filterKey = filter.storageKey
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 14, weight: .bold))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(selected ? .black.opacity(0.6) : Theme.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? .black : .white)
            .background(selected ? Theme.accent : Theme.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(selected ? .clear : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct LeagueHeader: View {
    let league: League
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: league.symbol)
                .foregroundStyle(Theme.accent)
            Text(league.title)
                .font(.system(size: 18, weight: .heavy))
            if league == .sim {
                Text("SIMULATED")
                    .font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.raised, in: .capsule)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("\(count) game\(count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

private struct EmptyBoard: View {
    let filter: BoardFilter
    let showSim: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sportscourt")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textMuted)
            Text(filter == .live ? "No live games right now" : "No games on the board")
                .font(.system(size: 17, weight: .bold))
            Text("Sim Hoops runs around the clock. A new slate tips off every 10 minutes.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Bet on Sim Hoops", action: showSim)
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}
