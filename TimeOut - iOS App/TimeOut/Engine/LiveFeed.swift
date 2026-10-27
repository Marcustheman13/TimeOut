import Foundation
import Observation

/// ESPN live scores and sportsbook lines. A port of the web demo's live.js.
@Observable
final class LiveFeed {
    static let shared = LiveFeed()

    static let espn = "https://site.api.espn.com/apis/site/v2/sports"
    static let espnCore = "https://sports.core.api.espn.com/v2/sports"
    static let cfbGroups: [(String, String)] = [
        ("all", "All College Football"), ("80", "Top 25"), ("8", "SEC"), ("4", "Big 12"), ("1", "ACC"), ("5", "Big Ten"),
        ("9", "Pac-12"), ("151", "American"), ("17", "Mountain West"), ("37", "Sun Belt"),
        ("15", "MAC"), ("12", "Conference USA"), ("18", "Independents"),
    ]
    /// league → (scoreboard path, sport, core league)
    static let leagues: [String: (String, String, String)] = [
        "nfl": ("football/nfl", "football", "nfl"), "ncaaf": ("football/college-football", "football", "college-football"),
        "nba": ("basketball/nba", "basketball", "nba"), "mlb": ("baseball/mlb", "baseball", "mlb"),
        "nhl": ("hockey/nhl", "hockey", "nhl"), "epl": ("soccer/eng.1", "soccer", "eng.1"),
    ]
    /// How many days ahead Home's day picker offers (1 = Today and Tomorrow).
    static let upcomingDays = 1
    private static let upcomingTTL: Ms = 10 * TO.MIN

    /// Bumped whenever scores or odds change, so views that read it re-render.
    private(set) var version = 0
    /// Bumped when a game's ESPN summary (stats) arrives.
    private(set) var detailsVersion = 0
    private(set) var loading = false
    private(set) var failed = false
    /// ESPN couldn't be reached at all, so the board falls back to the simulated games.
    private(set) var offline = false
    private(set) var cfbGroup = "all"
    private(set) var upcomingLoading = false
    private var upcomingAt: Ms = 0

    @ObservationIgnored private var cache: [String: [Game]] = [:]
    @ObservationIgnored private var upcoming: [String: [Game]] = [:]
    @ObservationIgnored private var competitions: [String: JSON] = [:]
    @ObservationIgnored private var oddsBooks: [String: [JSON]] = [:]
    @ObservationIgnored private var boards: [String: OddsBoard] = [:]
    @ObservationIgnored private var oddsRequested: Set<String> = []
    @ObservationIgnored private var eventOddsCache: [String: (at: Ms, books: [JSON])] = [:]
    @ObservationIgnored private var details: [String: JSON] = [:]
    @ObservationIgnored private var detailLoading: Set<String> = []
    @ObservationIgnored private var updatedAt: Ms = 0
    @ObservationIgnored private var updatedDayKey = ""
    @ObservationIgnored private var loadingDayKey = ""
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var upcomingDayKey = ""

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    var upcomingIsLoading: Bool { upcomingLoading || upcomingAt == 0 }

    // MARK: Days

    private static func todayBounds(_ now: Ms) -> (Ms, Ms) {
        let start = TO.dayStart(TO.dayKey(now))
        return (start, TO.nextMidnight(now))
    }

