import Foundation

/// Simulated sports feed, fair odds and grading. A port of the web demo's sim.js.
///
/// Every league runs on rolling 20-minute slots. Each game lasts 12 real minutes, and every score and price is a
/// pure function of the game ID and the clock, so the same game looks the same on every refresh (and on the web).
/// The app only shows these when ESPN can't be reached.
enum Sim {
    static let SLOT: Ms = 20 * TO.MIN
    static let DURATION: Ms = 12 * TO.MIN
    static let STEP: Ms = 5000
    static let STEPS = Int(DURATION / STEP) // 144
    static let oddsBucketLive: Ms = 15_000
    static let oddsBucketPre: Ms = 2 * TO.MIN

    struct Sport {
        var periods: Int
        var periodMin: Double = 0
        var marginSigma: Double
        var totalSigma: Double
        var perTeam: Double
        var homeEdge: Double
        var spread: String?
        var spreadLabel: String = "Spread"
        var draw = false
        var discrete: Bool
        var unit: String
    }

    static let sports: [String: Sport] = [
        "football": Sport(periods: 4, periodMin: 15, marginSigma: 13.5, totalSigma: 10, perTeam: 21.6, homeEdge: 1.5, spread: "dynamic", spreadLabel: "Spread", discrete: false, unit: "pts"),
        "basketball": Sport(periods: 4, periodMin: 12, marginSigma: 12, totalSigma: 15, perTeam: 111, homeEdge: 2.5, spread: "dynamic", spreadLabel: "Spread", discrete: false, unit: "pts"),
        "baseball": Sport(periods: 9, marginSigma: 4.2, totalSigma: 3.2, perTeam: 4.3, homeEdge: 0.25, spread: "fixed", spreadLabel: "Run line", discrete: true, unit: "runs"),
        "hockey": Sport(periods: 3, periodMin: 20, marginSigma: 2.4, totalSigma: 2.2, perTeam: 3.0, homeEdge: 0.2, spread: "fixed", spreadLabel: "Puck line", discrete: true, unit: "goals"),
        "soccer": Sport(periods: 2, marginSigma: 1.6, totalSigma: 1.6, perTeam: 1.35, homeEdge: 0.3, spread: nil, draw: true, discrete: true, unit: "goals"),
    ]

    struct League {
        var id: String
        var title: String
        var short: String
        var sport: String
        var offset: Ms
        var stagger: Ms
        var perSlot: Int
        var gp: Int
        var simulated = false
        var teams: [Team]
    }

    private static func t(_ abbr: String, _ name: String, _ city: String, _ color: String) -> Team {
        Team(abbr: abbr, name: name, city: city, color: color)
    }

