import Foundation

// MARK: - Sports feed

struct Team: Codable, Hashable {
    var id: String?
    var abbr: String
    var name: String
    var fullName: String?
    var city: String = ""
    var color: String
    var logo: String?
    var rank: Int?
    var record: String?
}

enum GameState: String, Codable { case scheduled, live, final, postponed, canceled }

/// Overtime / extra innings detail on a simulated final.
struct GameOT: Hashable {
    var side: String
    var label: String
}

struct Game: Identifiable {
    var id: String
    var league: String
    var sport: String
    var start: Ms
    var end: Ms
    var state: GameState = .scheduled
    var home: Team
    var away: Team
    var homeScore = 0
    var awayScore = 0
    var progress: Double = 0
    var clock = ""
    var statusText = ""
    var ot: GameOT?
    var simulated = false
    var endedAt: Ms?
    var stepsPlayed = 0
    // ESPN
    var eventID: String?
    var competitionID: String?
    var period = 0
    var conferenceName = ""
    var otherConferenceLive = false

    func team(_ side: String) -> Team? { side == "home" ? home : side == "away" ? away : nil }
}

/// One price on the board: a moneyline side, spread, total, or race runner.
struct Selection: Codable, Hashable {
    var id: String
    var kind: String
    var gameId: String?
    var predId: String?
    var raceId: String?
    var horseId: Int?
    var market: String
    var side: String
    var line: Double?
    var price: Int
    var source: String?
}

struct OddsBoard {
    var moneyline: [Selection] = []
    var spread: [Selection] = []
    var total: [Selection] = []
    var suspended = true
    var move: [String: Int] = [:]
    var updatedAt: Ms = 0
    var all: [Selection] { moneyline + spread + total }

    static let empty = OddsBoard()
}

// MARK: - Bets

struct Leg: Codable, Hashable {
    var selId: String
    var kind: String
    var gameId: String?
    var predId: String?
    var raceId: String?
    var horseId: Int?
    var market: String
    var side: String?
    var line: Double?
    var price: Int
    var label: String
    var marketLabel: String
    var matchup: String
    var short: String?
    var league: String?
    var start: Ms?
    var result: String = "pending"
    var final: String?
    var text: String?
    var difficulty: String?

    init(selId: String, kind: String, market: String, price: Int, label: String, marketLabel: String, matchup: String) {
        self.selId = selId; self.kind = kind; self.market = market; self.price = price
        self.label = label; self.marketLabel = marketLabel; self.matchup = matchup
    }

    enum CodingKeys: String, CodingKey {
        case selId, kind, gameId, predId, raceId, horseId, market, side, line, price, label, marketLabel, matchup, short, league, start, result, final, text, difficulty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selId = (try? c.decode(String.self, forKey: .selId)) ?? ""
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "game"
        gameId = try? c.decodeIfPresent(String.self, forKey: .gameId)
        predId = try? c.decodeIfPresent(String.self, forKey: .predId)
        raceId = try? c.decodeIfPresent(String.self, forKey: .raceId)
        horseId = (try? c.decodeIfPresent(Int.self, forKey: .horseId)) ?? (try? c.decodeIfPresent(String.self, forKey: .horseId)).flatMap { $0.flatMap { Int($0) } }
        market = (try? c.decode(String.self, forKey: .market)) ?? "ml"
        side = try? c.decodeIfPresent(String.self, forKey: .side)
        line = try? c.decodeIfPresent(Double.self, forKey: .line)
        price = (try? c.decode(Int.self, forKey: .price)) ?? (try? c.decode(Double.self, forKey: .price)).map { Int($0) } ?? 100
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        marketLabel = (try? c.decode(String.self, forKey: .marketLabel)) ?? ""
        matchup = (try? c.decode(String.self, forKey: .matchup)) ?? ""
        short = try? c.decodeIfPresent(String.self, forKey: .short)
        league = try? c.decodeIfPresent(String.self, forKey: .league)
        start = try? c.decodeIfPresent(Double.self, forKey: .start)
        result = (try? c.decode(String.self, forKey: .result)) ?? "pending"
        final = try? c.decodeIfPresent(String.self, forKey: .final)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        difficulty = try? c.decodeIfPresent(String.self, forKey: .difficulty)
    }
}

