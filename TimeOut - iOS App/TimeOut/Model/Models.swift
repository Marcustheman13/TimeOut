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

/// One price on the board: a winner side, margin, total, or race runner.
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

struct PointValueBoard {
    var winner: [Selection] = []
    var margin: [Selection] = []
    var total: [Selection] = []
    var suspended = true
    var move: [String: Int] = [:]
    var updatedAt: Ms = 0
    var all: [Selection] { winner + margin + total }

    static let empty = PointValueBoard()
}

// MARK: - Challenges

struct Pick: Codable, Hashable {
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
        market = (try? c.decode(String.self, forKey: .market)) ?? "winner"
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

struct Challenge: Codable, Identifiable, Hashable {
    var id: String
    var kind: String
    var placedAt: Ms
    var dayKey: String
    var pledgeMinutes: Int
    var picks: [Pick]
    var decimal: Double
    var american: Int
    var boosted = false
    var insured = false
    var multiplier: Double = 1
    var status = "open"
    var reward = 0
    var resolvedAt: Ms?
    var insurancePaid: Bool?
    var deadline: Ms?
    var supabaseId: String?
    var supabaseSynced: Bool?
    var potentialReward: Int?

    init(id: String, kind: String, placedAt: Ms, dayKey: String, pledgeMinutes: Int, picks: [Pick], decimal: Double, american: Int) {
        self.id = id; self.kind = kind; self.placedAt = placedAt; self.dayKey = dayKey
        self.pledgeMinutes = pledgeMinutes; self.picks = picks; self.decimal = decimal; self.american = american
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, placedAt, dayKey, pledgeMinutes, picks, decimal, american, boosted, insured, multiplier, status, reward, resolvedAt, insurancePaid, deadline, supabaseId, supabaseSynced, potentialReward
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "sports"
        placedAt = (try? c.decode(Double.self, forKey: .placedAt)) ?? 0
        dayKey = (try? c.decode(String.self, forKey: .dayKey)) ?? TO.dayKey(placedAt)
        pledgeMinutes = (try? c.decode(Int.self, forKey: .pledgeMinutes)) ?? 0
        picks = (try? c.decode([Pick].self, forKey: .picks)) ?? []
        decimal = (try? c.decode(Double.self, forKey: .decimal)) ?? 1
        american = (try? c.decode(Int.self, forKey: .american)) ?? PointValueMath.fromDecimal(decimal)
        boosted = (try? c.decode(Bool.self, forKey: .boosted)) ?? false
        insured = (try? c.decode(Bool.self, forKey: .insured)) ?? false
        multiplier = (try? c.decode(Double.self, forKey: .multiplier)) ?? 1
        status = (try? c.decode(String.self, forKey: .status)) ?? "open"
        reward = (try? c.decode(Int.self, forKey: .reward)) ?? 0
        resolvedAt = try? c.decodeIfPresent(Double.self, forKey: .resolvedAt)
        insurancePaid = try? c.decodeIfPresent(Bool.self, forKey: .insurancePaid)
        deadline = try? c.decodeIfPresent(Double.self, forKey: .deadline)
        supabaseId = try? c.decodeIfPresent(String.self, forKey: .supabaseId)
        supabaseSynced = try? c.decodeIfPresent(Bool.self, forKey: .supabaseSynced)
        potentialReward = try? c.decodeIfPresent(Int.self, forKey: .potentialReward)
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
    var resolved = true
    var friends = true
    var lowTime = true
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resolved = (try? c.decode(Bool.self, forKey: .resolved)) ?? true
        friends = (try? c.decode(Bool.self, forKey: .friends)) ?? true
        lowTime = (try? c.decode(Bool.self, forKey: .lowTime)) ?? true
    }
}

struct PrivacySettings: Codable, Hashable {
    var record = true
    var minutes = true
    var challenges = true
    init() {}
    init(record: Bool, minutes: Bool, challenges: Bool) { self.record = record; self.minutes = minutes; self.challenges = challenges }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        record = (try? c.decode(Bool.self, forKey: .record)) ?? true
        minutes = (try? c.decode(Bool.self, forKey: .minutes)) ?? true
        challenges = (try? c.decode(Bool.self, forKey: .challenges)) ?? true
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
    /// Lock points from the real Screen Time picks on an iPhone. Saved with settings so the website shows the same tier.
    var deviceLockPoints = 0

    init() {}

    enum CodingKeys: String, CodingKey { case sports, showPredictions, showTodos, enforce, lockedApps, minLimit, lowWarn, notify, privacy, deviceLockPoints }

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
        deviceLockPoints = (try? c.decode(Int.self, forKey: .deviceLockPoints)) ?? 0
    }
}

/// A friend's shared stats, from `timeout_social_state`. Anything they keep private arrives as zero with share off.
struct SocialProfile: Codable, Hashable {
    var username: String
    var name: String
    var photo: String?
    var w = 0
    var l = 0
    var net = 0
    var tier = "rookie"
    var streak = 0
    var share = PrivacySettings()
    var picks: [SharedPick] = []
}