    static let leagues: [String: League] = [
        "nfl": League(id: "nfl", title: "NFL", short: "NFL", sport: "football", offset: 0, stagger: 4 * TO.MIN, perSlot: 2, gp: 4, teams: [
            t("KC", "Chiefs", "Kansas City", "#E31837"), t("BUF", "Bills", "Buffalo", "#00338D"), t("PHI", "Eagles", "Philadelphia", "#004C54"), t("DAL", "Cowboys", "Dallas", "#003594"), t("SF", "49ers", "San Francisco", "#AA0000"), t("GB", "Packers", "Green Bay", "#203731"), t("BAL", "Ravens", "Baltimore", "#241773"), t("DET", "Lions", "Detroit", "#0076B6"), t("MIA", "Dolphins", "Miami", "#008E97"), t("CIN", "Bengals", "Cincinnati", "#FB4F14"), t("LAR", "Rams", "Los Angeles", "#003594"), t("NYJ", "Jets", "New York", "#125740"),
        ]),
        "ncaaf": League(id: "ncaaf", title: "College Football", short: "NCAAF", sport: "football", offset: 15 * TO.MIN, stagger: 3 * TO.MIN, perSlot: 2, gp: 5, teams: [
            t("BYU", "Cougars", "BYU", "#002E5D"), t("UTAH", "Utes", "Utah", "#CC0000"), t("ALA", "Crimson Tide", "Alabama", "#9E1B32"), t("UGA", "Bulldogs", "Georgia", "#BA0C2F"), t("OSU", "Buckeyes", "Ohio State", "#BB0000"), t("MICH", "Wolverines", "Michigan", "#00274C"), t("TEX", "Longhorns", "Texas", "#BF5700"), t("ORE", "Ducks", "Oregon", "#154733"), t("USC", "Trojans", "USC", "#990000"), t("ND", "Fighting Irish", "Notre Dame", "#0C2340"),
        ]),
        "nba": League(id: "nba", title: "NBA", short: "NBA", sport: "basketball", offset: 3 * TO.MIN, stagger: 4 * TO.MIN, perSlot: 2, gp: 12, teams: [
            t("BOS", "Celtics", "Boston", "#007A33"), t("LAL", "Lakers", "Los Angeles", "#552583"), t("GSW", "Warriors", "Golden State", "#1D428A"), t("DEN", "Nuggets", "Denver", "#0E2240"), t("MIL", "Bucks", "Milwaukee", "#00471B"), t("PHX", "Suns", "Phoenix", "#1D1160"), t("MIA", "Heat", "Miami", "#98002E"), t("NYK", "Knicks", "New York", "#F58426"), t("DAL", "Mavericks", "Dallas", "#00538C"), t("OKC", "Thunder", "Oklahoma City", "#007AC1"), t("UTA", "Jazz", "Utah", "#4B2A8E"), t("MIN", "Timberwolves", "Minnesota", "#236192"),
        ]),
        "mlb": League(id: "mlb", title: "MLB", short: "MLB", sport: "baseball", offset: 6 * TO.MIN, stagger: 4 * TO.MIN, perSlot: 2, gp: 158, teams: [
            t("NYY", "Yankees", "New York", "#0C2340"), t("LAD", "Dodgers", "Los Angeles", "#005A9C"), t("ATL", "Braves", "Atlanta", "#CE1141"), t("HOU", "Astros", "Houston", "#EB6E1F"), t("CHC", "Cubs", "Chicago", "#0E3386"), t("BOS", "Red Sox", "Boston", "#BD3039"), t("SEA", "Mariners", "Seattle", "#005C5C"), t("SD", "Padres", "San Diego", "#7A5C3A"), t("PHI", "Phillies", "Philadelphia", "#E81828"), t("TOR", "Blue Jays", "Toronto", "#134A8E"),
        ]),
        "nhl": League(id: "nhl", title: "NHL", short: "NHL", sport: "hockey", offset: 9 * TO.MIN, stagger: 4 * TO.MIN, perSlot: 2, gp: 8, teams: [
            t("COL", "Avalanche", "Colorado", "#6F263D"), t("VGK", "Golden Knights", "Vegas", "#8C7650"), t("EDM", "Oilers", "Edmonton", "#FF4C00"), t("TOR", "Maple Leafs", "Toronto", "#00205B"), t("BOS", "Bruins", "Boston", "#A87D00"), t("NYR", "Rangers", "New York", "#0038A8"), t("TBL", "Lightning", "Tampa Bay", "#002868"), t("FLA", "Panthers", "Florida", "#C8102E"), t("DAL", "Stars", "Dallas", "#006847"), t("CAR", "Hurricanes", "Carolina", "#CC0000"),
        ]),
        "epl": League(id: "epl", title: "Premier League", short: "EPL", sport: "soccer", offset: 12 * TO.MIN, stagger: 4 * TO.MIN, perSlot: 2, gp: 6, teams: [
            t("ARS", "Arsenal", "London", "#EF0107"), t("MCI", "Man City", "Manchester", "#4A90C8"), t("LIV", "Liverpool", "Liverpool", "#C8102E"), t("CHE", "Chelsea", "London", "#034694"), t("MUN", "Man United", "Manchester", "#DA291C"), t("TOT", "Tottenham", "London", "#132257"), t("NEW", "Newcastle", "Newcastle", "#3A3A3A"), t("AVL", "Aston Villa", "Birmingham", "#670E36"),
        ]),
        "sim": League(id: "sim", title: "Sim League", short: "SIM", sport: "basketball", offset: 1 * TO.MIN, stagger: 6 * TO.MIN, perSlot: 3, gp: 20, simulated: true, teams: [
            t("NCV", "Volts", "Neon City", "#00B8D4"), t("HBK", "Kraken", "Harbor", "#1E5EB8"), t("DSC", "Scorpions", "Desert", "#E09A00"), t("SMY", "Yetis", "Summit", "#7E8CC7"), t("BYG", "Gators", "Bayou", "#2E7D32"), t("MTC", "Comets", "Metro", "#D93A3A"), t("PRS", "Storm", "Prairie", "#8E3FB5"), t("IBA", "Anchors", "Iron Bay", "#4F6572"),
        ]),
    ]