struct Bet: Codable, Identifiable, Hashable {
    var id: String
    var kind: String
    var placedAt: Ms
    var dayKey: String
    var stake: Int
    var legs: [Leg]
    var decimal: Double
    var american: Int
    var boosted = false
    var insured = false
    var multiplier: Double = 1
    var status = "open"
    var payout = 0
    var settledAt: Ms?
    var insurancePaid: Bool?
    var deadline: Ms?
    var supabaseId: String?
    var supabaseSynced: Bool?
    var potentialPayout: Int?

    init(id: String, kind: String, placedAt: Ms, dayKey: String, stake: Int, legs: [Leg], decimal: Double, american: Int) {
        self.id = id; self.kind = kind; self.placedAt = placedAt; self.dayKey = dayKey
        self.stake = stake; self.legs = legs; self.decimal = decimal; self.american = american
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, placedAt, dayKey, stake, legs, decimal, american, boosted, insured, multiplier, status, payout, settledAt, insurancePaid, deadline, supabaseId, supabaseSynced, potentialPayout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "sports"
        placedAt = (try? c.decode(Double.self, forKey: .placedAt)) ?? 0
        dayKey = (try? c.decode(String.self, forKey: .dayKey)) ?? TO.dayKey(placedAt)
        stake = (try? c.decode(Int.self, forKey: .stake)) ?? 0
        legs = (try? c.decode([Leg].self, forKey: .legs)) ?? []
        decimal = (try? c.decode(Double.self, forKey: .decimal)) ?? 1
        american = (try? c.decode(Int.self, forKey: .american)) ?? OddsMath.fromDecimal(decimal)
        boosted = (try? c.decode(Bool.self, forKey: .boosted)) ?? false
        insured = (try? c.decode(Bool.self, forKey: .insured)) ?? false
        multiplier = (try? c.decode(Double.self, forKey: .multiplier)) ?? 1
        status = (try? c.decode(String.self, forKey: .status)) ?? "open"
        payout = (try? c.decode(Int.self, forKey: .payout)) ?? 0
        settledAt = try? c.decodeIfPresent(Double.self, forKey: .settledAt)
        insurancePaid = try? c.decodeIfPresent(Bool.self, forKey: .insurancePaid)
        deadline = try? c.decodeIfPresent(Double.self, forKey: .deadline)
        supabaseId = try? c.decodeIfPresent(String.self, forKey: .supabaseId)
        supabaseSynced = try? c.decodeIfPresent(Bool.self, forKey: .supabaseSynced)
        potentialPayout = try? c.decodeIfPresent(Int.self, forKey: .potentialPayout)
    }
}

// MARK: - User data

struct WalletData: Codable {
    struct Warned: Codable { var locked: String?; var low: String? }

    var dayKey: String
    var balance: Int
    var lockedOut = false
    var netByDay: [String: Int] = [:]
    var penaltyByDay: [String: Int] = [:]
    var overridesByDay: [String: Int] = [:]
    var usageByDay: [String: Int] = [:]
    var boostsByDay: [String: Int] = [:]
    var insuranceByWeek: [String: Int] = [:]
    var bonusDay: String?
    var bonusGranted = 0
    var streakDays = 0
    var warned = Warned()

    init(dayKey: String, balance: Int) {
        self.dayKey = dayKey
        self.balance = balance
    }

