import Foundation
import Observation

extension TO {
    /// Same data URL as the web demo's initialsAvatar, so photos round-trip through Supabase unchanged.
    static func initialsAvatar(_ name: String?, _ color: String? = nil) -> String {
        let source = name ?? "?"
        let cleaned = source.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : " " }
        let words = String(cleaned).split(separator: " ").filter { !$0.isEmpty }
        var initials = String(words.compactMap(\.first).prefix(2)).uppercased()
        if initials.isEmpty { initials = "?" }
        let c = color ?? "hsl(\(TO.hash(source) % 360) 55% 42%)"
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 96 96\"><rect width=\"96\" height=\"96\" fill=\"\(c)\"/><text x=\"48\" y=\"60\" font-family=\"Arial, sans-serif\" font-size=\"38\" font-weight=\"700\" fill=\"#fff\" text-anchor=\"middle\">\(initials)</text></svg>"
        return "data:image/svg+xml;utf8,\(encodeURIComponent(svg))"
    }

    static func encodeURIComponent(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
        allowed.insert(charactersIn: "-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// A pick on the bet slip: the selection and the price/line the user accepted.
struct SlipLeg: Hashable {
    var selId: String
    var price: Int
    var line: Double?
    var ref: String
}

struct SharedPick: Hashable { var label: String; var matchup: String; var price: Int; var stake: Int }

struct Standing: Hashable { var username: String; var me: Bool; var net: Int; var w: Int; var l: Int; var hidden: Bool; var photo: String; var tier: String }

struct LeaderRow: Hashable {
    var username: String; var me: Bool; var photo: String; var w: Int; var l: Int; var net: Int; var tier: String; var streak: Int
    var share: PrivacySettings; var name: String?
}

/// What Supabase returns for a signed-in user (see API.loadState).
struct RemoteState {
    struct Wallet {
        var balance: Int
        var dayKey: String
        var lockedOut: Bool
        var streakDays: Int
        var bonusDay: String?
        var bonusGranted: Int?
        var boostsByDay: [String: Int]?
        var insuranceByWeek: [String: Int]?
    }
    var bets: [Bet] = []
    var wallet: Wallet?
    /// Raw app_preferences (plus followed sports), merged key by key like the web demo.
    var settings: [String: Any]?
    var appPreferencesReady = false
}

/// Accounts, the screen-time wallet, bets, settlement, tiers/streaks, friends and teams.
/// A port of the web demo's state.js. Everything is saved on this device; signed-in Supabase
/// accounts also sync bets, wallet and settings through `API`.
@Observable
final class Store {
    static let shared = Store()

    // MARK: Constants

    static let tiers: [Tier] = [
        Tier(id: "rookie", title: "Rookie", min: 0, color: "#8C96A8", icon: .user, bonus: 0, boosts: 0, insurance: 0),
        Tier(id: "starter", title: "Starter", min: 1, color: "#4FB3FF", icon: .star, bonus: 5, boosts: 0, insurance: 0),
        Tier(id: "allstar", title: "All-Star", min: 4, color: "#22D66E", icon: .star, bonus: 5, boosts: 1, insurance: 0),
        Tier(id: "mvp", title: "MVP", min: 8, color: "#FFC940", icon: .trophy, bonus: 10, boosts: 2, insurance: 0),
        Tier(id: "hof", title: "Hall of Fame", min: 12, color: "#C58CFF", icon: .crown, bonus: 10, boosts: 2, insurance: 1),
    ]

    static func tierPerks(_ t: Tier) -> [String] {
        var list: [String] = []
        if t.bonus > 0 { list.append("+\(t.bonus) betting min a day") }
        if t.boosts > 0 { list.append("\(t.boosts) odds boost\(t.boosts == 1 ? "" : "s") a day (+10% winnings)") }
        if t.insurance > 0 { list.append("Parlay insurance once a week") }
        return list.isEmpty ? ["Lock apps to earn perks"] : list
    }
    static func tierById(_ id: String) -> Tier { tiers.first { $0.id == id } ?? tiers[0] }
    static func tierForPoints(_ pts: Int) -> Tier { tiers.reversed().first { pts >= $0.min } ?? tiers[0] }
    static func streakMultiplier(_ days: Int) -> Double { days >= 7 ? 1.25 : days >= 3 ? 1.1 : 1 }
    static func nextStreakMilestone(_ days: Int) -> (days: Int, mult: Double)? { days < 3 ? (3, 1.1) : days < 7 ? (7, 1.25) : nil }

    static let lockable: [Lockable] = [
        Lockable(id: "instagram", name: "Instagram", kind: "App", pts: 1, color: "#D6417B"),
        Lockable(id: "tiktok", name: "TikTok", kind: "App", pts: 1, color: "#25F4EE"),
        Lockable(id: "youtube", name: "YouTube", kind: "App", pts: 1, color: "#FF0033"),
        Lockable(id: "snapchat", name: "Snapchat", kind: "App", pts: 1, color: "#FFFC00"),
        Lockable(id: "x", name: "X", kind: "App", pts: 1, color: "#E7E9EA"),
        Lockable(id: "reddit", name: "Reddit", kind: "App", pts: 1, color: "#FF4500"),
        Lockable(id: "netflix", name: "Netflix", kind: "App", pts: 1, color: "#E50914"),
        Lockable(id: "discord", name: "Discord", kind: "App", pts: 1, color: "#5865F2"),
        Lockable(id: "site-youtube", name: "youtube.com", kind: "Website", pts: 1, color: "#FF0033"),
        Lockable(id: "site-reddit", name: "reddit.com", kind: "Website", pts: 1, color: "#FF4500"),
        Lockable(id: "cat-social", name: "Social", kind: "Category", pts: 3, color: "#4FB3FF", note: "Every social app on your phone"),
        Lockable(id: "cat-ent", name: "Entertainment", kind: "Category", pts: 3, color: "#C58CFF", note: "Streaming and video apps"),
        Lockable(id: "cat-games", name: "Games", kind: "Category", pts: 3, color: "#FFC940", note: "Every game on your phone"),
    ]
    static func points(_ ids: [String]) -> Int { ids.reduce(0) { sum, id in sum + (lockable.first { $0.id == id }?.pts ?? 0) } }

    /// Demo friends for the Social screens.
    static let people: [Person] = {
        func p(_ u: String, _ name: String, _ color: String, _ w: Int, _ l: Int, _ net: Int, _ tier: String, _ streak: Int, _ r: Bool, _ m: Bool, _ b: Bool) -> Person {
            Person(username: u, name: name, photo: TO.initialsAvatar(name, color), w: w, l: l, net: net, tier: tier, streak: streak,
                   share: PrivacySettings(record: r, minutes: m, bets: b), fake: true)
        }
        return [
            p("mike_t", "Mike Torres", "#2F6FDE", 34, 27, 48, "allstar", 5, true, true, true),
            p("jess.plays", "Jess Park", "#D0467A", 41, 30, 73, "mvp", 9, true, false, true),
            p("coach_dan", "Dan Reeves", "#E08A1E", 22, 29, -36, "starter", 0, true, true, true),
            p("lily_k", "Lily Kim", "#7B5CE0", 18, 12, 25, "allstar", 3, true, true, false),
            p("tbone22", "Tyler Bonner", "#1E9E7A", 51, 55, -12, "rookie", 1, false, false, false),
            p("priya_p", "Priya Patel", "#C2410C", 12, 9, 19, "starter", 2, true, true, true),
            p("sam_the_fan", "Sam Ortiz", "#0E7490", 60, 58, 4, "mvp", 6, true, true, false),
            p("ava.r", "Ava Russo", "#BE185D", 9, 4, 22, "allstar", 4, true, true, true),
            p("big_ben", "Ben Hall", "#4D7C0F", 27, 33, -41, "rookie", 0, true, false, false),
            p("nate_w", "Nate Walker", "#6D28D9", 15, 15, 0, "starter", 1, true, true, true),
            p("coop_24", "Cooper James", "#B45309", 38, 22, 91, "hof", 12, true, true, true),
            p("maria.g", "Maria Garcia", "#DB2777", 20, 21, -3, "starter", 2, true, true, false),
        ]
    }()

    static let demo = (username: "demo", email: "demo@timeout.app", password: "timeout123")
    static let todoOdds = ["easy": 50, "medium": 100, "hard": 200]

    // MARK: State

    private(set) var account: Account?
    var data: UserData?
    private(set) var accountsById: [String: Account] = [:]

    private let fm = FileManager.default
    private var dir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TimeOut", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private init() {
        accountsById = read([String: Account].self, "accounts.json") ?? [:]
    }

    // MARK: Persistence

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let raw = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: raw)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        guard let raw = try? JSONEncoder().encode(value) else { return }
        try? raw.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    private func dataFile(_ id: String) -> String { "data-\(id.replacingOccurrences(of: "/", with: "_")).json" }
    private func loadData(_ id: String) -> UserData? { read(UserData.self, dataFile(id)) }
    private func storeData(_ id: String, _ d: UserData) { write(d, dataFile(id)) }
    private func saveAccounts() { write(accountsById, "accounts.json") }

    private var sessionId: String? {
        get { UserDefaults.standard.string(forKey: "timeout.session") }
        set { UserDefaults.standard.set(newValue, forKey: "timeout.session") }
    }

    /// Saves this account's data on the device and queues a Supabase sync for signed-in accounts.
    func save() {
        guard let account, let data else { return }
        storeData(account.id, data)
        if account.server != nil { API.shared.queueStateSave(data) }
    }

    /// Saves on the device only (used after merging something the server already has).
    func saveQuiet() {
        guard let account, let data else { return }
        storeData(account.id, data)
    }

    // MARK: Accounts

    func findAccount(_ identifier: String) -> Account? {
        var q = identifier.trimmingCharacters(in: .whitespaces).lowercased()
        if q.hasPrefix("@") { q.removeFirst() }
        return accountsById.values.first { $0.username.lowercased() == q || $0.email.lowercased() == q }
    }

    func findAccountByUsername(_ u: String) -> Account? {
        accountsById.values.first { $0.username.lowercased() == u.lowercased() }
    }

    static func validUsernameFormat(_ username: String) -> Bool {
        username.range(of: #"^[a-zA-Z0-9_.]{3,20}$"#, options: .regularExpression) != nil
    }

    func validateUsername(_ username: String, except: String? = nil) -> String? {
        if !Self.validUsernameFormat(username) { return "Use 3–20 letters, numbers, dots or underscores." }
        let taken = accountsById.values.contains { $0.id != except && $0.username.lowercased() == username.lowercased() }
            || Self.people.contains { $0.username.lowercased() == username.lowercased() }
        return taken ? "That username is taken. Try another." : nil
    }

    func validateEmail(_ email: String, except: String? = nil) -> String? {
        if email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) == nil { return "Enter a valid email address." }
        let taken = accountsById.values.contains { $0.id != except && $0.email.lowercased() == email.lowercased() }
        return taken ? "An account already uses that email. Log in instead." : nil
    }

    static func validatePassword(_ pw: String) -> String? { pw.count < 8 ? "Use at least 8 characters." : nil }

    @discardableResult
    func createAccount(username rawUser: String, email rawEmail: String, password: String, photo: String?, demo: Bool = false, data seeded: UserData? = nil) throws -> Account {
        let username = rawUser.trimmingCharacters(in: .whitespaces), email = rawEmail.trimmingCharacters(in: .whitespaces)
        var errors: [String: String] = [:]
        if let e = validateUsername(username) { errors["username"] = e }
        if let e = validateEmail(email) { errors["email"] = e }
        if let e = Self.validatePassword(password) { errors["password"] = e }
        if !errors.isEmpty { throw AppError(code: "invalid", message: "Fix the highlighted fields.", fields: errors) }
        let id = TO.uid("u"), salt = TO.uid("s")
        let acc = Account(id: id, username: username, email: email, salt: salt, pw: TO.pwHash(password, salt),
                          photo: photo ?? TO.initialsAvatar(username), createdAt: TO.now(), demo: demo)
        accountsById[id] = acc
        saveAccounts()
        storeData(id, seeded ?? freshData(TO.now()))
        return acc
    }

    func login(_ identifier: String, _ password: String) throws {
        if identifier.trimmingCharacters(in: .whitespaces).isEmpty {
            throw AppError(code: "invalid", message: "Enter your username or email.", fields: ["identifier": "Required"])
        }
        guard let acc = findAccount(identifier) else {
            throw AppError(code: "not_found", message: "No account matches that username or email.", fields: ["identifier": "No account found"])
        }
        guard acc.pw == TO.pwHash(password, acc.salt ?? "") else {
            throw AppError(code: "bad_password", message: "That password is incorrect.", fields: ["password": "Incorrect password"])
        }
        startSession(acc.id)
    }

    /// Copies a Supabase user onto this device and merges the server's bets, wallet and settings with the local cache.
    func adoptServerUser(_ user: ServerUser, remote remoteIn: RemoteState?) {
        let id = "srv_\(user.id)"
        var acc = accountsById[id] ?? Account(id: id, username: user.username, email: user.email, photo: "", createdAt: TO.now())
        acc.username = user.username
        acc.email = user.email
        acc.demo = user.isDemo
        acc.createdAt = LiveFeed.parseDate(user.createdAt) ?? acc.createdAt
        acc.server = user
        acc.photo = user.photoUrl ?? (acc.photo.isEmpty ? TO.initialsAvatar(user.isDemo ? "Demo User" : user.username, user.isDemo ? "#1AA560" : nil) : acc.photo)
        accountsById[id] = acc
        saveAccounts()

        if let remote = remoteIn {
            var merged: UserData
            if let cached = loadData(id) {
                merged = cached
                // Bets: server rows, with any newer local copy of the same bet laid over them.
                var order: [String] = []
                var byKey: [String: Bet] = [:]
                func key(_ b: Bet) -> String { b.supabaseId.map { "db:\($0)" } ?? "id:\(b.id)" }
                for b in remote.bets { let k = key(b); if byKey[k] == nil { order.append(k) }; byKey[k] = b }
                for b in cached.bets {
                    let k = key(b)
                    if byKey[k] == nil { order.append(k) }
                    if let saved = byKey[k] {
                        var combined = b
                        if combined.supabaseId == nil { combined.supabaseId = saved.supabaseId }
                        byKey[k] = combined
                    } else { byKey[k] = b }
                }
                merged.bets = order.compactMap { byKey[$0] }
                let hasUnsynced = cached.bets.contains { $0.kind == "sports" && $0.supabaseId == nil }
                // Settings: whichever side has real preferences wins, key by key.
                let cachedDict = Self.dictionary(cached.settings)
                let remoteDict = remote.settings ?? [:]
                let remoteHasPrefs = remote.appPreferencesReady && remoteDict.count > 1
                var prefs = remoteHasPrefs ? cachedDict.merging(remoteDict) { _, r in r } : remoteDict.merging(cachedDict) { _, c in c }
                let sports = (cached.settings.sports + ((remoteDict["sports"] as? [String]) ?? [])).filter { Sim.realLeagues.contains($0) }
                var unique: [String] = []
                for s in sports where !unique.contains(s) { unique.append(s) }
                if !unique.isEmpty { prefs["sports"] = unique }
                merged.settings = Self.settings(from: prefs) ?? cached.settings
                if let server = remote.wallet, !hasUnsynced {
                    // Supabase owns the balance; streak and daily ledgers stay local.
                    var w = cached.wallet
                    w.dayKey = server.dayKey
                    w.lockedOut = server.lockedOut
                    for (day, n) in server.boostsByDay ?? [:] { w.boostsByDay[day] = max(n, w.boostsByDay[day] ?? 0) }
                    for (week, n) in server.insuranceByWeek ?? [:] { w.insuranceByWeek[week] = max(n, w.insuranceByWeek[week] ?? 0) }
                    // The server may not have credited today's local tier bonus yet; keep it visible.
                    let localBonus = cached.wallet.bonusDay == server.dayKey ? cached.wallet.bonusGranted : 0
                    let serverBonus = server.bonusDay == server.dayKey ? (server.bonusGranted ?? 0) : 0
                    let uncredited = max(localBonus - serverBonus, 0)
                    w.balance = server.balance + uncredited
                    if uncredited > 0 && w.balance > 0 { w.lockedOut = false }
                    if localBonus > 0 || serverBonus > 0 {
                        w.bonusDay = server.dayKey
                        w.bonusGranted = max(localBonus, serverBonus)
                    }
                    merged.wallet = w
                }
            } else {
                merged = freshData(TO.now())
                merged.bets = remote.bets
                if let prefs = remote.settings, let s = Self.settings(from: Self.dictionary(merged.settings).merging(prefs) { _, r in r }) {
                    merged.settings = s
                }
                if let server = remote.wallet {
                    merged.wallet.dayKey = server.dayKey
                    merged.wallet.balance = server.balance
                    merged.wallet.lockedOut = server.lockedOut
                    merged.wallet.streakDays = server.streakDays
                    merged.wallet.bonusDay = server.bonusDay
                    merged.wallet.bonusGranted = server.bonusGranted ?? 0
                    merged.wallet.boostsByDay = server.boostsByDay ?? [:]
                    merged.wallet.insuranceByWeek = server.insuranceByWeek ?? [:]
                }
            }
            storeData(id, merged)
        } else if loadData(id) == nil {
            storeData(id, user.isDemo ? seedDemoData(TO.now()) : freshData(TO.now()))
        }
        startSession(id)
    }

    static func dictionary(_ s: Settings) -> [String: Any] {
        guard let raw = try? JSONEncoder().encode(s), let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return [:] }
        return obj
    }

    static func settings(from dict: [String: Any]) -> Settings? {
        guard JSONSerialization.isValidJSONObject(dict), let raw = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: raw)
    }

    func startSession(_ id: String) {
        sessionId = id
        _ = loadSession()
    }

    func logout() {
        sessionId = nil
        account = nil
        data = nil
    }

    @discardableResult
    func loadSession() -> Bool {
        guard let id = sessionId, let acc = accountsById[id] else { account = nil; data = nil; return false }
        var d = migrate(loadData(id) ?? freshData(TO.now()))
        _ = rollover(&d, TO.now())
        grantTierBonus(&d)
        account = acc
        data = d
        save()
        return true
    }

    struct AccountPatch { var username: String?; var email: String?; var photo: String?; var currentPassword: String?; var newPassword: String? }

    func updateAccount(_ patch: AccountPatch) throws {
        guard var acc = account else { return }
        if let u = patch.username?.trimmingCharacters(in: .whitespaces), u != acc.username {
            if let err = validateUsername(u, except: acc.id) { throw AppError(code: "invalid", message: err, fields: ["username": err]) }
            renameEverywhere(acc.username, u)
            acc.username = u
        }
        if let e = patch.email?.trimmingCharacters(in: .whitespaces), e != acc.email {
            if let err = validateEmail(e, except: acc.id) { throw AppError(code: "invalid", message: err, fields: ["email": err]) }
            acc.email = e
        }
        if let photo = patch.photo { acc.photo = photo }
        if let pw = patch.newPassword {
            if acc.pw != TO.pwHash(patch.currentPassword ?? "", acc.salt ?? "") {
                throw AppError(code: "bad_password", message: "Your current password is incorrect.", fields: ["currentPassword": "Incorrect password"])
            }
            if let err = Self.validatePassword(pw) { throw AppError(code: "invalid", message: err, fields: ["newPassword": err]) }
            acc.pw = TO.pwHash(pw, acc.salt ?? "")
        }
        accountsById[acc.id] = acc
        saveAccounts()
        account = acc
    }

    private func renameEverywhere(_ old: String, _ new: String) {
        guard let me = account else { return }
        for other in accountsById.values where other.id != me.id {
            mutateData(other.id) { d in
                d.friends = d.friends.map { $0 == old ? new : $0 }
                for i in d.teams.indices { d.teams[i].members = d.teams[i].members.map { $0 == old ? new : $0 } }
            }
        }
        guard var d = data else { return }
        for i in d.teams.indices {
            d.teams[i].members = d.teams[i].members.map { $0 == old ? new : $0 }
            if d.teams[i].owner == old { d.teams[i].owner = new }
        }
        data = d
    }

    func deleteAccount() {
        guard let acc = account else { return }
        accountsById[acc.id] = nil
        saveAccounts()
        try? fm.removeItem(at: dir.appendingPathComponent(dataFile(acc.id)))
        logout()
    }

    /// Edits another account's data on this device (or this account's, then saves).
    private func mutateData(_ id: String, _ fn: (inout UserData) -> Void) {
        if account?.id == id, var d = data { fn(&d); data = d; save(); return }
        guard var d = loadData(id) else { return }
        d = migrate(d)
        fn(&d)
        storeData(id, d)
    }

    // MARK: User data

    func freshData(_ now: Ms) -> UserData {
        var d = UserData(wallet: WalletData(dayKey: TO.dayKey(now), balance: Rules.daily))
        d.settings = Settings()
        return d
    }

    func migrate(_ input: UserData) -> UserData {
        var d = input
        if d.settings.sports.isEmpty { d.settings.sports = Sim.realLeagues }
        // Rebuild the daily bet-result ledger from settled bets (server wallets don't store it).
        var settledNet: [String: Int] = [:]
        for bet in d.bets where bet.status != "open" {
            settledNet[bet.dayKey, default: 0] += bet.payout - bet.stake
        }
        for (k, v) in settledNet { d.wallet.netByDay[k] = v }
        if d.settings.lockedApps.isEmpty { d.settings.enforce = false } // nothing to block, so limits can't be on
        return d
    }

    // MARK: Wallet

    func lockPoints(_ d: UserData) -> Int { d.settings.enforce ? Self.points(d.settings.lockedApps) : 0 }
    func tier(_ d: UserData) -> Tier { Self.tierForPoints(lockPoints(d)) }

    /// Phone time allowed on a day: 60 + the day before's results − emergency penalties (never below the user's floor).
    func baseLimitFor(_ day: String, _ d: UserData) -> Int {
        let net = d.wallet.netByDay[TO.addDays(day, -1)] ?? 0
        let penalty = d.wallet.penaltyByDay[day] ?? 0
        return max(Rules.daily + net - penalty, d.settings.minLimit, 0)
    }
    func emergencyMinutes(_ day: String, _ d: UserData) -> Int { (d.wallet.overridesByDay[day] ?? 0) * Rules.overrideMinutes }
    func limitFor(_ day: String, _ d: UserData) -> Int { baseLimitFor(day, d) + emergencyMinutes(day, d) }

    func walletView(_ d: UserData) -> WalletView {
        let w = d.wallet, day = w.dayKey, tomorrow = TO.addDays(day, 1)
        let used = w.usageByDay[day] ?? 0
        let todayLimit = limitFor(day, d)
        let open = d.bets.filter { $0.status == "open" }
        let t = tier(d)
        return WalletView(
            day: day, balance: w.balance, lockedOut: w.lockedOut,
            todayLimit: todayLimit, tomorrowLimit: baseLimitFor(tomorrow, d),
            yesterdayNet: w.netByDay[TO.addDays(day, -1)] ?? 0, todayNet: w.netByDay[day] ?? 0,
            penaltyToday: w.penaltyByDay[day] ?? 0, penaltyTomorrow: w.penaltyByDay[tomorrow] ?? 0,
            emergencyToday: emergencyMinutes(day, d), overridesUsed: w.overridesByDay[day] ?? 0,
            used: used, phoneLeft: max(todayLimit - used, 0),
            appsLocked: d.settings.enforce && used >= todayLimit,
            atRisk: open.reduce(0) { $0 + $1.stake }, openCount: open.count,
            tier: t, points: lockPoints(d), streak: w.streakDays, multiplier: Self.streakMultiplier(w.streakDays),
            boostsLeft: max(t.boosts - (w.boostsByDay[day] ?? 0), 0),
            insuranceLeft: max(t.insurance - (w.insuranceByWeek[TO.weekKey(TO.dayStart(day) + 12 * TO.HOUR)] ?? 0), 0),
            bonusToday: w.bonusDay == day ? w.bonusGranted : 0
        )
    }

    /// The signed-in user's wallet (a fresh default if nobody is signed in).
    var wallet: WalletView { walletView(data ?? freshData(TO.now())) }

    func grantTierBonus(_ d: inout UserData) {
        let day = d.wallet.dayKey
        if d.wallet.bonusDay != day { d.wallet.bonusDay = day; d.wallet.bonusGranted = 0 }
        let owed = tier(d).bonus - d.wallet.bonusGranted
        if owed > 0 {
            d.wallet.balance += owed
            d.wallet.bonusGranted = tier(d).bonus
            if d.wallet.balance > 0 { d.wallet.lockedOut = false }
        }
    }

    func grantTierBonus() {
        guard var d = data else { return }
        grantTierBonus(&d)
        data = d
    }

    /// Starts a new day at local midnight: closes out the old day, updates the streak, resets the betting balance.
    @discardableResult
    func rollover(_ d: inout UserData, _ now: Ms) -> Bool {
        let target = TO.dayKey(now)
        if d.wallet.dayKey == target { return false }
        if d.wallet.dayKey > target { d.wallet.dayKey = target; return false } // the local date moved backward
        var guardCount = 0
        while d.wallet.dayKey < target && guardCount < 400 {
            guardCount += 1
            let day = d.wallet.dayKey
            closeTodos(&d, day, now)
            let clean = d.settings.enforce && (d.wallet.usageByDay[day] ?? 0) <= limitFor(day, d) && !((d.wallet.overridesByDay[day] ?? 0) > 0)
            d.wallet.streakDays = clean ? d.wallet.streakDays + 1 : 0
            d.wallet.dayKey = TO.addDays(day, 1)
        }
        d.wallet.balance = Rules.daily
        d.wallet.lockedOut = false
        d.wallet.bonusDay = nil
        d.wallet.bonusGranted = 0
        grantTierBonus(&d)
        let cutoff = TO.addDays(d.wallet.dayKey, -60)
        d.wallet.netByDay = d.wallet.netByDay.filter { $0.key >= cutoff }
        d.wallet.penaltyByDay = d.wallet.penaltyByDay.filter { $0.key >= cutoff }
        d.wallet.overridesByDay = d.wallet.overridesByDay.filter { $0.key >= cutoff }
        d.wallet.usageByDay = d.wallet.usageByDay.filter { $0.key >= cutoff }
        d.wallet.boostsByDay = d.wallet.boostsByDay.filter { $0.key >= cutoff }
        return true
    }

    func rollover(_ now: Ms = TO.now()) -> Bool {
        guard var d = data else { return false }
        let rolled = rollover(&d, now)
        if rolled { data = d }
        return rolled
    }

    /// Phone time used on locked apps today, reported by the Screen Time monitor (only ever goes up).
    func setUsage(_ minutes: Int) {
        guard var d = data else { return }
        let day = d.wallet.dayKey
        guard minutes > (d.wallet.usageByDay[day] ?? 0) else { return }
        d.wallet.usageByDay[day] = minutes
        data = d
        save()
        checkPhoneTime()
    }

    func checkPhoneTime() {
        guard var d = data, d.settings.enforce else { return }
        let wl = walletView(d)
        if wl.appsLocked && d.wallet.warned.locked != wl.day {
            d.wallet.warned.locked = wl.day
            UIState.shared.toast(.loss, "Locked apps are blocked", "You used all of today's phone time. Use an emergency unlock in Settings if you really need it.")
        } else if !wl.appsLocked && wl.phoneLeft <= d.settings.lowWarn && d.wallet.warned.low != wl.day && d.settings.notify.lowTime {
            d.wallet.warned.low = wl.day
            UIState.shared.toast(.warn, "\(wl.phoneLeft) min of phone time left", "Your locked apps close when it runs out.")
        } else { return }
        data = d
        save()
    }

    func useEmergencyUnlock() throws {
        guard var d = data else { return }
        let day = d.wallet.dayKey
        if (d.wallet.overridesByDay[day] ?? 0) >= Rules.maxOverrides {
            throw AppError(code: "limit", message: "You've used both emergency unlocks today. They reset at midnight.")
        }
        d.wallet.overridesByDay[day, default: 0] += 1
        d.wallet.penaltyByDay[TO.addDays(day, 1), default: 0] += Rules.overridePenalty
        d.wallet.streakDays = 0
        d.wallet.warned.locked = nil
        data = d
        save()
    }

    // MARK: Settings

    /// App limits need something to block: they switch off with the last locked app and back on with the first.
    func setLockedApps(_ ids: [String]) {
        guard var d = data else { return }
        let hadLocks = !d.settings.lockedApps.isEmpty
        d.settings.lockedApps = ids
        d.settings.enforce = !ids.isEmpty && (d.settings.enforce || !hadLocks)
        grantTierBonus(&d)
        data = d
        save()
    }

    func setEnforce(_ on: Bool) {
        guard var d = data else { return }
        d.settings.enforce = on
        grantTierBonus(&d)
        data = d
        save()
    }

    func updateSettings(_ fn: (inout Settings) -> Void) {
        guard var d = data else { return }
        fn(&d.settings)
        data = d
        save()
    }

    func setFeedFilter(_ f: String) {
        guard var d = data else { return }
        d.feedFilter = f
        data = d
        save()
    }

    // MARK: Bets

    func legFromSelection(_ sel: Selection, _ now: Ms) -> Leg {
        if sel.kind == "race" || sel.market == "race" {
            let race = Races.shared.get(sel.raceId)
            let horse = Races.shared.horse(sel.horseId ?? Int(sel.side))
            var leg = Leg(selId: sel.id, kind: "race", market: "race", price: sel.price, label: horse.name, marketLabel: "Race winner",
                          matchup: "Virtual Race #\(race?.number ?? 0)")
            leg.raceId = sel.raceId; leg.horseId = horse.id; leg.side = String(horse.id); leg.league = "race"
            leg.start = race?.startedAt ?? now
            return leg
        }
        let g = sel.gameId.flatMap { Feed.game($0, now) }
        var leg = Leg(selId: sel.id, kind: "game", market: sel.market, price: sel.price, label: Sim.selectionLabel(sel, g),
                      marketLabel: Sim.marketLabel(sel, g), matchup: g.map { "\($0.away.name) @ \($0.home.name)" } ?? "")
        leg.gameId = sel.gameId; leg.side = sel.side; leg.line = sel.line
        leg.short = g.map { "\($0.away.abbr) @ \($0.home.abbr)" }
        leg.league = g?.league; leg.start = g?.start
        return leg
    }

    static func combine(_ legs: [Leg]) -> (decimal: Double, american: Int) {
        let dec = legs.reduce(1.0) { $0 * OddsMath.decimal($1.price) }
        return (dec, OddsMath.fromDecimal(dec))
    }

    /// Places a bet from bet-slip picks. Each pick carries the price the user accepted.
    @discardableResult
    func placeBet(picks: [SlipLeg], stake: Int?, boost: Bool, insure: Bool, now: Ms = TO.now()) throws -> Bet {
        guard var d = data else { throw AppError(code: "session", message: "Log in again.") }
        rollover(&d, now)
        if picks.isEmpty { throw AppError(code: "empty", message: "Add a pick to your bet slip.") }
        if picks.count > Rules.maxLegs { throw AppError(code: "too_many", message: "Parlays can have up to \(Rules.maxLegs) picks.") }
        var changed: [String] = []
        var legs: [Leg] = []
        for p in picks {
            guard let cur = Feed.currentSelection(p.selId, now), let sel = cur.sel, cur.open else {
                throw AppError(code: "closed", message: "One of your picks is no longer available. Remove it to continue.")
            }
            if sel.price != p.price || sel.line != p.line { changed.append(p.selId) }
            legs.append(legFromSelection(sel, now))
        }
        if !changed.isEmpty { throw AppError(code: "odds_changed", message: "The odds changed. Review the new odds and confirm again.", changed: changed) }
        if legs.contains(where: { $0.kind == "race" }) && legs.count != 1 {
            throw AppError(code: "race_single", message: "Virtual race picks can only be placed as a single bet.")
        }
        if d.wallet.lockedOut || d.wallet.balance <= 0 { throw AppError(code: "locked", message: "You're out of betting minutes for today. Betting reopens at midnight.") }
        guard let stake, stake >= 1 else { throw AppError(code: "stake", message: "Enter a stake of at least 1 minute.") }
        if stake > d.wallet.balance {
            throw AppError(code: "not_enough", message: "Not enough screentime. You have \(d.wallet.balance) min left to bet today.")
        }
        let wl = walletView(d)
        let combo = Self.combine(legs)
        var bet = Bet(id: TO.uid("bet"), kind: legs[0].kind == "race" ? "race" : "sports", placedAt: now, dayKey: d.wallet.dayKey,
                      stake: stake, legs: legs, decimal: combo.decimal, american: combo.american)
        var mult = wl.multiplier
        if boost && wl.boostsLeft > 0 {
            bet.boosted = true
            mult *= 1 + Rules.boostPercent
            d.wallet.boostsByDay[d.wallet.dayKey, default: 0] += 1
        }
        if insure && legs.count > 1 && wl.insuranceLeft > 0 {
            bet.insured = true
            d.wallet.insuranceByWeek[TO.weekKey(now), default: 0] += 1
        }
        bet.multiplier = (mult * 10000).rounded() / 10000
        if bet.kind == "race" { try Races.shared.startForBet(bet, now: now) }
        d.wallet.balance -= stake
        d.lastStake = stake
        if d.wallet.balance <= 0 { d.wallet.balance = 0; d.wallet.lockedOut = true }
        d.bets.append(bet)
        data = d
        save()
        return bet
    }

    private func closeTodos(_ d: inout UserData, _ day: String, _ now: Ms) {
        for i in d.bets.indices where d.bets[i].kind == "todo" && d.bets[i].status == "open" && d.bets[i].dayKey == day {
            for j in d.bets[i].legs.indices where d.bets[i].legs[j].result == "pending" {
                d.bets[i].legs[j].result = "lost"
                d.bets[i].legs[j].final = "Not done by midnight"
            }
            _ = finishIfDone(&d, i, now)
        }
    }

    static func outcome(_ bet: Bet) -> (status: String, payout: Int, insurancePaid: Bool) {
        let lost = bet.legs.filter { $0.result == "lost" }.count
        let pending = bet.legs.contains { $0.result == "pending" }
        if lost > 0 {
            if bet.insured {
                if pending { return ("open", 0, false) }
                if lost == 1 { return ("push", bet.stake, true) }
            }
            return ("lost", 0, false)
        }
        if pending { return ("open", 0, false) }
        let won = bet.legs.filter { $0.result == "won" }
        if won.isEmpty { return (bet.legs.allSatisfy { $0.result == "void" } ? "void" : "push", bet.stake, false) }
        let dec = won.reduce(1.0) { $0 * OddsMath.decimal($1.price) }
        var payout = jsRoundInt(Double(bet.stake) * dec)
        payout = bet.stake + jsRoundInt(Double(payout - bet.stake) * bet.multiplier)
        return ("won", payout, false)
    }

    private func finishIfDone(_ d: inout UserData, _ i: Int, _ now: Ms) -> Bet? {
        let res = Self.outcome(d.bets[i])
        if res.status == "open" { return nil }
        d.bets[i].status = res.status
        d.bets[i].payout = res.payout
        d.bets[i].insurancePaid = res.insurancePaid
        d.bets[i].settledAt = now
        let bet = d.bets[i]
        d.wallet.netByDay[bet.dayKey, default: 0] += bet.payout - bet.stake
        // Voids and pushes return the stake; wins and losses only affect the next day's limit.
        if bet.dayKey == d.wallet.dayKey && (bet.status == "void" || bet.status == "push") { d.wallet.balance += bet.payout }
        return bet
    }

    /// Grades every open bet against the latest scores. Runs on every tick, so bets settle seconds after a game ends.
    func settle(_ now: Ms = TO.now()) -> [Bet] {
        guard var d = data else { return [] }
        var settled: [Bet] = []
        var any = false
        for i in d.bets.indices where d.bets[i].status == "open" && d.bets[i].kind != "todo" {
            var changed = false
            for j in d.bets[i].legs.indices where d.bets[i].legs[j].result == "pending" {
                let leg = d.bets[i].legs[j]
                let r = Feed.grade(leg, now)
                if r == "pending" { continue }
                d.bets[i].legs[j].result = r
                changed = true
                if leg.kind == "race" {
                    let race = Races.shared.get(leg.raceId)
                    d.bets[i].legs[j].final = race?.winnerId.map { "Winner: \(Races.shared.horse($0).name)" } ?? "Race finished"
                } else if let gameId = leg.gameId, let g = Feed.game(gameId, now) {
                    let ot = g.ot.map { $0.label == "10" ? " (10 inn)" : " (OT)" } ?? ""
                    d.bets[i].legs[j].final = g.state == .postponed ? "Postponed" : "\(g.away.abbr) \(g.awayScore) – \(g.home.abbr) \(g.homeScore)\(ot)"
                }
            }
            if changed {
                any = true
                if let bet = finishIfDone(&d, i, now) { settled.append(bet) }
            }
        }
        if any {
            data = d
            if !settled.isEmpty { save() }
        }
        return settled
    }

    // MARK: Record / stats

    static func statsFor(_ bets: [Bet]) -> Stats {
        let settled = bets.filter { $0.status != "open" }
        let won = settled.filter { $0.status == "won" }
        let lost = settled.filter { $0.status == "lost" }
        let voids = settled.filter { $0.status == "void" || $0.status == "push" }
        let net = settled.reduce(0) { $0 + $1.payout - $1.stake }
        var bySport: [String: Stats.Line] = [:]
        for b in settled {
            let key = b.kind == "todo" ? "todo" : b.kind == "race" ? "race" : b.legs.count > 1 ? "parlay" : (b.legs.first?.league ?? "other")
            var line = bySport[key] ?? Stats.Line()
            if b.status == "won" { line.w += 1 }
            if b.status == "lost" { line.l += 1 }
            line.net += b.payout - b.stake
            bySport[key] = line
        }
        let decided = settled.filter { $0.status == "won" || $0.status == "lost" }.sorted { ($0.settledAt ?? 0) > ($1.settledAt ?? 0) }
        return Stats(
            w: won.count, l: lost.count, v: voids.count, net: net,
            pct: won.count + lost.count > 0 ? jsRoundInt(100 * Double(won.count) / Double(won.count + lost.count)) : nil,
            best: won.reduce(0) { max($0, $1.payout - $1.stake) },
            bySport: bySport,
            recent: decided.prefix(5).map { $0.status == "won" ? "W" : "L" }
        )
    }

    var myStats: Stats { Self.statsFor(data?.bets ?? []) }

    // MARK: People & friends

    static func sameUser(_ a: String?, _ b: String?) -> Bool { (a ?? "").lowercased() == (b ?? "").lowercased() }

    func person(_ username: String) -> Person? {
        if let fake = Self.people.first(where: { $0.username.lowercased() == username.lowercased() }) { return fake }
        guard let acc = findAccountByUsername(username) else { return nil }
        let d = acc.id == account?.id ? (data ?? freshData(TO.now())) : migrate(loadData(acc.id) ?? freshData(TO.now()))
        let st = Self.statsFor(d.bets)
        return Person(username: acc.username, name: acc.username, photo: acc.photo, w: st.w, l: st.l, net: st.net, tier: tier(d).id,
                      streak: d.wallet.streakDays, share: d.settings.privacy, local: true, accountId: acc.id,
                      openBets: d.bets.filter { $0.status == "open" })
    }

    /// Open picks a friend has shared (demo friends pick from the live board).
    func sharedPicks(_ p: Person, _ now: Ms = TO.now()) -> [SharedPick] {
        guard p.share.bets else { return [] }
        if p.local {
            return p.openBets.prefix(3).map { b in
                SharedPick(label: b.legs.map(\.label).joined(separator: " + "), matchup: b.legs.count > 1 ? "\(b.legs.count)-pick parlay" : (b.legs.first?.matchup ?? ""),
                           price: b.american, stake: b.stake)
            }
        }
        let games = Feed.board(now).filter { ($0.state == .live || $0.state == .scheduled) && !$0.simulated }
        let rand = TO.RNG("\(p.username)-\(Int((now / Sim.SLOT).rounded(.down)))")
        var picks: [SharedPick] = []
        let count = 1 + Int((rand() * 2).rounded(.down))
        for _ in 0..<count where !games.isEmpty {
            let g = games[Int((rand() * Double(games.count)).rounded(.down))]
            let all = Feed.odds(g.id, now).all
            guard !all.isEmpty else { _ = rand(); _ = rand(); continue }
            let sel = all[Int((rand() * Double(all.count)).rounded(.down))]
            picks.append(SharedPick(label: Sim.selectionLabel(sel, g), matchup: "\(g.away.name) @ \(g.home.name)", price: sel.price,
                                    stake: 5 + Int((rand() * 4).rounded(.down)) * 5))
        }
        return picks
    }

    func searchPeople(_ query: String) -> [Person] {
        var q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.hasPrefix("@") { q.removeFirst() }
        guard !q.isEmpty, let me = account?.username.lowercased() else { return [] }
        let locals = accountsById.values.filter { $0.username.lowercased() != me }
            .map { Person(username: $0.username, name: $0.username, photo: $0.photo, local: true) }
        return (Self.people + locals).filter { p in
            let u = p.username.lowercased()
            return u != me && (u.contains(q) || p.name.lowercased().contains(q))
        }.prefix(8).map { $0 }
    }

    func relation(_ username: String) -> String {
        guard let d = data else { return "none" }
        if d.friends.contains(where: { Self.sameUser($0, username) }) { return "friend" }
        if d.requestsOut.contains(where: { Self.sameUser($0.to, username) }) { return "requested" }
        if d.requestsIn.contains(where: { Self.sameUser($0.from, username) }) { return "incoming" }
        return "none"
    }

    /// An invite link is a yes from the sender, so this connects both people when the other account is on this device.
    @discardableResult
    func addFriend(_ username: String) -> Bool {
        var u = username.trimmingCharacters(in: .whitespaces)
        if u.hasPrefix("@") { u.removeFirst() }
        guard var d = data, let me = account?.username, !u.isEmpty, !Self.sameUser(u, me),
              u.range(of: #"^[a-zA-Z0-9_.]{1,20}$"#, options: .regularExpression) != nil else { return false }
        if !d.friends.contains(where: { Self.sameUser($0, u) }) { d.friends.append(u) }
        d.requestsIn.removeAll { Self.sameUser($0.from, u) }
        d.requestsOut.removeAll { Self.sameUser($0.to, u) }
        data = d
        if let acc = findAccountByUsername(u) {
            mutateData(acc.id) { o in
                if !o.friends.contains(where: { Self.sameUser($0, me) }) { o.friends.append(me) }
                o.requestsOut.removeAll { Self.sameUser($0.to, me) }
                o.requestsIn.removeAll { Self.sameUser($0.from, me) }
            }
        }
        save()
        return true
    }

    func sendFriendRequest(_ username: String, _ now: Ms = TO.now()) {
        let rel = relation(username)
        if rel == "friend" || rel == "requested" { return }
        if rel == "incoming" {
            if let incoming = data?.requestsIn.first(where: { Self.sameUser($0.from, username) }) { acceptFriendRequest(incoming.id) }
            return
        }
        guard var d = data, let me = account?.username else { return }
        let p = person(username)
        var req = FriendRequest(id: TO.uid("fr"), to: username, at: now)
        if p?.fake == true { req.acceptAt = now + 6000 } // demo friends accept after a few seconds
        d.requestsOut.append(req)
        data = d
        if let p, p.local, let accId = p.accountId {
            mutateData(accId) { o in
                if !o.requestsIn.contains(where: { $0.from == me }) { o.requestsIn.append(FriendRequest(id: req.id, from: me, at: now)) }
            }
        }
        save()
    }

    func acceptFriendRequest(_ id: String) {
        guard var d = data, let me = account?.username, let req = d.requestsIn.first(where: { $0.id == id }), let from = req.from else { return }
        d.requestsIn.removeAll { $0.id == id }
        if !d.friends.contains(from) { d.friends.append(from) }
        data = d
        if let acc = findAccountByUsername(from) {
            mutateData(acc.id) { o in
                o.requestsOut.removeAll { $0.to == me }
                if !o.friends.contains(me) { o.friends.append(me) }
            }
        }
        save()
    }

    func declineFriendRequest(_ id: String) {
        guard var d = data, let me = account?.username else { return }
        let req = d.requestsIn.first { $0.id == id }
        d.requestsIn.removeAll { $0.id == id }
        data = d
        if let from = req?.from, let acc = findAccountByUsername(from) {
            mutateData(acc.id) { o in o.requestsOut.removeAll { $0.to == me } }
        }
        save()
    }

    /// Resending is allowed once an hour per request. Returns ms until it can be sent again (0 = now).
    static func resendWait(_ req: FriendRequest, _ now: Ms = TO.now()) -> Ms { max(0, req.at + TO.HOUR - now) }

    func resendFriendRequest(_ username: String, _ now: Ms = TO.now()) throws {
        guard var d = data, let me = account?.username, let i = d.requestsOut.firstIndex(where: { $0.to == username }) else { return }
        let wait = Self.resendWait(d.requestsOut[i], now)
        if wait > 0 { throw AppError(code: "too_soon", message: "You can send @\(username) another request in \(Fmt.inTime(wait)).") }
        d.requestsOut[i].at = now
        data = d
        if let acc = findAccountByUsername(username) {
            mutateData(acc.id) { o in
                if let j = o.requestsIn.firstIndex(where: { $0.from == me }) { o.requestsIn[j].at = now }
            }
        }
        save()
    }

    func cancelFriendRequest(_ username: String) {
        guard var d = data, let me = account?.username else { return }
        d.requestsOut.removeAll { $0.to == username }
        data = d
        if let acc = findAccountByUsername(username) { mutateData(acc.id) { o in o.requestsIn.removeAll { $0.from == me } } }
        save()
    }

    func removeFriend(_ username: String) {
        guard var d = data, let me = account?.username else { return }
        d.friends.removeAll { $0 == username }
        data = d
        if let acc = findAccountByUsername(username) { mutateData(acc.id) { o in o.friends.removeAll { $0 == me } } }
        save()
    }

    /// Background social events: demo friends accept requests after a few seconds.
    func socialTick(_ now: Ms = TO.now()) -> [String] {
        guard var d = data else { return [] }
        var accepted: [String] = []
        for r in d.requestsOut {
            if let at = r.acceptAt, now >= at, let to = r.to {
                d.requestsOut.removeAll { $0.id == r.id }
                if !d.friends.contains(to) { d.friends.append(to) }
                accepted.append(to)
            }
        }
        if !accepted.isEmpty { data = d; save() }
        return accepted
    }

    // MARK: Teams

    static func teamStatus(_ t: Squad, _ now: Ms = TO.now()) -> String {
        let start = TO.dayStart(t.start), end = TO.dayStart(t.end) + TO.DAY
        if now < start { return "upcoming" }
        if now >= end { return "ended" }
        return "active"
    }

    func teamStandings(_ t: Squad, _ now: Ms = TO.now()) -> [Standing] {
        guard let me = account, let myData = data else { return [] }
        let start = TO.dayStart(t.start), end = TO.dayStart(t.end) + TO.DAY
        let lastDay = TO.dayKey(min(now, end - 1))
        let rows: [Standing] = t.members.map { u in
            let mine = Self.sameUser(u, me.username)
            let p = mine ? nil : person(u)
            // A username that isn't a demo profile or an account on this device still belongs on the roster.
            if !mine && p == nil {
                return Standing(username: u, me: false, net: 0, w: 0, l: 0, hidden: true, photo: TO.initialsAvatar(u), tier: "rookie")
            }
            var net = 0, w = 0, l = 0, hidden = false
            if p == nil || p!.local {
                let bets = p.flatMap { $0.accountId }.map { migrate(loadData($0) ?? freshData(now)).bets } ?? myData.bets
                for b in bets where b.status != "open" && b.placedAt >= start && b.placedAt < end {
                    net += b.payout - b.stake
                    if b.status == "won" { w += 1 }
                    if b.status == "lost" { l += 1 }
                }
                if let p, !p.share.minutes { hidden = true }
            } else if let p {
                if now >= start {
                    var day = t.start
                    var guardCount = 0
                    while day <= lastDay && guardCount < 400 {
                        guardCount += 1
                        let r = TO.unit("\(t.id)-\(u)-\(day)")
                        net += jsRoundInt(10 * r + (p.net > 0 ? 2 : -1))
                        let games = 1 + Int((TO.u01("\(t.id)-\(u)-\(day)-n") * 3).rounded(.down))
                        let wins = jsRoundInt(Double(games) * (0.5 + 0.3 * r))
                        w += wins; l += games - wins
                        day = TO.addDays(day, 1)
                    }
                }
                if !p.share.minutes { hidden = true }
            }
            return Standing(username: u, me: mine, net: net, w: w, l: l, hidden: hidden, photo: p?.photo ?? me.photo, tier: p?.tier ?? tier(myData).id)
        }
        return rows.enumerated().sorted { a, b in
            if a.element.hidden != b.element.hidden { return !a.element.hidden }
            if a.element.net != b.element.net { return a.element.net > b.element.net }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func newShareKey() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    private func touch(_ team: inout Squad) -> Int {
        team.rev = (team.rev ?? 0) + 1
        return team.rev!
    }

    private static func applyRemote(_ local: inout Squad, _ remote: API.RemoteTeam) {
        if !remote.name.isEmpty { local.name = remote.name }
        if !remote.start.isEmpty { local.start = String(remote.start.prefix(10)) }
        if !remote.end.isEmpty { local.end = String(remote.end.prefix(10)) }
        if let owner = remote.owner, !owner.isEmpty { local.owner = owner }
        if !remote.members.isEmpty { local.members = remote.members }
        local.remote = true
    }

    private func updateTeam(_ id: String, _ fn: (inout Squad) -> Void) {
        guard var d = data, let i = d.teams.firstIndex(where: { $0.id == id }) else { return }
        fn(&d.teams[i])
        data = d
    }

    func ensureTeamKey(_ id: String) -> String? {
        guard let t = data?.teams.first(where: { $0.id == id }) else { return nil }
        if let key = t.shareKey { return key }
        let key = Self.newShareKey()
        updateTeam(id) { team in team.shareKey = key; _ = touch(&team) }
        save()
        if let team = data?.teams.first(where: { $0.id == id }) { publishTeam(team) }
        return key
    }

    private func publishTeam(_ team: Squad) {
        guard team.shareKey != nil else { return }
        Task {
            if await API.shared.publishTeam(team) != nil {
                updateTeam(team.id) { $0.remote = true }
                saveQuiet()
            }
        }
    }

    /// Copies the team onto every member who has an account saved on this device.
    private func syncTeamCopies(_ team: Squad) {
        guard let me = account?.username else { return }
        for u in team.members where !Self.sameUser(u, me) {
            guard let acc = findAccountByUsername(u) else { continue }
            mutateData(acc.id) { d in
                if let i = d.teams.firstIndex(where: { $0.id == team.id }) {
                    d.teams[i].name = team.name; d.teams[i].start = team.start; d.teams[i].end = team.end
                    d.teams[i].owner = team.owner; d.teams[i].members = team.members
                } else { d.teams.append(team) }
            }
        }
    }

    @discardableResult
    func createTeam(name rawName: String, start: String, end: String, members: [String]) throws -> Squad {
        guard var d = data, let me = account?.username else { throw AppError(code: "session", message: "Log in again.") }
        let name = rawName.trimmingCharacters(in: .whitespaces)
        var errors: [String: String] = [:]
        if name.isEmpty { errors["name"] = "Give your team a name." }
        if start.isEmpty { errors["start"] = "Pick a start date." }
        if end.isEmpty { errors["end"] = "Pick an end date." }
        if !start.isEmpty && !end.isEmpty && end < start { errors["end"] = "End date must be on or after the start date." }
        if !errors.isEmpty { throw AppError(code: "invalid", message: "Fix the highlighted fields.", fields: errors) }
        var seen: Set<String> = [me.lowercased()]
        var invited: [String] = []
        for raw in members {
            let u = raw.trimmingCharacters(in: .whitespaces)
            if u.isEmpty || seen.contains(u.lowercased()) { continue }
            seen.insert(u.lowercased())
            invited.append(u)
        }
        let team = Squad(id: TO.uid("team"), name: name, start: start, end: end, members: [me] + invited, owner: me, createdAt: TO.now(),
                         shareKey: Self.newShareKey(), remote: false, rev: 1)
        d.teams.append(team)
        data = d
        syncTeamCopies(team)
        save()
        publishTeam(team)
        return team
    }

    func leaveTeam(_ id: String, remote: Bool = true) {
        guard var d = data, let me = account?.username else { return }
        let t = d.teams.first { $0.id == id }
        d.teams.removeAll { $0.id == id }
        data = d
        if let t {
            for u in t.members where !Self.sameUser(u, me) {
                guard let acc = findAccountByUsername(u) else { continue }
                mutateData(acc.id) { o in
                    guard let i = o.teams.firstIndex(where: { $0.id == id }) else { return }
                    o.teams[i].members.removeAll { Self.sameUser($0, me) }
                    if o.teams[i].members.isEmpty { o.teams.remove(at: i) }
                }
            }
        }
        save()
        if remote, let t, t.shareKey != nil { Task { _ = await API.shared.leaveTeamRemote(t, username: me) } }
    }

    func inviteToTeam(_ id: String, _ members: [String]) {
        guard var t = data?.teams.first(where: { $0.id == id }) else { return }
        var added: [String] = []
        for raw in members {
            let u = raw.trimmingCharacters(in: .whitespaces)
            if u.isEmpty || t.members.contains(where: { Self.sameUser($0, u) }) { continue }
            t.members.append(u)
            added.append(u)
        }
        guard !added.isEmpty else { return }
        _ = touch(&t)
        let team = t
        updateTeam(id) { $0 = team }
        syncTeamCopies(team)
        save()
        if team.shareKey != nil { for u in added { Task { _ = await API.shared.addTeamMember(team, username: u) } } }
    }

    struct TeamSnapshot { var id: String; var name: String; var start: String; var end: String; var owner: String?; var shareKey: String?; var members: [String] }

    /// Join a team from its link. Adds you, and the server roster when the link has a key.
    @discardableResult
    func joinTeam(_ snap: TeamSnapshot) throws -> Squad {
        guard var d = data, let me = account?.username else { throw AppError(code: "session", message: "Log in again.") }
        let id = snap.id.trimmingCharacters(in: .whitespaces), name = snap.name.trimmingCharacters(in: .whitespaces)
        let start = String(snap.start.prefix(10)), end = String(snap.end.prefix(10))
        let dateRe = #"^\d{4}-\d{2}-\d{2}$"#
        guard id.range(of: #"^[A-Za-z0-9_-]{1,40}$"#, options: .regularExpression) != nil, !name.isEmpty,
              start.range(of: dateRe, options: .regularExpression) != nil, end.range(of: dateRe, options: .regularExpression) != nil, end >= start else {
            throw AppError(code: "invalid", message: "That team link is missing a name or its dates.")
        }
        var team = d.teams.first { $0.id == id } ?? Squad(id: id, name: name, start: start, end: end, members: [], owner: snap.owner ?? me,
                                                          createdAt: TO.now(), shareKey: snap.shareKey, remote: false, rev: 0)
        if let key = snap.shareKey { team.shareKey = key }
        team.name = name; team.start = start; team.end = end
        if let owner = snap.owner, !owner.isEmpty { team.owner = owner }
        func add(_ u: String?) { if let u, !u.isEmpty, !team.members.contains(where: { Self.sameUser($0, u) }) { team.members.append(u) } }
        add(snap.owner)
        snap.members.forEach { add($0.trimmingCharacters(in: .whitespaces)) }
        add(me)
        let rev = touch(&team)
        if let i = d.teams.firstIndex(where: { $0.id == id }) { d.teams[i] = team } else { d.teams.append(team) }
        data = d
        syncTeamCopies(team)
        save()
        if let key = team.shareKey {
            let snapshot = team
            Task {
                guard let remote = await API.shared.addTeamMember(snapshot, username: me),
                      let current = data?.teams.first(where: { $0.id == id }), (current.rev ?? 0) == rev else { return }
                var updated = current
                Self.applyRemote(&updated, remote)
                updated.shareKey = key
                updateTeam(id) { $0 = updated }
                syncTeamCopies(updated)
                saveQuiet()
            }
        }
        return team
    }

    /// Pull rosters saved on the server. A failed request leaves the local team alone.
    func refreshTeams() async {
        guard let d = data, let me = account?.username else { return }
        let revs = Dictionary(d.teams.map { ($0.id, $0.rev ?? 0) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        for team in d.teams where team.shareKey != nil && team.remote == true {
            let remote = await API.shared.fetchTeam(team.id, key: team.shareKey!)
            guard let current = data?.teams.first(where: { $0.id == team.id }), (current.rev ?? 0) == revs[team.id] else { continue }
            switch remote {
            case .unreachable: continue
            case .gone:
                leaveTeam(team.id, remote: false); changed = true
            case .team(let r):
                if !r.members.contains(where: { Self.sameUser($0, me) }) { leaveTeam(team.id, remote: false); changed = true; continue }
                var updated = current
                Self.applyRemote(&updated, r)
                updated.shareKey = team.shareKey
                updateTeam(team.id) { $0 = updated }
                syncTeamCopies(updated)
                changed = true
            }
        }
        if let listed = await API.shared.myTeams(), var d2 = data {
            var seen = Set<String>()
            for r in listed where !r.id.isEmpty {
                seen.insert(r.id)
                if let i = d2.teams.firstIndex(where: { $0.id == r.id }) {
                    if (d2.teams[i].rev ?? 0) == revs[r.id] {
                        let key = d2.teams[i].shareKey
                        Self.applyRemote(&d2.teams[i], r)
                        if let key { d2.teams[i].shareKey = key }
                        changed = true
                    }
                } else {
                    d2.teams.append(Squad(id: r.id, name: r.name, start: String(r.start.prefix(10)), end: String(r.end.prefix(10)),
                                          members: r.members.isEmpty ? [me] : r.members, owner: r.owner ?? me, createdAt: TO.now(), remote: true, rev: 1))
                    changed = true
                }
            }
            let kept = d2.teams.filter { $0.shareKey != nil || $0.remote != true || seen.contains($0.id) }
            if kept.count != d2.teams.count { d2.teams = kept; changed = true }
            data = d2
        }
        if changed { saveQuiet() }
    }

    // MARK: Leaderboard

    func leaderboard() -> [LeaderRow] {
        guard let me = account, let d = data else { return [] }
        let st = myStats
        var rows = [LeaderRow(username: me.username, me: true, photo: me.photo, w: st.w, l: st.l, net: st.net, tier: tier(d).id,
                              streak: d.wallet.streakDays, share: PrivacySettings())]
        for f in d.friends {
            if let p = person(f) {
                rows.append(LeaderRow(username: p.username, me: false, photo: p.photo, w: p.w, l: p.l, net: p.net, tier: p.tier, streak: p.streak, share: p.share, name: p.name))
            }
        }
        return rows.enumerated().sorted { a, b in
            if a.element.share.minutes != b.element.share.minutes { return a.element.share.minutes }
            if a.element.net != b.element.net { return a.element.net > b.element.net }
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Demo account

    func seedDemoData(_ now: Ms) -> UserData {
        var d = freshData(now)
        let day = TO.dayKey(now)
        d.onboarded = true
        d.settings.lockedApps = ["instagram", "tiktok", "youtube", "cat-social"]
        d.friends = ["mike_t", "jess.plays", "coach_dan", "lily_k", "tbone22"]
        d.requestsIn = [FriendRequest(id: TO.uid("fr"), from: "priya_p", at: now - 20 * TO.MIN)]
        // Still waiting on these two: one can be resent, the other was sent too recently.
        d.requestsOut = [FriendRequest(id: TO.uid("fr"), to: "sam_the_fan", at: now - 3 * TO.HOUR), FriendRequest(id: TO.uid("fr"), to: "ava.r", at: now - 25 * TO.MIN)]
        d.teams = [Squad(id: "team_sunday", name: "Sunday Squad", start: TO.addDays(day, -3), end: TO.addDays(day, 4),
                         members: ["demo", "mike_t", "jess.plays", "lily_k"], owner: "mike_t", createdAt: now - 3 * TO.DAY)]

        // Bet history from past simulated games, graded with the same rules as live bets.
        let rand = TO.RNG("demo-history")
        for back in stride(from: 6, through: 1, by: -1) {
            let dk = TO.addDays(day, -back)
            d.wallet.usageByDay[dk] = 25 + Int((rand() * 25).rounded(.down))
            for k in 0..<(2 + back % 2) {
                let legsN = rand() < 0.25 ? 2 : 1
                var legs: [Leg] = []
                let placedAt = TO.dayStart(dk) + Double(12 + k * 3) * TO.HOUR + (rand() * 40).rounded(.down) * TO.MIN
                for j in 0..<legsN {
                    let league = Sim.realLeagues[Int((rand() * Double(Sim.realLeagues.count)).rounded(.down))]
                    let L = Sim.leagues[league]!
                    let slot = Int(((placedAt - L.offset) / Sim.SLOT).rounded(.down)) + 1
                    let id = "\(league)-\(slot)-\(j % L.perSlot)"
                    guard let g0 = Sim.game(id, now), g0.state != .postponed, !legs.contains(where: { $0.gameId == id }),
                          let o = Sim.odds(id, g0.start - 60_000) else { continue }
                    let pool = o.all.filter { $0.side != "draw" }
                    let sel = pool[Int((rand() * Double(pool.count)).rounded(.down))]
                    var leg = simLeg(sel, g0)
                    leg.result = Sim.grade(leg, now)
                    if let g = Sim.game(id, now) { leg.final = "\(g.away.abbr) \(g.awayScore) – \(g.home.abbr) \(g.homeScore)" }
                    legs.append(leg)
                }
                if legs.isEmpty { continue }
                let stake = 5 + Int((rand() * 3).rounded(.down)) * 5
                let combo = Self.combine(legs)
                var bet = Bet(id: TO.uid("bet"), kind: "sports", placedAt: placedAt, dayKey: dk, stake: stake, legs: legs, decimal: combo.decimal, american: combo.american)
                let res = Self.outcome(bet)
                bet.status = res.status; bet.payout = res.payout
                bet.settledAt = legs.compactMap { $0.gameId.flatMap { Sim.game($0, now)?.end } }.max() ?? placedAt
                d.wallet.netByDay[dk, default: 0] += bet.payout - bet.stake
                d.bets.append(bet)
            }
        }
        d.wallet.streakDays = 4
        d.wallet.usageByDay[day] = 22
        grantTierBonus(&d)

        // Open bets on today's board.
        let board = Feed.board(now).filter { !$0.simulated }
        let live = board.filter { $0.state == .live && $0.progress < 0.7 }
        let upcoming = board.filter { $0.state == .scheduled && $0.start - now > 4 * TO.MIN }
        func open(_ legs: [Leg], _ stake: Int, _ placedAt: Ms) {
            let combo = Self.combine(legs)
            var bet = Bet(id: TO.uid("bet"), kind: "sports", placedAt: placedAt, dayKey: d.wallet.dayKey, stake: stake, legs: legs, decimal: combo.decimal, american: combo.american)
            bet.multiplier = Self.streakMultiplier(d.wallet.streakDays)
            d.bets.append(bet)
            d.wallet.balance -= stake
        }
        if let g = live.first, let sel = Feed.odds(g.id, now).moneyline.first(where: { $0.side == "home" }) {
            open([legFromSelection(sel, now)], 10, now - 3 * TO.MIN)
        }
        if upcoming.count >= 2, let a = Feed.odds(upcoming[0].id, now).total.first,
           let b = Feed.odds(upcoming[1].id, now).spread.dropFirst().first ?? Feed.odds(upcoming[1].id, now).moneyline.dropFirst().first {
            open([legFromSelection(a, now), legFromSelection(b, now)], 5, now - TO.MIN)
        } else if live.count > 1, let sel = Feed.odds(live[1].id, now).total.dropFirst().first {
            open([legFromSelection(sel, now)], 5, now - TO.MIN)
        }
        return d
    }

    /// A leg for a simulated game, without going through the live feed.
    private func simLeg(_ sel: Selection, _ g: Game) -> Leg {
        var leg = Leg(selId: sel.id, kind: "game", market: sel.market, price: sel.price, label: Sim.selectionLabel(sel, g),
                      marketLabel: Sim.marketLabel(sel, g), matchup: "\(g.away.name) @ \(g.home.name)")
        leg.gameId = g.id; leg.side = sel.side; leg.line = sel.line
        leg.short = "\(g.away.abbr) @ \(g.home.abbr)"; leg.league = g.league; leg.start = g.start
        return leg
    }

    @discardableResult
    func ensureDemoAccount() -> Account? {
        if let acc = findAccountByUsername(Self.demo.username) { return acc }
        let seeded = seedDemoData(TO.now())
        return try? createAccount(username: Self.demo.username, email: Self.demo.email, password: Self.demo.password,
                                  photo: TO.initialsAvatar("Demo User", "#1AA560"), demo: true, data: seeded)
    }

    func loginDemo() {
        if let acc = ensureDemoAccount() { startSession(acc.id) }
    }

    func completeOnboarding(sports: [String], locks: [String]?) {
        guard var d = data else { return }
        d.settings.sports = Sim.leagueOrder.filter { sports.contains($0) }
        if let locks {
            let hadLocks = !d.settings.lockedApps.isEmpty
            d.settings.lockedApps = locks
            d.settings.enforce = !locks.isEmpty && (d.settings.enforce || !hadLocks)
        }
        d.onboarded = true
        grantTierBonus(&d)
        data = d
        save()
    }
}