    static let realLeagues = ["nfl", "ncaaf", "nba", "mlb", "nhl", "epl"]
    static let leagueOrder = ["nfl", "ncaaf", "nba", "mlb", "nhl", "epl", "sim"]

    static func strength(_ league: String, _ team: Team) -> Double { 0.9 * TO.unit("str-\(league)-\(team.abbr)") }

    // MARK: Scoring timeline

    struct Event { var step: Int; var side: String; var pts: Int }
    struct Timeline { var events: [Event]; var extra: GameOT?; var finalHome: Int; var finalAway: Int }
    private static var timelines: [String: Timeline] = [:]

    private static func scoringRoll(_ sport: String, _ r: Double, _ r2: Double, _ mult: Double) -> Int? {
        switch sport {
        case "football":
            if r < 0.0165 * mult { return r2 < 0.9 ? 7 : r2 < 0.95 ? 6 : 8 }
            if r < (0.0165 + 0.0115) * mult { return 3 }
            return nil
        case "basketball":
            if r < 0.335 * mult { return r2 < 0.3 ? 3 : 2 }
            return nil
        case "baseball":
            if r < 0.042 * mult { return r2 < 0.68 ? 1 : r2 < 0.88 ? 2 : r2 < 0.97 ? 3 : 4 }
            return nil
        case "hockey": return r < 0.021 * mult ? 1 : nil
        case "soccer": return r < 0.0095 * mult ? 1 : nil
        default: return nil
        }
    }

    private static func timeline(_ g: Game) -> Timeline {
        if let hit = timelines[g.id] { return hit }
        let L = leagues[g.league]!
        let S = sports[L.sport]!
        let rand = TO.RNG("game-\(g.id)")
        let d = strength(g.league, g.home) - strength(g.league, g.away)
        let homeBoost = S.homeEdge / S.perTeam
        let multHome = max(0.3, 1 + 0.06 * d + homeBoost)
        let multAway = max(0.3, 1 - 0.06 * d)
        var events: [Event] = []
        var h = 0, a = 0
        for step in 0..<STEPS {
            for side in ["away", "home"] {
                let r = rand(), r2 = rand()
                if L.sport == "baseball" {
                    let half = step / (STEPS / 18)
                    if (half % 2 == 0) != (side == "away") { continue }
                }
                if let pts = scoringRoll(L.sport, r, r2, side == "home" ? multHome : multAway) {
                    if side == "home" { h += pts } else { a += pts }
                    events.append(Event(step: step, side: side, pts: pts))
                }
            }
        }
        var extra: GameOT?
        if h == a && !S.draw {
            let r = rand()
            let side = r < 0.5 + 0.1 * d ? "home" : "away"
            var pts = 1, lose = 0, label = "OT"
            if L.sport == "football" { pts = rand() < 0.6 ? 3 : 6 }
            if L.sport == "basketball" {
                pts = 4 + Int((rand() * 7).rounded(.down))
                lose = max(0, pts - 1 - Int((rand() * 5).rounded(.down)))
            }
            if L.sport == "baseball" { label = "10" }
            if L.sport == "hockey" { _ = rand() }
            extra = GameOT(side: side, label: label)
            if side == "home" { h += pts; a += lose } else { a += pts; h += lose }
        }
        let tl = Timeline(events: events, extra: extra, finalHome: h, finalAway: a)
        timelines[g.id] = tl
        return tl
    }