    enum CodingKeys: String, CodingKey {
        case dayKey, balance, lockedOut, netByDay, penaltyByDay, overridesByDay, usageByDay, boostsByDay, insuranceByWeek, bonusDay, bonusGranted, streakDays, warned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = (try? c.decode(String.self, forKey: .dayKey)) ?? TO.dayKey()
        balance = (try? c.decode(Int.self, forKey: .balance)) ?? Rules.daily
        lockedOut = (try? c.decode(Bool.self, forKey: .lockedOut)) ?? false
        netByDay = (try? c.decode([String: Int].self, forKey: .netByDay)) ?? [:]
        penaltyByDay = (try? c.decode([String: Int].self, forKey: .penaltyByDay)) ?? [:]
        overridesByDay = (try? c.decode([String: Int].self, forKey: .overridesByDay)) ?? [:]
        usageByDay = (try? c.decode([String: Int].self, forKey: .usageByDay)) ?? [:]
        boostsByDay = (try? c.decode([String: Int].self, forKey: .boostsByDay)) ?? [:]
        insuranceByWeek = (try? c.decode([String: Int].self, forKey: .insuranceByWeek)) ?? [:]
        bonusDay = try? c.decodeIfPresent(String.self, forKey: .bonusDay)
        bonusGranted = (try? c.decode(Int.self, forKey: .bonusGranted)) ?? 0
        streakDays = (try? c.decode(Int.self, forKey: .streakDays)) ?? 0
        warned = (try? c.decode(Warned.self, forKey: .warned)) ?? Warned()
    }
}

struct NotifySettings: Codable, Hashable {
    var settled = true
    var friends = true
    var lowTime = true
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settled = (try? c.decode(Bool.self, forKey: .settled)) ?? true
        friends = (try? c.decode(Bool.self, forKey: .friends)) ?? true
        lowTime = (try? c.decode(Bool.self, forKey: .lowTime)) ?? true
    }
}

struct PrivacySettings: Codable, Hashable {
    var record = true
    var minutes = true
    var bets = true
    init() {}
    init(record: Bool, minutes: Bool, bets: Bool) { self.record = record; self.minutes = minutes; self.bets = bets }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        record = (try? c.decode(Bool.self, forKey: .record)) ?? true
        minutes = (try? c.decode(Bool.self, forKey: .minutes)) ?? true
        bets = (try? c.decode(Bool.self, forKey: .bets)) ?? true
    }
}

/// Same keys as the web demo's `data.settings`, so Supabase `app_preferences` round-trips between them.
struct Settings: Codable, Equatable {
    var sports: [String] = Sim.realLeagues
    var showPredictions = true
    var showTodos = true
    var enforce = true
    var lockedApps: [String] = []
    var minLimit = 0
    var lowWarn = 10
    var notify = NotifySettings()
    var privacy = PrivacySettings()

    init() {}

    enum CodingKeys: String, CodingKey { case sports, showPredictions, showTodos, enforce, lockedApps, minLimit, lowWarn, notify, privacy }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sports = (try? c.decode([String].self, forKey: .sports)) ?? Sim.realLeagues
        showPredictions = (try? c.decode(Bool.self, forKey: .showPredictions)) ?? true
        showTodos = (try? c.decode(Bool.self, forKey: .showTodos)) ?? true
        enforce = (try? c.decode(Bool.self, forKey: .enforce)) ?? true
        lockedApps = (try? c.decode([String].self, forKey: .lockedApps)) ?? []
        minLimit = (try? c.decode(Int.self, forKey: .minLimit)) ?? 0
        lowWarn = (try? c.decode(Int.self, forKey: .lowWarn)) ?? 10
        notify = (try? c.decode(NotifySettings.self, forKey: .notify)) ?? NotifySettings()
        privacy = (try? c.decode(PrivacySettings.self, forKey: .privacy)) ?? PrivacySettings()
    }
}

struct FriendRequest: Codable, Hashable, Identifiable {
    var id: String
    var from: String?
    var to: String?
    var at: Ms
    var acceptAt: Ms?
}

/// A social team (a group of friends competing over dates). Named Squad to stay clear of sports teams.
struct Squad: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var start: String
    var end: String
    var members: [String]
    var owner: String
    var createdAt: Ms
    var shareKey: String?
    var remote: Bool?
    var rev: Int?
}