    private static let eastern: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return c
    }()

    private static func espnDayKey(_ now: Ms) -> String {
        let c = eastern.dateComponents([.year, .month, .day], from: TO.date(now))
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func shiftDayKey(_ key: String, _ days: Int) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let y = Int(key.prefix(4)) ?? 1970, m = Int(key.dropFirst(4).prefix(2)) ?? 1, d = Int(key.dropFirst(6).prefix(2)) ?? 1
        let date = utc.date(from: DateComponents(year: y, month: m, day: d + days)) ?? Date()
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// ESPN indexes schedules by Eastern calendar day; local days can overlap two or three of them.
    private static func scoreboardDays(_ now: Ms) -> [String] {
        let (start, end) = todayBounds(now)
        let first = espnDayKey(start), last = espnDayKey(end - 1)
        var out: [String] = []
        for k in [shiftDayKey(first, -1), first, last] where !out.contains(k) { out.append(k) }
        return out
    }

    /// 0 = today, 1 = tomorrow, ... in the viewer's own time zone.
    static func dayOffset(_ start: Ms, _ now: Ms) -> Int {
        let today = todayBounds(now).0
        let dayOf = TO.dayStart(TO.dayKey(start))
        return jsRoundInt((dayOf - today) / TO.DAY)
    }

    // MARK: Parsing

    private static let isoFormats: [ISO8601DateFormatter] = {
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime]
        let b = ISO8601DateFormatter()
        b.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [a, b]
    }()
    private static let shortISO: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        return f
    }()

    static func parseDate(_ s: String?) -> Ms? {
        guard let s, !s.isEmpty else { return nil }
        for f in isoFormats { if let d = f.date(from: s) { return TO.ms(d) } }
        if let d = shortISO.date(from: s) { return TO.ms(d) }
        return nil
    }

    private func gameFrom(_ event: JSON, league: String, sport: String) -> (Game, JSON)? {
        let comp = event["competitions"][0]
        let home = comp["competitors"].find { $0["homeAway"].string == "home" }
        let away = comp["competitors"].find { $0["homeAway"].string == "away" }
        guard comp.isObject, home["team"].isObject, away["team"].isObject else { return nil }
        guard let start = Self.parseDate(event["date"].text ?? comp["date"].text) else { return nil }
        let statusObj = comp["status"]["type"].truthy ? comp["status"]["type"] : event["status"]["type"]
        let statusName = statusObj["name"].string ?? ""
        let state: GameState = statusName.contains("POSTPONED") ? .postponed
            : ["CANCELED", "CANCELLED", "ABANDONED", "FORFEIT"].contains(where: { statusName.contains($0) }) ? .canceled
            : statusObj["state"].string == "in" ? .live : statusObj["state"].string == "post" ? .final : .scheduled
        func team(_ c: JSON) -> Team {
            let t = c["team"]
            let rank = c["curatedRank"]["current"].number.map { Int($0) }
            let records = c["records"]
            let record = records.find { $0["type"].string == "total" }["summary"].text ?? records[0]["summary"].text
            return Team(
                id: t["id"].string,
                abbr: t["abbreviation"].text ?? t["shortDisplayName"].text ?? t["displayName"].text ?? "",
                name: t["shortDisplayName"].text ?? t["displayName"].text ?? t["name"].text ?? "",
                fullName: t["displayName"].text ?? t["name"].text,
                city: "",
                color: "#\(t["color"].text ?? "5A6475")",
                logo: t["logo"].text ?? t["logos"][0]["href"].text,
                rank: (rank != nil && rank! > 0 && rank! <= 25) ? rank : nil,
                record: record
            )
        }
        let eventID = event["id"].string ?? ""
        var g = Game(id: "espn-\(league)-\(eventID)", league: league, sport: sport, start: start, end: start + 4 * TO.HOUR,
                     state: state, home: team(home), away: team(away))
        g.eventID = eventID
        g.competitionID = comp["id"].text ?? eventID
        g.homeScore = Int(home["score"].number ?? 0)
        g.awayScore = Int(away["score"].number ?? 0)
        g.progress = state == .live ? 0.5 : state == .final ? 1 : 0
        g.period = Int(comp["status"]["period"].number ?? 0)
        g.clock = statusObj["shortDetail"].text ?? comp["status"]["displayClock"].text ?? ""
        g.statusText = statusObj["shortDetail"].text ?? statusObj["detail"].text ?? statusObj["description"].text ?? "Scheduled"
        g.conferenceName = comp["groups"]["shortName"].text ?? comp["groups"]["name"].text ?? ""
        return (g, comp)
    }

    // MARK: Odds parsing

    private static func american(_ value: JSON) -> Int? {
        guard let n = value.number, n.isFinite, n != 0 else { return nil }
        return jsRoundInt(n)
    }
    private static func hasPrice(_ value: JSON) -> Bool { american(value) != nil }

    private static func marketPrice(_ teamOdds: JSON, _ market: String) -> JSON {
        func value(_ entry: JSON) -> JSON {
            let simple: JSON
            switch entry { case .number, .string: simple = entry; default: simple = .null }
            return entry["american"] ?? entry["alternateDisplayValue"] ?? simple
        }
        return value(teamOdds[market]) ?? value(teamOdds["current"][market])
    }

    private static func moneylinePrice(_ book: JSON, _ side: String) -> JSON {
        if side == "draw" {
            return marketPrice(book["drawOdds"], "moneyLine") ?? book["drawOdds"]["moneyLine"]
                ?? book["moneyline"]["draw"]["current"]["odds"] ?? book["moneyline"]["draw"]["close"]["odds"] ?? book["moneyline"]["draw"]["open"]["odds"]
        }
        let teamOdds = side == "home" ? book["homeTeamOdds"] : book["awayTeamOdds"]
        return marketPrice(teamOdds, "moneyLine") ?? teamOdds["moneyline"]
            ?? book["moneyline"][side]["current"]["odds"] ?? book["moneyline"][side]["close"]["odds"] ?? book["moneyline"][side]["open"]["odds"]
    }

    private static func spreadPrice(_ book: JSON, _ side: String) -> JSON {
        let teamOdds = side == "home" ? book["homeTeamOdds"] : book["awayTeamOdds"]
        let market = book["pointSpread"][side]
        return marketPrice(teamOdds, "spread") ?? teamOdds["spreadOdds"]
            ?? market["current"]["odds"] ?? market["close"]["odds"] ?? market["open"]["odds"]
            ?? (side == "home" ? book["homeSpreadOdds"] : book["awaySpreadOdds"])
    }

    private static func totalPrice(_ book: JSON, _ side: String) -> JSON {
        let flat = side == "over" ? (book["overOdds"] ?? book["overUnderOdds"]) : (book["underOdds"] ?? book["underUnderOdds"])
        let market = book["total"][side].truthy ? book["total"][side] : book["overUnder"][side]
        return flat ?? market["current"]["odds"] ?? market["close"]["odds"] ?? market["open"]["odds"]
    }

    private static func totalLine(_ book: JSON) -> Double? {
        guard let raw = (book["overUnder"] ?? book["total"]).number, raw.isFinite, raw > 0 else { return nil }
        return raw
    }

    private static func isBookmaker(_ book: JSON) -> Bool {
        guard book.truthy else { return false }
        let name = (book["provider"]["name"].string ?? "").lowercased()
        return !(name.contains("numberfire") || name.contains("predictor") || name.contains("win probability"))
    }

    private static func isLiveBook(_ book: JSON) -> Bool {
        (book["provider"]["name"].string ?? "").range(of: "live odds", options: .caseInsensitive) != nil
    }

    private static func spreadFor(_ book: JSON, _ game: Game, _ homeOdds: JSON, _ awayOdds: JSON) -> Double? {
        let homeMarketLine = homeOdds["current"]["pointSpread"]["alternateDisplayValue"] ?? homeOdds["current"]["pointSpread"]["american"]
            ?? homeOdds["pointSpread"]["alternateDisplayValue"] ?? homeOdds["pointSpread"]["american"]
            ?? book["pointSpread"]["home"]["current"]["line"] ?? book["pointSpread"]["home"]["close"]["line"] ?? book["pointSpread"]["home"]["open"]["line"]
        let awayMarketLine = awayOdds["current"]["pointSpread"]["alternateDisplayValue"] ?? awayOdds["current"]["pointSpread"]["american"]
            ?? awayOdds["pointSpread"]["alternateDisplayValue"] ?? awayOdds["pointSpread"]["american"]
            ?? book["pointSpread"]["away"]["current"]["line"] ?? book["pointSpread"]["away"]["close"]["line"] ?? book["pointSpread"]["away"]["open"]["line"]
        if let direct = (homeMarketLine ?? homeOdds["spread"] ?? book["homeSpread"]).number, direct.isFinite, direct != 0 { return direct }
        if let awayLine = awayMarketLine.number, awayLine.isFinite, awayLine != 0 { return -awayLine }
        // ESPN's MLB `details` is the moneyline favorite and price, not a run line.
        if game.sport == "baseball" { return nil }
        let detail = book["details"].text ?? ""
        var value: Double?
        if let r = detail.range(of: #"[+-]\s*\d+(?:\.\d+)?"#, options: .regularExpression) {
            value = Double(detail[r].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "+", with: ""))
        } else {
            value = book["spread"].number
        }
        guard let v = value, v.isFinite, v != 0, abs(v) <= 50 else { return nil }
        if homeOdds["favorite"].bool == true { return -abs(v) }
        if awayOdds["favorite"].bool == true { return abs(v) }
        let lower = detail.lowercased()
        let named = { (t: Team) in [t.abbr, t.name, t.fullName ?? ""].filter { !$0.isEmpty }.contains { lower.contains($0.lowercased()) } }
        if named(game.home) { return v }
        if named(game.away) { return -v }
        if let signed = book["spread"].number, signed.isFinite, signed != 0 { return signed }
        return nil
    }

    private func makeOdds(_ game: Game) -> OddsBoard {
        let comp = competitions[game.id] ?? .null
        let fetched = oddsBooks[game.id] ?? []
        let candidates: [JSON] = fetched.isEmpty
            ? [comp["odds"][0]].filter { $0.truthy }
            : fetched + (game.state == .live ? [] : comp["odds"].array)
        let books = candidates.filter { Self.isBookmaker($0) }
        let liveBooks = books.filter { Self.isLiveBook($0) }
        let marketBooks = game.state == .live && !liveBooks.isEmpty ? liveBooks : books
        func add(_ market: String, _ side: String, _ line: Double?, _ price: JSON, _ title: String?) -> Selection? {
            guard let p = Self.american(price) else { return nil }
            return Selection(id: "\(game.id)|\(market)|\(side)", kind: "game", gameId: game.id, market: market, side: side, line: line, price: p, source: title ?? "")
        }
        var board = OddsBoard()
        board.moneyline = ["away", "home", "draw"].compactMap { side in
            guard let source = marketBooks.first(where: { Self.hasPrice(Self.moneylinePrice($0, side)) }) else { return nil }
            let team = side == "home" ? source["homeTeamOdds"]["team"] : source["awayTeamOdds"]["team"]
            return add("ml", side, nil, Self.moneylinePrice(source, side), side == "draw" ? "Draw" : team["displayName"].string)
        }
        let spreads = marketBooks.compactMap { book -> (JSON, Double)? in
            guard let line = Self.spreadFor(book, game, book["homeTeamOdds"], book["awayTeamOdds"]),
                  Self.hasPrice(Self.spreadPrice(book, "home")) || Self.hasPrice(Self.spreadPrice(book, "away")) else { return nil }
            return (book, line)
        }
        let spreadSource = spreads.first { Self.hasPrice(Self.spreadPrice($0.0, "home")) && Self.hasPrice(Self.spreadPrice($0.0, "away")) } ?? spreads.first
        if let spreadLine = spreadSource?.1 {
            func priceAt(_ side: String) -> JSON {
                spreads.first { $0.1 == spreadLine && Self.hasPrice(Self.spreadPrice($0.0, side)) }.map { Self.spreadPrice($0.0, side) } ?? .null
            }
            board.spread = [add("spread", "away", -spreadLine, priceAt("away"), "Away"), add("spread", "home", spreadLine, priceAt("home"), "Home")].compactMap { $0 }
        }
        let totals = marketBooks.compactMap { book -> (JSON, Double)? in
            guard let line = Self.totalLine(book), Self.hasPrice(Self.totalPrice(book, "over")) || Self.hasPrice(Self.totalPrice(book, "under")) else { return nil }
            return (book, line)
        }
        let totalSource = totals.first { Self.hasPrice(Self.totalPrice($0.0, "over")) && Self.hasPrice(Self.totalPrice($0.0, "under")) } ?? totals.first
        if let line = totalSource?.1 {
            func priceAt(_ side: String) -> JSON {
                totals.first { $0.1 == line && Self.hasPrice(Self.totalPrice($0.0, side)) }.map { Self.totalPrice($0.0, side) } ?? .null
            }
            board.total = [add("total", "over", line, priceAt("over"), "Over"), add("total", "under", line, priceAt("under"), "Under")].compactMap { $0 }
        }
        board.suspended = !(game.state == .scheduled || game.state == .live) || (!books.isEmpty && books.allSatisfy { $0["isClosed"].bool == true })
        board.updatedAt = updatedAt
        return board
    }

    // MARK: Fetching

    private func getJSON(_ url: URL) async throws -> JSON {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError(code: "espn", message: "ESPN returned \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return JSON(data: data)
    }

    private func fetchLeague(_ league: String, group: String, now: Ms, dates: [String]? = nil) async throws -> [(Game, JSON)] {
        guard let entry = Self.leagues[league] else { return [] }
        let path = entry.0, sport = entry.1
        let days = dates ?? Self.scoreboardDays(now)
        var payloads: [JSON] = []
        await withTaskGroup(of: JSON?.self) { groupTasks in
            for date in days {
                groupTasks.addTask { @MainActor [session = self.session] in
                    var comps = URLComponents(string: "\(Self.espn)/\(path)/scoreboard")!
                    var items = [URLQueryItem(name: "dates", value: date)]
                    if league == "ncaaf" {
                        if group != "all" { items.append(URLQueryItem(name: "groups", value: group)) }
                        items.append(URLQueryItem(name: "limit", value: "100"))
                    }
                    comps.queryItems = items
                    guard let url = comps.url, let (data, response) = try? await session.data(from: url),
                          let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
                    return JSON(data: data)
                }
            }
            for await result in groupTasks { if let r = result { payloads.append(r) } }
        }
        if payloads.isEmpty { throw AppError(code: "espn", message: "All ESPN scoreboard requests failed for \(league).") }
        var events: [String: JSON] = [:]
        var order: [String] = []
        for payload in payloads {
            for event in payload["events"].array {
                let id = event["id"].string ?? ""
                if events[id] == nil { order.append(id) }
                events[id] = event
            }
        }
        return order.compactMap { events[$0] }.compactMap { gameFrom($0, league: league, sport: sport) }
    }

    private func resolveOddsItem(_ item: JSON) async throws -> JSON {
        guard let ref = item["$ref"].string else { return item }
        guard let url = URL(string: ref.replacingOccurrences(of: "http:", with: "https:", options: .anchored)) else { return .null }
        return try await getJSON(url)
    }

    private func fetchEventOdds(_ game: Game, now: Ms) async -> [JSON] {
        if let cached = eventOddsCache[game.id], now - cached.at < 25_000 { return cached.books }
        guard let coreLeague = Self.leagues[game.league]?.2, let eventID = game.eventID,
              let url = URL(string: "\(Self.espnCore)/\(game.sport)/leagues/\(coreLeague)/events/\(eventID)/competitions/\(game.competitionID ?? eventID)/odds?limit=10")
        else { return [] }
        do {
            let payload = try await getJSON(url)
            let items = payload["items"].isArray ? payload["items"].array : (payload["provider"].truthy || payload["homeTeamOdds"].truthy ? [payload] : [])
            let refs = Array(items.filter { Self.isBookmaker($0) }.prefix(8))
            var resolved: [(Int, JSON)] = []
            await withTaskGroup(of: (Int, JSON?).self) { group in
                for (i, item) in refs.enumerated() {
                    group.addTask { @MainActor in (i, try? await self.resolveOddsItem(item)) }
                }
                for await (i, book) in group { if let book { resolved.append((i, book)) } }
            }
            let available = resolved.sorted { $0.0 < $1.0 }.map(\.1).filter { book in
                let ml = Self.hasPrice(Self.moneylinePrice(book, "home")) || Self.hasPrice(Self.moneylinePrice(book, "away")) || Self.hasPrice(Self.moneylinePrice(book, "draw"))
                let hasLines = !book["overUnder"].isNull || !book["spread"].isNull || !book["homeTeamOdds"]["spread"].isNull || ml
                let hasPrices = Self.hasPrice(book["overOdds"] ?? book["overUnderOdds"]) || Self.hasPrice(book["underOdds"] ?? book["underUnderOdds"])
                    || Self.hasPrice(book["homeTeamOdds"]["spreadOdds"]) || Self.hasPrice(book["awayTeamOdds"]["spreadOdds"]) || ml
                return Self.isBookmaker(book) && hasLines && hasPrices
            }
            // Stable sort: live books first while live, last otherwise.
            let preferred = available.enumerated().sorted { a, b in
                let la = Self.isLiveBook(a.element) ? 1 : 0, lb = Self.isLiveBook(b.element) ? 1 : 0
                if la != lb { return game.state == .live ? la > lb : la < lb }
                return a.offset < b.offset
            }.map(\.element)
            eventOddsCache[game.id] = (now, preferred)
            return preferred
        } catch {
            eventOddsCache[game.id] = (now, [])
            return []
        }
    }

    private func loadOdds(_ games: [Game], now: Ms) async {
        let queue = GameQueue(games)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(6, games.count) {
                group.addTask { @MainActor in
                    while let game = queue.next() {
                        let sb = self.competitions[game.id]?["odds"][0] ?? .null
                        let hasScoreboardLines = game.state != .live && Self.isBookmaker(sb)
                            && Self.hasPrice(sb["homeTeamOdds"]["spreadOdds"]) && Self.hasPrice(sb["awayTeamOdds"]["spreadOdds"])
                            && Self.hasPrice(sb["overOdds"]) && Self.hasPrice(sb["underOdds"])
                            && Self.hasPrice(Self.moneylinePrice(sb, "home")) && Self.hasPrice(Self.moneylinePrice(sb, "away"))
                        if !hasScoreboardLines { self.oddsBooks[game.id] = await self.fetchEventOdds(game, now: now) }
                        if let current = self.byId(game.id) { self.boards[game.id] = self.makeOdds(current) }
                    }
                }
            }
        }
        emit()
    }

    func loadDetails(_ id: String) {
        guard let game = byId(id), let eventID = game.eventID, details[id] == nil, !detailLoading.contains(id),
              let path = Self.leagues[game.league]?.0,
              let url = URL(string: "\(Self.espn)/\(path)/summary?event=\(eventID)") else { return }
        detailLoading.insert(id)
        Task {
            if let json = try? await getJSON(url) { details[id] = json }
            detailLoading.remove(id)
            detailsVersion += 1
        }
    }

    struct StatRow: Hashable { var label: String; var awayValue: String; var homeValue: String }

    func stats(_ game: Game) -> [StatRow] {
        _ = detailsVersion
        let teams = details[game.id]?["boxscore"]["teams"].array ?? []
        let home = teams.first { $0["team"]["id"].string == game.home.id }
        let away = teams.first { $0["team"]["id"].string == game.away.id }
        guard let home, let away else { return [] }
        func index(_ t: JSON) -> [(String, JSON)] { t["statistics"].array.map { (($0["name"].text ?? $0["label"].string) ?? "", $0) } }
        let awayStats = index(away)
        let homeStats = Dictionary(index(home), uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        return awayStats.compactMap { key, a in
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            guard let h = homeStats[key] else { return nil }
            let label = a["label"].text ?? a["displayName"].text ?? a["name"].text ?? key
            let av = a["displayValue"] ?? a["value"], hv = h["displayValue"] ?? h["value"]
            guard let avs = av.string, let hvs = hv.string else { return nil }
            return StatRow(label: label, awayValue: avs, homeValue: hvs)
        }
    }

    private func followedLeagues() -> [String] {
        let wanted = Store.shared.data?.settings.sports.filter { Self.leagues[$0] != nil } ?? []
        return wanted.isEmpty ? Array(Self.leagues.keys).sorted() : wanted
    }

    /// Refetches today's scoreboards (at most every 25 seconds unless forced).
    func refresh(_ now: Ms = TO.now(), force: Bool = false) {
        let requestedDay = TO.dayKey(now)
        if loading {
            if force || requestedDay != loadingDayKey { refreshQueued = true }
            return
        }
        if !force && requestedDay == updatedDayKey && now - updatedAt < 25_000 { return }
        loading = true
        loadingDayKey = requestedDay
        failed = false
        emit()
        let leagues = followedLeagues()
        let group = cfbGroup
        Task {
            var results: [String: [(Game, JSON)]] = [:]
            var failures = 0
            await withTaskGroup(of: (String, [(Game, JSON)]?).self) { tasks in
                for league in leagues {
                    tasks.addTask { @MainActor in (league, try? await self.fetchLeague(league, group: group, now: now)) }
                }
                for await (league, games) in tasks {
                    if let games { results[league] = games } else { failures += 1 }
                }
            }
            let completedAt = TO.now()
            if TO.dayKey(completedAt) != requestedDay {
                loading = false; loadingDayKey = ""; updatedAt = 0; updatedDayKey = ""; refreshQueued = false
                refresh(completedAt)
                return
            }
            let (dayStart, dayEnd) = Self.todayBounds(completedAt)
            for (league, fetchedPairs) in results {
                let relevant = fetchedPairs.filter { g, _ in (g.start >= dayStart && g.start < dayEnd) || g.state == .live || (g.state == .final && g.start >= dayStart - TO.DAY) }
                let fetched = league == "ncaaf" && group == "80" ? relevant.filter { g, _ in g.home.rank != nil || g.away.rank != nil } : relevant
                for (g, comp) in fetched { competitions[g.id] = comp }
                let previous = cache[league] ?? []
                let fetchedIds = Set(fetched.map { $0.0.id })
                var byId: [String: Game] = [:]
                var order: [String] = []
                func put(_ g: Game) { if byId[g.id] == nil { order.append(g.id) }; byId[g.id] = g }
                previous.filter { $0.state == .final && $0.start >= dayStart - TO.DAY }.forEach(put)
                previous.filter { $0.start >= dayStart && $0.start < dayEnd && ($0.state == .scheduled || $0.state == .live) && !fetchedIds.contains($0.id) }.forEach(put)
                fetched.forEach { put($0.0) }
                let games = order.compactMap { byId[$0] }
                cache[league] = games
                for g in games { boards[g.id] = makeOdds(g) }
            }
            failed = failures > 0 && results.isEmpty
            offline = failed
            updatedAt = completedAt
            updatedDayKey = requestedDay
            loading = false
            loadingDayKey = ""
            emit()
            Task { if await loadOldBetGames(completedAt) { emit() } }
            let todays = cache.values.flatMap { $0 }.filter { $0.start >= dayStart - TO.DAY }
            Task { await loadOdds(todays, now: completedAt) }
            if refreshQueued {
                refreshQueued = false
                updatedAt = 0
                refresh()
            }
        }
    }

    /// Keep old unresolved tickets gradeable after their games fall out of the current scoreboard cache.
    private func loadOldBetGames(_ now: Ms) async -> Bool {
        guard let bets = Store.shared.data?.bets else { return false }
        var wanted: [String: (league: String, day: String, ids: Set<String>)] = [:]
        for bet in bets where bet.status == "open" {
            for leg in bet.legs where leg.result == "pending" {
                guard let gameId = leg.gameId, let league = leg.league, Self.leagues[league] != nil, byId(gameId) == nil else { continue }
                let day = TO.dayKey(bet.placedAt)
                let key = "\(league)|\(day)"
                var entry = wanted[key] ?? (league, day, [])
                entry.ids.insert(gameId)
                wanted[key] = entry
            }
        }
        var loaded = false
        for job in wanted.values {
            guard let games = try? await fetchLeague(job.league, group: cfbGroup, now: TO.dayStart(job.day) + 12 * TO.HOUR) else { continue }
            for (game, comp) in games where job.ids.contains(game.id) || job.ids.contains(game.eventID ?? "") || job.ids.contains(where: { $0.hasSuffix("-\(game.eventID ?? "")") }) {
                var list = cache[game.league] ?? []
                if !list.contains(where: { $0.id == game.id }) {
                    competitions[game.id] = comp
                    var suspended = OddsBoard()
                    suspended.suspended = true
                    boards[game.id] = suspended
                    list.append(game)
                    cache[game.league] = list
                    loaded = true
                }
            }
        }
        return loaded
    }

    /// Tomorrow's games, fetched in the background and refreshed every 10 minutes.
    func refreshUpcoming(_ now: Ms = TO.now()) {
        let leagues = followedLeagues()
        let fresh = TO.dayKey(now) == upcomingDayKey && now - upcomingAt < Self.upcomingTTL && leagues.allSatisfy { upcoming[$0] != nil }
        if upcomingLoading || fresh { return }
        upcomingLoading = true
        let todayEnd = Self.todayBounds(now).1
        let weekEnd = todayEnd + Double(Self.upcomingDays) * TO.DAY
        let first = Self.espnDayKey(todayEnd)
        let days = (0...Self.upcomingDays).map { Self.shiftDayKey(first, $0) }
        let group = cfbGroup
        Task {
            var any = false
            await withTaskGroup(of: (String, [(Game, JSON)]?).self) { tasks in
                for league in leagues {
                    tasks.addTask { @MainActor in (league, try? await self.fetchLeague(league, group: group, now: now, dates: days)) }
                }
                for await (league, result) in tasks {
                    // A failed league keeps what it had until the next scheduled refresh.
                    guard let result else { if upcoming[league] == nil { upcoming[league] = [] }; continue }
                    any = true
                    var games = result.filter { g, _ in g.start >= todayEnd && g.start < weekEnd && g.state != .final }
                    if league == "ncaaf" && group == "80" { games = games.filter { g, _ in g.home.rank != nil || g.away.rank != nil } }
                    for (g, comp) in games {
                        competitions[g.id] = comp
                        boards[g.id] = makeOdds(g)
                    }
                    upcoming[league] = games.map(\.0)
                }
            }
            upcomingAt = TO.now()
            upcomingDayKey = TO.dayKey(now)
            upcomingLoading = false
            if any { emit() }
            loadViewedDayOdds()
        }
    }

    @ObservationIgnored private var viewingDay = 0
    /// Home is showing a future day: load its odds once (they aren't fetched in the background).
    func setViewingDay(_ day: Int) {
        viewingDay = day
        loadViewedDayOdds()
    }

    private func loadViewedDayOdds() {
        guard viewingDay > 0 else { return }
        let now = TO.now()
        let games = upcoming.values.flatMap { $0 }.filter { Self.dayOffset($0.start, now) == viewingDay && !oddsRequested.contains($0.id) }
        guard !games.isEmpty else { return }
        games.forEach { oddsRequested.insert($0.id) }
        Task { await loadOdds(games, now: now) }
    }

    func setGroup(_ group: String) {
        cfbGroup = Self.cfbGroups.contains { $0.0 == group } ? group : "all"
        cache["ncaaf"] = nil; updatedAt = 0; updatedDayKey = ""
        upcoming["ncaaf"] = nil; upcomingAt = 0
        if loading { refreshQueued = true } else { refresh() }
        refreshUpcoming()
    }

    private func emit() { version &+= 1 }

    // MARK: Lookups

    func byId(_ id: String) -> Game? {
        _ = version // views that look games up re-render when scores change
        for games in cache.values { if let g = games.first(where: { $0.id == id || $0.eventID == id }) { return g } }
        for games in upcoming.values { if let g = games.first(where: { $0.id == id || $0.eventID == id }) { return g } }
        return nil
    }

    func odds(_ id: String) -> OddsBoard? {
        _ = version
        guard let g = byId(id) else { return nil }
        return boards[g.id] ?? OddsBoard.empty
    }

    /// Board for Home. `day`: 0 = today (live and today's games), 1 = tomorrow.
    func board(_ now: Ms, day: Int, leagues: [String]) -> [Game] {
        _ = version
        if day > 0 {
            return leagues.flatMap { upcoming[$0] ?? [] }
                .filter { Self.dayOffset($0.start, now) == day }
                .sorted { $0.start < $1.start }
        }
        let (start, end) = Self.todayBounds(now)
        return leagues.flatMap { cache[$0] ?? [] }
            .filter { ($0.start >= start && $0.start < end) || $0.state == .live }
            .sorted { ($0.state == .live ? 0 : 1, $0.start) < ($1.state == .live ? 0 : 1, $1.start) }
    }
}