    private static func clockText(_ sport: String, _ progIn: Double) -> String {
        let S = sports[sport]!
        let prog = TO.clamp(progIn, 0, 0.9999)
        if sport == "baseball" {
            let half = Int((prog * 18).rounded(.down))
            return "\(half % 2 == 0 ? "Top" : "Bot") \(Fmt.ordinal(half / 2 + 1))"
        }
        if sport == "soccer" { return "\(Int((prog * 90).rounded(.down)) + 1)'" }
        let x = prog * Double(S.periods)
        let per = Int(x.rounded(.down))
        let secsLeft = jsRoundInt((1 - (x - Double(per))) * S.periodMin * 60)
        let clock = "\(secsLeft / 60):\(String(format: "%02d", secsLeft % 60))"
        if sport == "hockey" { return "\(Fmt.ordinal(per + 1)) · \(clock)" }
        return "Q\(per + 1) · \(clock)"
    }

    // MARK: Games

    static func game(_ id: String, _ now: Ms = TO.now()) -> Game? {
        let parts = id.split(separator: "-").map(String.init)
        guard parts.count == 3, let L = leagues[parts[0]], let slot = Int(parts[1]), let idx = Int(parts[2]) else { return nil }
        let order = TO.shuffle(Array(0..<L.teams.count), TO.RNG("slot-\(L.id)-\(slot)"))
        guard idx * 2 + 1 < order.count else { return nil }
        let home = L.teams[order[idx * 2]]
        let away = L.teams[order[idx * 2 + 1]]
        let start = Double(slot) * SLOT + L.offset + Double(idx) * L.stagger
        var g = Game(id: id, league: L.id, sport: L.sport, start: start, end: start + DURATION, home: home, away: away)
        g.simulated = L.simulated
        let elapsed = now - start
        let naturalPpd = !L.simulated && TO.hash("ppd-\(id)") % 29 == 0
        if naturalPpd && now >= start - 8 * TO.MIN {
            g.state = .postponed
            g.statusText = "Postponed"
            return g
        }
        if elapsed < 0 {
            g.statusText = Fmt.time(start)
            return g
        }
        let tl = timeline(g)
        if elapsed >= DURATION {
            g.state = .final
            g.progress = 1
            g.homeScore = tl.finalHome
            g.awayScore = tl.finalAway
            g.ot = tl.extra
            g.statusText = tl.extra.map { "Final/\($0.label)" } ?? "Final"
            g.endedAt = start + DURATION
            return g
        }
        let steps = Int((elapsed / STEP).rounded(.down))
        var h = 0, a = 0
        for ev in tl.events {
            if ev.step >= steps { break }
            if ev.side == "home" { h += ev.pts } else { a += ev.pts }
        }
        g.state = .live
        g.homeScore = h
        g.awayScore = a
        g.progress = elapsed / DURATION
        g.clock = clockText(L.sport, g.progress)
        g.statusText = g.clock
        g.stepsPlayed = steps
        return g
    }

    /// Games on the board right now: recent finals, live games and the next ~45 minutes.
    static func board(_ now: Ms = TO.now(), leagues wanted: [String] = leagueOrder) -> [Game] {
        var list: [Game] = []
        for league in wanted {
            guard let L = leagues[league] else { continue }
            let base = Int(((now - L.offset) / SLOT).rounded(.down))
            for slot in (base - 1)...(base + 2) {
                for i in 0..<L.perSlot {
                    guard let g = game("\(league)-\(slot)-\(i)", now) else { continue }
                    if g.state == .scheduled && g.start - now > 45 * TO.MIN { continue }
                    if g.state == .final && now - (g.endedAt ?? g.end) > 8 * TO.MIN { continue }
                    if g.state == .postponed && now > g.end { continue }
                    list.append(g)
                }
            }
        }
        let rank: [GameState: Int] = [.live: 0, .scheduled: 1, .postponed: 2, .final: 3, .canceled: 3]
        return list.sorted { (rank[$0.state]!, $0.start) < (rank[$1.state]!, $1.start) }
    }