struct UserData: Codable {
    var v = 1
    var wallet: WalletData
    var bets: [Bet] = []
    var lastStake = 5
    var settings = Settings()
    var onboarded = false
    var friends: [String] = []
    var requestsIn: [FriendRequest] = []
    var requestsOut: [FriendRequest] = []
    var teams: [Squad] = []
    var feedFilter: String?

    init(wallet: WalletData) { self.wallet = wallet }

    enum CodingKeys: String, CodingKey { case v, wallet, bets, lastStake, settings, onboarded, friends, requestsIn, requestsOut, teams, feedFilter }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? c.decode(Int.self, forKey: .v)) ?? 1
        wallet = (try? c.decode(WalletData.self, forKey: .wallet)) ?? WalletData(dayKey: TO.dayKey(), balance: Rules.daily)
        bets = (try? c.decode([Bet].self, forKey: .bets)) ?? []
        lastStake = (try? c.decode(Int.self, forKey: .lastStake)) ?? 5
        settings = (try? c.decode(Settings.self, forKey: .settings)) ?? Settings()
        onboarded = (try? c.decode(Bool.self, forKey: .onboarded)) ?? false
        friends = (try? c.decode([String].self, forKey: .friends)) ?? []
        requestsIn = (try? c.decode([FriendRequest].self, forKey: .requestsIn)) ?? []
        requestsOut = (try? c.decode([FriendRequest].self, forKey: .requestsOut)) ?? []
        teams = (try? c.decode([Squad].self, forKey: .teams)) ?? []
        feedFilter = try? c.decodeIfPresent(String.self, forKey: .feedFilter)
    }
}

// MARK: - Accounts and people

struct ServerUser: Codable, Hashable {
    var id: String
    var username: String
    var email: String
    var photoUrl: String?
    var createdAt: String
    var isDemo = false
    var loginCount: Int?
}

struct Account: Codable, Hashable {
    var id: String
    var username: String
    var email: String
    var salt: String?
    var pw: String?
    var photo: String
    var createdAt: Ms
    var demo = false
    var server: ServerUser?
}

struct Tier: Hashable {
    var id: String
    var title: String
    var min: Int
    var color: String
    var icon: IconName
    var bonus: Int
    var boosts: Int
    var insurance: Int
}

struct Lockable: Hashable {
    var id: String
    var name: String
    var kind: String
    var pts: Int
    var color: String
    var note: String?
}

/// Someone on the leaderboard or in search: a demo profile, an account on this device, or a server user.
struct Person: Hashable {
    var username: String
    var name: String
    var photo: String
    var w = 0
    var l = 0
    var net = 0
    var tier = "rookie"
    var streak = 0
    var share = PrivacySettings()
    var fake = false
    var local = false
    var remote = false
    var accountId: String?
    var openBets: [Bet] = []
}

/// The wallet as the screens show it, computed from WalletData.
struct WalletView {
    var day: String
    var balance: Int
    var lockedOut: Bool
    var todayLimit: Int
    var tomorrowLimit: Int
    var yesterdayNet: Int
    var todayNet: Int
    var penaltyToday: Int
    var penaltyTomorrow: Int
    var emergencyToday: Int
    var overridesUsed: Int
    var used: Int
    var phoneLeft: Int
    var appsLocked: Bool
    var atRisk: Int
    var openCount: Int
    var tier: Tier
    var points: Int
    var streak: Int
    var multiplier: Double
    var boostsLeft: Int
    var insuranceLeft: Int
    var bonusToday: Int
}

struct Stats {
    struct Line { var w = 0; var l = 0; var net = 0 }
    var w: Int
    var l: Int
    var v: Int
    var net: Int
    var pct: Int?
    var best: Int
    var bySport: [String: Line]
    var recent: [String]
}

enum Rules {
    static let daily = 60
    static let maxLegs = 10
    static let overrideMinutes = 15
    static let overridePenalty = 30
    static let maxOverrides = 2
    static let todoMaxStake = 20
    static let boostPercent = 0.1
}