/// One teammate's result for a team's dates, from `timeout_team_standings`.
struct TeamStanding: Codable, Hashable {
    var username: String
    var photo: String?
    var tier = "rookie"
    var hidden = false
    var w = 0
    var l = 0
    var net = 0
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

/// What a user's devices share (`user_settings.shared_ledger`). Same shape as the web app's.
/// This phone owns the screen-time records; the website only displays them.
struct SharedLedger: Codable {
    struct Device: Codable {
        var pledgedByDay: [String: Int] = [:]
        var netByDay: [String: Int] = [:]

        init(pledgedByDay: [String: Int] = [:], netByDay: [String: Int] = [:]) {
            self.pledgedByDay = pledgedByDay
            self.netByDay = netByDay
        }

        enum CodingKeys: String, CodingKey { case pledgedByDay, netByDay }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pledgedByDay = (try? c.decode([String: Int].self, forKey: .pledgedByDay)) ?? [:]
            netByDay = (try? c.decode([String: Int].self, forKey: .netByDay)) ?? [:]
        }
    }

    var usageByDay: [String: Int] = [:]
    var overridesByDay: [String: Int] = [:]
    var penaltyByDay: [String: Int] = [:]
    var devices: [String: Device] = [:]

    init() {}

    enum CodingKeys: String, CodingKey { case usageByDay, overridesByDay, penaltyByDay, devices }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usageByDay = (try? c.decode([String: Int].self, forKey: .usageByDay)) ?? [:]
        overridesByDay = (try? c.decode([String: Int].self, forKey: .overridesByDay)) ?? [:]
        penaltyByDay = (try? c.decode([String: Int].self, forKey: .penaltyByDay)) ?? [:]
        devices = (try? c.decode([String: Device].self, forKey: .devices)) ?? [:]
    }
}

struct UserData: Codable {
    var v = 1
    var wallet: WalletData
    var challenges: [Challenge] = []
    var lastPledge = 5
    var settings = Settings()
    var onboarded = false
    var friends: [String] = []
    var requestsIn: [FriendRequest] = []
    var requestsOut: [FriendRequest] = []
    var teams: [Squad] = []
    var feedFilter: String?
    /// The Home "Live games only" switch. It works with whichever sport is picked.
    var feedLive = false
    /// Friends' shared stats and team results, cached from the server so Social opens instantly.
    var socialProfiles: [String: SocialProfile] = [:]
    var teamResults: [String: [TeamStanding]] = [:]
    var socialSynced = false
    /// The user's other devices, from the shared ledger.
    var sharedDevices: [String: SharedLedger.Device] = [:]

    init(wallet: WalletData) { self.wallet = wallet }

    enum CodingKeys: String, CodingKey { case sharedDevices, v, wallet, challenges, lastPledge, settings, onboarded, friends, requestsIn, requestsOut, teams, feedFilter, feedLive, socialProfiles, teamResults, socialSynced }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? c.decode(Int.self, forKey: .v)) ?? 1
        wallet = (try? c.decode(WalletData.self, forKey: .wallet)) ?? WalletData(dayKey: TO.dayKey(), balance: Rules.daily)
        challenges = (try? c.decode([Challenge].self, forKey: .challenges)) ?? []
        lastPledge = (try? c.decode(Int.self, forKey: .lastPledge)) ?? 5
        settings = (try? c.decode(Settings.self, forKey: .settings)) ?? Settings()
        onboarded = (try? c.decode(Bool.self, forKey: .onboarded)) ?? false
        sharedDevices = (try? c.decode([String: SharedLedger.Device].self, forKey: .sharedDevices)) ?? [:]
        friends = (try? c.decode([String].self, forKey: .friends)) ?? []
        requestsIn = (try? c.decode([FriendRequest].self, forKey: .requestsIn)) ?? []
        requestsOut = (try? c.decode([FriendRequest].self, forKey: .requestsOut)) ?? []
        teams = (try? c.decode([Squad].self, forKey: .teams)) ?? []
        feedFilter = try? c.decodeIfPresent(String.self, forKey: .feedFilter)
        feedLive = (try? c.decode(Bool.self, forKey: .feedLive)) ?? false
        socialProfiles = (try? c.decode([String: SocialProfile].self, forKey: .socialProfiles)) ?? [:]
        teamResults = (try? c.decode([String: [TeamStanding]].self, forKey: .teamResults)) ?? [:]
        socialSynced = (try? c.decode(Bool.self, forKey: .socialSynced)) ?? false
        // "Live" used to be one of the sport chips.
        if feedFilter == "live" { feedFilter = "all"; feedLive = true }
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
    var openChallenges: [Challenge] = []
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
    static let maxPicks = 10
    /// A Combo Goal links at most this many matchups.
    static let maxMatchupPicks = 4
    /// The most minutes one challenge can pay back, pledge included.
    static let maxAllowedMinutes = 120
    static let overrideMinutes = 15
    static let overridePenalty = 30
    static let maxOverrides = 2
    static let todoMaxPledge = 20
    static let boostPercent = 0.1
}