    // MARK: Odds

    private static var oddsCache: [String: OddsBoard] = [:]

    private static func expectedMargin(_ g: Game, _ now: Ms) -> Double {
        let S = sports[g.sport]!
        let d = strength(g.league, g.home) - strength(g.league, g.away)
        var mu = S.perTeam * 0.12 * d + S.homeEdge
        if g.state == .scheduled { mu += 0.05 * S.marginSigma * TO.unit("drift-\(g.id)-\(Int((now / oddsBucketPre).rounded(.down)))") }
        return mu
    }

    private static func computeOdds(_ g: Game, _ now: Ms) -> OddsBoard {
        let S = sports[g.sport]!
        let rem = g.state == .live ? 1 - g.progress : 1
        let suspended = !(g.state == .scheduled || g.state == .live) || (g.state == .live && rem < 0.03)
        let mu0 = expectedMargin(g, now)
        let minSD = S.discrete ? 0.35 : 0.8
        let mu: Double, sd: Double
        if g.state == .live {
            mu = Double(g.homeScore - g.awayScore) + mu0 * rem
            sd = max(S.marginSigma * pow(rem, 0.4), minSD)
        } else { mu = mu0; sd = S.marginSigma }
        func sel(_ market: String, _ side: String, _ line: Double?, _ p: Double) -> Selection {
            Selection(id: "\(g.id)|\(market)|\(side)", kind: "game", gameId: g.id, market: market, side: side, line: line, price: OddsMath.fromProb(p))
        }
        var board = OddsBoard()
        if S.draw {
            let pHome = 1 - TO.phi((0.5 - mu) / sd)
            let pAway = TO.phi((-0.5 - mu) / sd)
            let pDraw = max(1 - pHome - pAway, 0.02)
            board.moneyline = [sel("ml", "away", nil, pAway), sel("ml", "draw", nil, pDraw), sel("ml", "home", nil, pHome)]
        } else {
            let pHome = TO.phi(mu / sd)
            board.moneyline = [sel("ml", "away", nil, 1 - pHome), sel("ml", "home", nil, pHome)]
        }
        if let spread = S.spread {
            let homeLine = spread == "fixed" ? (mu >= 0 ? -1.5 : 1.5) : -TO.hook(mu)
            let pCover = 1 - TO.phi((-homeLine - mu) / sd)
            board.spread = [sel("spread", "away", -homeLine, 1 - pCover), sel("spread", "home", homeLine, pCover)]
        }
        let base = g.league == "sim" ? 222 : S.perTeam * 2
        let baseTotal = base * (1 + 0.06 * TO.unit("total-\(g.id)"))
        let projected: Double, sdT: Double
        if g.state == .live {
            projected = Double(g.homeScore + g.awayScore) + baseTotal * rem
            sdT = max(S.totalSigma * pow(rem, 0.4), minSD)
        } else { projected = baseTotal; sdT = S.totalSigma }
        let line = TO.hook(projected)
        let pOver = 1 - TO.phi((line - projected) / sdT)
        board.total = [sel("total", "over", line, pOver), sel("total", "under", line, 1 - pOver)]
        board.suspended = suspended
        return board
    }

    /// Current odds for a game. Live prices refresh every 15 seconds; pre-game every 2 minutes.
    static func odds(_ id: String, _ now: Ms = TO.now()) -> OddsBoard? {
        guard let g = game(id, now) else { return nil }
        let bucketLen = g.state == .live ? oddsBucketLive : oddsBucketPre
        let bucket = (now / bucketLen).rounded(.down) * bucketLen
        let key = "\(id)|\(bucket)|\(g.state.rawValue)"
        if let hit = oddsCache[key] { return hit }
        let gb = g.state == .live ? (game(id, max(bucket, g.start)) ?? g) : g
        var o = computeOdds(gb.state == .live || gb.state == .scheduled ? gb : g, bucket)
        if g.state != .live && g.state != .scheduled { o.suspended = true }
        if g.state == .live && 1 - g.progress < 0.03 { o.suspended = true }
        o.updatedAt = bucket
        let prevT = bucket - bucketLen
        if let gp = game(id, prevT), gp.state == .live || gp.state == .scheduled {
            let prev = computeOdds(gp, prevT)
            for s in o.all {
                if let p = prev.all.first(where: { $0.id == s.id }), p.price != s.price { o.move[s.id] = s.price > p.price ? 1 : -1 }
            }
        }
        if oddsCache.count > 3000 { oddsCache.removeAll() }
        oddsCache[key] = o
        return o
    }