/// Hands out games to the odds workers one at a time.
private final class GameQueue {
    private var items: ArraySlice<Game>
    init(_ games: [Game]) { items = games[...] }
    func next() -> Game? { items.popFirst() }
}

/// One way to read games, odds and picks: ESPN first, the simulated feed when a game isn't from ESPN.
enum Feed {
    static var live: LiveFeed { LiveFeed.shared }

    static func game(_ id: String, _ now: Ms = TO.now()) -> Game? { live.byId(id) ?? Sim.game(id, now) }

    static func odds(_ id: String, _ now: Ms = TO.now()) -> OddsBoard { live.odds(id) ?? Sim.odds(id, now) ?? .empty }

    /// Home's board. Without ESPN it falls back to the simulated games (today only).
    static func board(_ now: Ms = TO.now(), day: Int = 0, leagues: [String] = Sim.leagueOrder) -> [Game] {
        if live.offline { return day > 0 ? [] : Sim.board(now, leagues: leagues) }
        return live.board(now, day: day, leagues: leagues)
    }

    static func currentSelection(_ selId: String, _ now: Ms = TO.now()) -> (sel: Selection?, open: Bool)? {
        let parts = selId.split(separator: "|").map(String.init)
        let ref = parts.first ?? ""
        if parts.count > 1 && parts[1] == "race" { return Races.shared.currentSelection(selId) }
        if parts.count > 1 && parts[1] == "pred" { return nil }
        guard let game = live.byId(ref) else { return Sim.currentSelection(selId, now) }
        let sel = live.odds(game.id)?.all.first { $0.id == selId }
        let suspended = live.odds(game.id)?.suspended ?? true
        return (sel, sel != nil && !suspended && game.state != .final)
    }

    /// Grades a pick: pending | won | lost | push | void.
    static func grade(_ leg: Leg, _ now: Ms = TO.now()) -> String {
        if leg.market == "race" { return Races.shared.grade(leg, now) }
        if leg.market == "pred" { return "pending" }
        guard let gameId = leg.gameId else { return "pending" }
        guard let game = live.byId(gameId) else { return Sim.grade(leg, now) }
        if game.state == .postponed || game.state == .canceled { return "void" }
        if game.state != .final { return "pending" }
        return Sim.gradeScore(market: leg.market, side: leg.side ?? "", line: leg.line, H: game.homeScore, A: game.awayScore)
    }

    static func liveStanding(_ leg: Leg) -> String {
        Sim.liveStanding(leg, leg.gameId.flatMap { game($0) })
    }
}