    static func currentSelection(_ selId: String, _ now: Ms = TO.now()) -> (sel: Selection?, open: Bool)? {
        let ref = String(selId.split(separator: "|").first ?? "")
        guard let o = odds(ref, now) else { return nil }
        let sel = o.all.first { $0.id == selId }
        return (sel, sel != nil && !o.suspended)
    }

    /// e.g. "Chiefs −3.5", "Over 44.5", "Lakers to win", "Draw".
    static func selectionLabel(_ sel: Selection, _ g: Game?) -> String {
        if sel.market == "race" { return Races.shared.horse(sel.horseId ?? Int(sel.side) ?? 1).name }
        if sel.market == "pred" { return sel.side == "yes" ? "Yes" : "No" }
        let team = g?.team(sel.side)
        switch sel.market {
        case "ml": return team.map { "\($0.name) to win" } ?? "Draw"
        case "spread": return "\(team?.name ?? "") \(OddsMath.fmtLine(sel.line ?? 0))"
        case "total": return "\(sel.side == "over" ? "Over" : "Under") \(OddsMath.fmtLine(sel.line ?? 0, signed: false))"
        default: return ""
        }
    }

    static func marketLabel(_ sel: Selection, _ g: Game?) -> String {
        switch sel.market {
        case "race": return "Race winner"
        case "pred": return "Prediction"
        case "ml": return "Moneyline"
        case "spread": return g.flatMap { sports[$0.sport]?.spreadLabel } ?? "Spread"
        default: return "Total"
        }
    }

    static func grade(_ leg: Leg, _ now: Ms = TO.now()) -> String {
        guard let gameId = leg.gameId, let g = game(gameId, now) else { return "pending" }
        if g.state == .postponed { return "void" }
        if g.state != .final { return "pending" }
        return gradeScore(market: leg.market, side: leg.side ?? "", line: leg.line, H: g.homeScore, A: g.awayScore)
    }

    static func gradeScore(market: String, side: String, line: Double?, H: Int, A: Int) -> String {
        switch market {
        case "ml":
            if side == "draw" { return H == A ? "won" : "lost" }
            if H == A { return "lost" }
            return (side == "home") == (H > A) ? "won" : "lost"
        case "spread":
            let m = Double(side == "home" ? H - A : A - H) + (line ?? 0)
            return m > 0 ? "won" : m < 0 ? "lost" : "push"
        case "total":
            let tot = Double(H + A)
            if tot == line { return "push" }
            return (side == "over") == (tot > (line ?? 0)) ? "won" : "lost"
        default: return "pending"
        }
    }

    /// How an open pick is doing right now: winning | losing | even | upcoming | void.
    static func liveStanding(_ leg: Leg, _ g: Game?) -> String {
        guard let g, g.state != .scheduled else { return "upcoming" }
        if g.state == .postponed || g.state == .canceled { return "void" }
        if leg.market == "total" {
            // Compare pace, not the raw score, so an over isn't "losing" in the first minute.
            let line = leg.line ?? 0
            let pace = g.progress > 0.05 ? Double(g.homeScore + g.awayScore) / g.progress : line
            if abs(pace - line) < 0.5 { return "even" }
            return (leg.side == "over") == (pace > line) ? "winning" : "losing"
        }
        let r = gradeScore(market: leg.market, side: leg.side ?? "", line: leg.line, H: g.homeScore, A: g.awayScore)
        if r == "push" { return "even" }
        if leg.market == "ml" && g.homeScore == g.awayScore { return leg.side == "draw" ? "winning" : "even" }
        return r == "won" ? "winning" : "losing"
    }
}
