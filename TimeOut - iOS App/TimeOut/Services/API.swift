import Foundation
import Observation

/// TimeOut's Supabase client: the same project, tables and RPCs as the web demo (api.js), so one login works on both.
/// The publishable key is meant to ship in clients; row-level security protects the tables.
@Observable
final class API {
    static let shared = API()

    static let baseURL = "https://obegznrsxlbpmtbmqkll.supabase.co"
    static let publishableKey = "sb_publishable_Ye3rhYIle7db-4O9DL_IHw_xz88b-sB"
    /// Where the confirmation email sends people back to. It must be in Supabase's Redirect URLs (the live site is).
    static let returnURL = "https://marcustheman13.github.io/TimeOut/"
    /// The web app, used for invite links so anyone can open them.
    static let webURL = "https://marcustheman13.github.io/TimeOut/"

    private(set) var configured = true
    private(set) var online = true

    private let tokenKey = "timeout.supabase.session"
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingState: UserData?
    @ObservationIgnored private var lastSaveAt: Date = .distantPast
    @ObservationIgnored private var lastSettingsSnapshot = ""
    @ObservationIgnored private var supportsAppPreferences = true
    @ObservationIgnored private var supportsTierBonusColumns: Bool?
    @ObservationIgnored private var supportsTierPerkColumns: Bool?
    @ObservationIgnored private var placing = Set<String>()
    @ObservationIgnored private var settling = Set<String>()
    @ObservationIgnored private var alertTimes: [String: Date] = [:]

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    // MARK: Session token

    private struct TokenSession: Codable {
        var access_token: String
        var refresh_token: String?
        var expires_at: Double?
        var expires_in: Double?
        var token_type: String?
    }

    private var stored: TokenSession? {
        get { UserDefaults.standard.data(forKey: tokenKey).flatMap { try? JSONDecoder().decode(TokenSession.self, from: $0) } }
        set {
            if let v = newValue, let raw = try? JSONEncoder().encode(v) { UserDefaults.standard.set(raw, forKey: tokenKey) }
            else { UserDefaults.standard.removeObject(forKey: tokenKey) }
        }
    }

    var hasToken: Bool { stored?.access_token != nil }
    func clearToken() { stored = nil }
    private var token: String? { stored?.access_token }

    private var tokenUserId: String? {
        guard let t = token else { return nil }
        let parts = t.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let raw = Data(base64Encoded: b64) else { return nil }
        return JSON(data: raw)["sub"].string
    }

    private func saveSession(_ json: JSON) {
        guard let access = json["access_token"].string else { return }
        let expiresIn = json["expires_in"].number ?? 3600
        stored = TokenSession(access_token: access, refresh_token: json["refresh_token"].string,
                              expires_at: json["expires_at"].number ?? Date().timeIntervalSince1970 + expiresIn,
                              expires_in: expiresIn, token_type: json["token_type"].string)
    }

    // MARK: Requests

    private func headers(auth: Bool) -> [String: String] {
        ["apikey": Self.publishableKey, "authorization": "Bearer \(auth ? (token ?? Self.publishableKey) : Self.publishableKey)", "content-type": "application/json"]
    }

    private func send(_ url: URL, method: String = "GET", body: Data? = nil, auth: Bool = true, extra: [String: String] = [:], timeout: TimeInterval? = nil) async throws -> JSON {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if let timeout { req.timeoutInterval = timeout }
        for (k, v) in headers(auth: auth).merging(extra, uniquingKeysWith: { _, b in b }) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? JSON.null : JSON(data: data)
        guard (200..<300).contains(status) else {
            let message = json["msg"].text ?? json["message"].text ?? json["error_description"].text ?? json["error"].text ?? "Supabase request failed (\(status))."
            var fields: [String: String] = [:]
            let lower = message.lowercased()
            if lower.contains("username") { fields["username"] = message }
            else if lower.contains("email") { fields["email"] = message }
            else if lower.contains("password") { fields["password"] = message }
            throw AppError(code: status == 409 ? "taken" : "supabase_error", message: message, fields: fields, status: status)
        }
        return json
    }

    private func authRequest(_ path: String, _ body: [String: Any], auth: Bool = false) async throws -> JSON {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await send(URL(string: "\(Self.baseURL)/auth/v1/\(path)")!, method: "POST", body: data, auth: auth)
    }

    private func ensureFreshSession() async throws {
        guard let s = stored, let refresh = s.refresh_token else { return }
        if (s.expires_at ?? 0) > Date().timeIntervalSince1970 + 60 { return }
        let fresh = try await authRequest("token?grant_type=refresh_token", ["refresh_token": refresh])
        saveSession(fresh)
    }

    private func rest(_ path: String, method: String = "GET", body: Any? = nil, extra: [String: String] = [:], timeout: TimeInterval? = nil) async throws -> JSON {
        try await ensureFreshSession()
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
        guard let url = URL(string: "\(Self.baseURL)/rest/v1/\(path)") else { throw AppError(code: "url", message: "Bad request.") }
        return try await send(url, method: method, body: data, extra: extra, timeout: timeout)
    }

    private static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?"))) ?? s }

    // MARK: Auth

    /// Falls back to the on-device demo accounts when Supabase can't be reached at all.
    func initialize() async -> Bool {
        // Launch with -offline-demo to use the on-device demo accounts, like the web demo without its Supabase config.
        if ProcessInfo.processInfo.arguments.contains("-offline-demo") { configured = false; online = false }
        guard configured, Net.shared.online else { return configured }
        var req = URLRequest(url: URL(string: "\(Self.baseURL)/auth/v1/health")!)
        req.timeoutInterval = 5
        req.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
        do {
            _ = try await session.data(for: req)
        } catch {
            configured = false
            online = false
        }
        return configured
    }

    func resendConfirmation(_ email: String) async throws {
        _ = try await authRequest("resend?redirect_to=\(Self.enc(Self.returnURL))", ["type": "signup", "email": email.trimmingCharacters(in: .whitespaces)])
    }

    func login(email: String, password: String) async throws -> ServerUser {
        let session = try await authRequest("token?grant_type=password", ["email": email.trimmingCharacters(in: .whitespaces), "password": password])
        saveSession(session)
        lastSettingsSnapshot = ""
        supportsAppPreferences = true
        return try await me()
    }

    enum RegisterResult { case needsConfirmation(String), signedIn(ServerUser, RemoteState?) }

    func register(username: String, email: String, password: String, photoUrl: String?) async throws -> RegisterResult {
        if !Store.validUsernameFormat(username) {
            throw AppError(code: "invalid", message: "Use 3–20 letters, numbers, dots or underscores.", fields: ["username": "Use 3–20 letters, numbers, dots or underscores."])
        }
        let mail = email.trimmingCharacters(in: .whitespaces)
        var meta: [String: Any] = ["username": username, "display_name": username]
        meta["avatar_url"] = photoUrl ?? NSNull()
        let result = try await authRequest("signup?redirect_to=\(Self.enc(Self.returnURL))", ["email": mail, "password": password, "data": meta])
        // Supabase answers a sign-up for an email that's already registered with a user that has no identities.
        if result["identities"].isArray && result["identities"].array.isEmpty {
            throw AppError(code: "taken", message: "An account with this email already exists. Log in instead.", fields: ["email": "An account with this email already exists."])
        }
        // Email confirmation is on: there's no session until the link in the email is opened.
        if result["session"]["access_token"].isNull && result["access_token"].isNull { return .needsConfirmation(mail) }
        saveSession(result["session"].isObject ? result["session"] : result)
        lastSettingsSnapshot = ""
        supportsAppPreferences = true
        let user = try await me()
        return .signedIn(user, try await loadState())
    }

    func me() async throws -> ServerUser {
        try await ensureFreshSession()
        let user = try await send(URL(string: "\(Self.baseURL)/auth/v1/user")!)
        let id = user["id"].string ?? ""
        let rows = try await rest("profiles?select=username,display_name,avatar_url,created_at&id=eq.\(Self.enc(id))&limit=1")
        let profile = rows[0]
        let email = user["email"].string ?? ""
        return ServerUser(
            id: id,
            username: profile["username"].text ?? user["user_metadata"]["username"].text ?? email.split(separator: "@").first.map(String.init) ?? "player",
            email: email,
            photoUrl: profile["avatar_url"].text ?? user["user_metadata"]["avatar_url"].text,
            createdAt: profile["created_at"].text ?? user["created_at"].string ?? "",
            isDemo: false
        )
    }

    func loadState() async throws -> RemoteState? {
        guard let id = tokenUserId else { return nil }
        let safe = Self.enc(id)
        var hasBonus = true, hasPerks = true
        let base = "balance_minutes,current_day,is_locked,streak"
        let bonus = "\(base),tier_bonus_day,tier_bonus_minutes"
        async let betRowsTask = rest("bets?select=*,bet_legs(*)&user_id=eq.\(safe)&order=placed_at.desc")
        var walletRows: JSON
        do {
            walletRows = try await rest("wallets?select=\(bonus),tier_boosts_by_day,tier_insurance_by_week&user_id=eq.\(safe)&limit=1")
        } catch let e as AppError where e.message.range(of: "tier_boosts_by_day|tier_insurance_by_week|column .*does not exist", options: .regularExpression) != nil {
            hasPerks = false
            do {
                walletRows = try await rest("wallets?select=\(bonus)&user_id=eq.\(safe)&limit=1")
            } catch let e2 as AppError where e2.message.range(of: "tier_bonus_day|tier_bonus_minutes|column .*does not exist", options: .regularExpression) != nil {
                hasBonus = false
                walletRows = try await rest("wallets?select=\(base)&user_id=eq.\(safe)&limit=1")
            }
        }
        let betRows = try await betRowsTask
        supportsTierBonusColumns = hasBonus
        supportsTierPerkColumns = hasPerks
        var settingsRows: JSON
        do {
            settingsRows = try await rest("user_settings?select=followed_sports,timezone,notifications_enabled,app_preferences&user_id=eq.\(safe)&limit=1")
            supportsAppPreferences = true
        } catch let e as AppError where e.message.range(of: "app_preferences", options: .caseInsensitive) != nil {
            supportsAppPreferences = false
            settingsRows = try await rest("user_settings?select=followed_sports,timezone,notifications_enabled&user_id=eq.\(safe)&limit=1")
        }
        let statusMap = ["pending": "open", "won": "won", "lost": "lost", "pushed": "push", "voided": "void", "cancelled": "void"]
        let resultMap = ["pending": "pending", "win": "won", "loss": "lost", "push": "push", "void": "void"]
        var state = RemoteState()
        state.bets = betRows.array.map { row in
            let legs: [Leg] = row["bet_legs"].array.map { leg in
                let eventId = leg["espn_event_id"].string ?? ""
                let market = leg["market"].string ?? "ml", side = leg["side"].string ?? ""
                let line = leg["line"].number
                var l = Leg(selId: "\(eventId)|\(market)|\(side)", kind: "game", market: market, price: Int(leg["accepted_odds"].number ?? 100),
                            label: "\(market) · \(side)\(leg["line"].isNull ? "" : " \(leg["line"].string ?? "")")", marketLabel: market, matchup: leg["matchup"].string ?? "")
                l.gameId = eventId; l.league = leg["league"].string; l.side = side; l.line = line
                l.result = resultMap[leg["result"].string ?? ""] ?? "pending"
                return l
            }
            let decimal = row["combined_odds"].number ?? 1
            let placedAt = LiveFeed.parseDate(row["placed_at"].string) ?? TO.now()
            var bet = Bet(id: "supabase-\(row["id"].string ?? "")", kind: "sports", placedAt: placedAt, dayKey: TO.dayKey(placedAt),
                          stake: Int(row["stake_minutes"].number ?? 0), legs: legs, decimal: decimal, american: OddsMath.fromDecimal(decimal))
            bet.supabaseId = row["id"].string
            bet.boosted = row["boosted"].truthy
            bet.insured = row["insured"].truthy
            bet.multiplier = row["multiplier"].number ?? 1
            bet.status = statusMap[row["status"].string ?? ""] ?? "open"
            bet.payout = Int(row["actual_payout_minutes"].number ?? 0)
            bet.potentialPayout = Int(row["potential_payout_minutes"].number ?? 0)
            bet.settledAt = LiveFeed.parseDate(row["settled_at"].string)
            bet.supabaseSynced = row["status"].string != "pending"
            return bet
        }
        let wallet = walletRows[0]
        if wallet.isObject {
            var w = RemoteState.Wallet(balance: Int(wallet["balance_minutes"].number ?? 0), dayKey: wallet["current_day"].string ?? TO.dayKey(),
                                       lockedOut: wallet["is_locked"].truthy, streakDays: Int(wallet["streak"].number ?? 0))
            if hasBonus {
                w.bonusDay = wallet["tier_bonus_day"].string
                w.bonusGranted = Int(wallet["tier_bonus_minutes"].number ?? 0)
            }
            if hasPerks {
                w.boostsByDay = Self.counts(wallet["tier_boosts_by_day"])
                w.insuranceByWeek = Self.counts(wallet["tier_insurance_by_week"])
            }
            state.wallet = w
        }
        let settings = settingsRows[0]
        if settings.isObject {
            var prefs = (settings["app_preferences"].isObject ? Self.any(settings["app_preferences"]) as? [String: Any] : nil) ?? [:]
            var followed: [String] = []
            for s in (settings["followed_sports"].array + ((prefs["sports"] as? [String])?.map { JSON.string($0) } ?? [])) {
                if let v = s.string, Sim.realLeagues.contains(v), !followed.contains(v) { followed.append(v) }
            }
            if !followed.isEmpty { prefs["sports"] = followed }
            state.settings = prefs
            state.appPreferencesReady = supportsAppPreferences
        }
        return state
    }

    private static func counts(_ json: JSON) -> [String: Int] {
        guard case .object(let o) = json else { return [:] }
        return o.compactMapValues { $0.number.map { Int($0) } }
    }

    private static func any(_ json: JSON) -> Any {
        switch json {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? Int(n) as Any : n
        case .string(let s): return s
        case .array(let a): return a.map(any)
        case .object(let o): return o.mapValues(any)
        }
    }

    // MARK: Sync

    func queueStateSave(_ data: UserData) {
        guard configured, token != nil else { return }
        pendingState = data
        guard saveTask == nil else { return }
        let delay = max(0, 1.5 - Date().timeIntervalSince(lastSaveAt))
        saveTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            saveTask = nil
            do { try await flushState() } catch {
                let message = (error as? AppError)?.message ?? error.localizedDescription
                if Self.isOutOfMinutes(message) { notify("minutes", .loss, "Out of betting minutes", "Betting reopens at midnight."); return }
                notify("sync", .loss, "Couldn’t save to Supabase", message)
            }
        }
    }

    private func notify(_ key: String, _ kind: ToastKind, _ title: String, _ msg: String) {
        if let last = alertTimes[key], Date().timeIntervalSince(last) < 15 { return }
        alertTimes[key] = Date()
        UIState.shared.toast(kind, title, msg)
    }

    private static func isOutOfMinutes(_ m: String) -> Bool {
        m.range(of: "insufficient|not enough|out of (betting )?(minutes|balance)|betting minutes", options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func rpcMissing(_ m: String, _ name: String) -> Bool {
        m.range(of: name, options: .caseInsensitive) != nil
            && m.range(of: "schema cache|function.*(not found|does not exist|could not find)", options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func perkExhausted(_ m: String) -> Bool {
        m.range(of: "no odds boosts left|no parlay insurance left", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private struct RejectedBet: Error { var betId: String; var reason: String }

    func flushState() async throws {
        saveTask?.cancel(); saveTask = nil
        guard let data = pendingState, token != nil else { return }
        pendingState = nil
        guard let id = tokenUserId else { pendingState = data; throw AppError(code: "bad_token", message: "Your session is invalid. Log in again.") }
        do {
            var settingsValue: [String: Any] = [
                "followed_sports": data.settings.sports,
                "timezone": TimeZone.current.identifier,
                "notifications_enabled": data.settings.notify.settled || data.settings.notify.friends || data.settings.notify.lowTime,
            ]
            if supportsAppPreferences { settingsValue["app_preferences"] = Store.dictionary(data.settings) }
            let snapshotData = try JSONSerialization.data(withJSONObject: settingsValue, options: [.sortedKeys])
            let snapshot = String(data: snapshotData, encoding: .utf8) ?? ""
            if snapshot != lastSettingsSnapshot {
                _ = try await rest("user_settings?user_id=eq.\(Self.enc(id))", method: "PATCH", body: settingsValue, extra: ["Prefer": "return=minimal"])
                lastSettingsSnapshot = snapshot
            }
            for bet in data.bets {
                guard bet.kind == "sports", bet.stake > 0, !bet.legs.isEmpty,
                      bet.legs.allSatisfy({ ($0.kind == "game" || $0.kind == "sports") && $0.gameId != nil }) else { continue }
                var supabaseId = bet.supabaseId
                if supabaseId == nil && !placing.contains(bet.id) {
                    placing.insert(bet.id)
                    defer { placing.remove(bet.id) }
                    supabaseId = try await placeRemote(bet, data)
                }
                guard let sid = supabaseId, bet.status != "open", bet.supabaseSynced != true, !settling.contains(sid) else { continue }
                settling.insert(sid)
                defer { settling.remove(sid) }
                let status = ["push": "pushed", "void": "voided"][bet.status] ?? bet.status
                let legs: [[String: Any]] = bet.legs.map { leg in
                    ["espn_event_id": leg.gameId ?? "", "market": leg.market, "side": leg.side ?? "", "line": leg.line as Any? ?? NSNull(), "result": leg.result]
                }
                let settled = try await rest("rpc/timeout_settle_bet", method: "POST", body: ["p_bet_id": sid, "p_status": status, "p_actual_payout": bet.payout, "p_leg_results": legs])
                let synced = settled.bool != false
                update(bet.id) { $0.supabaseSynced = synced }
            }
            lastSaveAt = Date()
        } catch let rejected as RejectedBet {
            pendingState = nil
            refund(rejected.betId)
            switch rejected.reason {
            case "perkMigration": notify("perk", .loss, "Tier perks need Supabase setup", "This bet was not saved with its boost or insurance. Run the updated tier system migration, then reload the app.")
            case "perkUsed": notify("perk", .warn, "Tier perk already used", "This boost or insurance was already used on another device.")
            case "bonusMigration": notify("bonus", .loss, "Tier setup needed in Supabase", "This parlay was not saved. Run the tier system migration in Supabase SQL Editor, then reload the app.")
            default: notify("minutes", .loss, "Out of betting minutes", "Betting reopens at midnight.")
            }
        } catch {
            pendingState = pendingState ?? data
            throw error
        }
    }

    /// Saves one bet through the newest RPC the database has, falling back like the web demo.
    private func placeRemote(_ bet: Bet, _ data: UserData) async throws -> String {
        let payout = bet.payout > 0 ? bet.payout
            : max(0, bet.stake + jsRoundInt(Double(jsRoundInt(Double(bet.stake) * bet.decimal) - bet.stake) * bet.multiplier))
        let bonusToday = data.wallet.bonusDay == data.wallet.dayKey ? data.wallet.bonusGranted : 0
        let legs: [[String: Any]] = bet.legs.map { leg in
            ["espn_event_id": leg.gameId ?? "", "league": leg.league ?? "unknown", "matchup": leg.matchup, "market": leg.market,
             "side": leg.side ?? "", "line": leg.line as Any? ?? NSNull(), "accepted_odds": leg.price]
        }
        let legacy: [String: Any] = ["p_stake_minutes": bet.stake, "p_combined_odds": bet.decimal, "p_potential_payout": payout,
                                     "p_current_day": data.wallet.dayKey, "p_legs": legs]
        var args = legacy
        args["p_use_boost"] = bet.boosted
        args["p_use_insurance"] = bet.insured
        args["p_multiplier"] = bet.multiplier
        let perk = bet.boosted || bet.insured
        func reject(_ message: String) -> Error {
            if Self.isOutOfMinutes(message) {
                return RejectedBet(betId: bet.id, reason: supportsTierBonusColumns == false && bonusToday > 0 ? "bonusMigration" : "minutes")
            }
            return AppError(code: "supabase_error", message: message)
        }
        var saved: JSON
        do {
            if perk && supportsTierPerkColumns == false { throw RejectedBet(betId: bet.id, reason: "perkMigration") }
            saved = try await rest("rpc/timeout_place_bet_with_perks", method: "POST", body: args)
        } catch let e as AppError {
            if Self.rpcMissing(e.message, "timeout_place_bet_with_perks") {
                if perk { throw RejectedBet(betId: bet.id, reason: "perkMigration") }
                do {
                    saved = try await rest("rpc/\(bonusToday > 0 ? "timeout_place_bet_with_tiers" : "timeout_place_bet")", method: "POST", body: legacy)
                } catch let e2 as AppError { throw reject(e2.message) }
            } else if Self.rpcMissing(e.message, "timeout_place_bet_with_tiers") && !perk {
                do { saved = try await rest("rpc/timeout_place_bet", method: "POST", body: legacy) } catch let e2 as AppError { throw reject(e2.message) }
            } else if Self.perkExhausted(e.message) {
                throw RejectedBet(betId: bet.id, reason: "perkUsed")
            } else {
                throw reject(e.message)
            }
        }
        guard let betId = saved.string ?? saved["id"].string else { throw AppError(code: "supabase_error", message: "Supabase did not return the saved bet ID.") }
        update(bet.id) { $0.supabaseId = betId; $0.supabaseSynced = false }
        return betId
    }

    private func update(_ betId: String, _ fn: (inout Bet) -> Void) {
        let store = Store.shared
        guard var d = store.data, let i = d.bets.firstIndex(where: { $0.id == betId }) else { return }
        fn(&d.bets[i])
        store.data = d
        store.saveQuiet()
    }

    /// The server refused a bet: take it off and give the stake back.
    private func refund(_ betId: String) {
        let store = Store.shared
        guard var d = store.data, let bet = d.bets.first(where: { $0.id == betId }) else { return }
        d.bets.removeAll { $0.id == betId }
        d.wallet.balance = max(0, d.wallet.balance + bet.stake)
        d.wallet.lockedOut = d.wallet.balance <= 0
        store.data = d
        store.saveQuiet()
    }

    struct ProfilePatch { var username: String?; var photoUrl: String?; var email: String?; var password: String? }

    func updateProfile(_ patch: ProfilePatch) async throws {
        try await ensureFreshSession()
        guard let userId = tokenUserId else { throw AppError(code: "bad_token", message: "Your session is invalid. Log in again.") }
        var body: [String: Any] = [:]
        if let u = patch.username { body["username"] = u }
        if let p = patch.photoUrl { body["avatar_url"] = p }
        if !body.isEmpty {
            _ = try await rest("profiles?id=eq.\(Self.enc(userId))", method: "PATCH", body: body, extra: ["Prefer": "return=minimal"])
        }
        if patch.email != nil || patch.password != nil {
            var auth: [String: Any] = [:]
            if let e = patch.email { auth["email"] = e }
            if let p = patch.password { auth["password"] = p }
            _ = try await send(URL(string: "\(Self.baseURL)/auth/v1/user")!, method: "PUT", body: try JSONSerialization.data(withJSONObject: auth))
        }
    }

    func logout() async {
        try? await flushState()
        if token != nil { _ = try? await send(URL(string: "\(Self.baseURL)/auth/v1/logout")!, method: "POST") }
        clearToken()
        lastSettingsSnapshot = ""
    }

    // MARK: People

    struct FoundUser: Hashable { var username: String; var name: String; var photo: String? }

    /// Usernames matching a query, from Supabase profiles. A failure is just no extra rows.
    func searchUsers(_ query: String) async -> [FoundUser] {
        var safe = query.trimmingCharacters(in: .whitespaces)
        if safe.hasPrefix("@") { safe.removeFirst() }
        safe = String(safe.prefix(20).filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }.filter(\.isASCII))
        guard !safe.isEmpty, configured, token != nil else { return [] }
        let me = Store.shared.account?.username.lowercased() ?? ""
        let like = safe.replacingOccurrences(of: "_", with: "\\_")
        guard let rows = try? await rest("profiles?select=username,display_name,avatar_url&username=ilike.*\(Self.enc(like))*&limit=8", timeout: 4) else { return [] }
        var out: [FoundUser] = []
        for r in rows.array {
            guard let u = r["username"].text, u.lowercased() != me, !out.contains(where: { $0.username.lowercased() == u.lowercased() }),
                  u.range(of: #"^[a-zA-Z0-9_.]{1,20}$"#, options: .regularExpression) != nil else { continue }
            out.append(FoundUser(username: u, name: r["display_name"].text ?? u, photo: r["avatar_url"].text))
        }
        return Array(out.prefix(8))
    }

    // MARK: Teams

    struct RemoteTeam { var id: String; var name: String; var start: String; var end: String; var owner: String?; var members: [String] }
    enum TeamFetch { case team(RemoteTeam), gone, unreachable }

    private static func team(_ json: JSON) -> RemoteTeam? {
        guard let id = json["id"].text else { return nil }
        return RemoteTeam(id: id, name: json["name"].string ?? "", start: json["start"].string ?? "", end: json["end"].string ?? "",
                          owner: json["owner"].text, members: json["members"].array.compactMap(\.string))
    }

    private var canUseTeams: Bool { configured && token != nil }

    /// Save one new team. A repeat with the same link returns the roster and does not add people again.
    func publishTeam(_ team: Squad) async -> RemoteTeam? {
        guard let key = team.shareKey, canUseTeams else { return nil }
        let body: [String: Any] = ["p_id": team.id, "p_name": team.name, "p_start": team.start, "p_end": team.end, "p_key": key, "p_members": team.members]
        return (try? await rest("rpc/timeout_save_team", method: "POST", body: body, timeout: 4)).flatMap(Self.team)
    }

    func addTeamMember(_ team: Squad, username: String) async -> RemoteTeam? {
        guard let key = team.shareKey, canUseTeams else { return nil }
        let body: [String: Any] = ["p_id": team.id, "p_key": key, "p_username": username]
        if let r = try? await rest("rpc/timeout_add_team_member", method: "POST", body: body, timeout: 4) {
            if let t = Self.team(r) { return t }
            // The team isn't on the server yet: save it, then add again.
            _ = await publishTeam(team)
            return (try? await rest("rpc/timeout_add_team_member", method: "POST", body: body, timeout: 4)).flatMap(Self.team)
        }
        return nil
    }

    func leaveTeamRemote(_ team: Squad, username: String) async -> RemoteTeam? {
        guard let key = team.shareKey, canUseTeams else { return nil }
        let body: [String: Any] = ["p_id": team.id, "p_key": key, "p_username": username]
        return (try? await rest("rpc/timeout_leave_team", method: "POST", body: body, timeout: 4)).flatMap(Self.team)
    }

    /// The roster, `.gone` when the link is wrong or the team is gone, `.unreachable` when the server can't be reached.
    func fetchTeam(_ id: String, key: String) async -> TeamFetch {
        guard canUseTeams else { return .unreachable }
        guard let row = try? await rest("rpc/timeout_get_team", method: "POST", body: ["p_id": id, "p_key": key], timeout: 4) else { return .unreachable }
        return Self.team(row).map { .team($0) } ?? .gone
    }

    /// Teams this signed-in profile is on. Nil means "don't change the local list".
    func myTeams() async -> [RemoteTeam]? {
        guard canUseTeams, let rows = try? await rest("rpc/timeout_my_teams", method: "POST", body: [String: Any](), timeout: 4), rows.isArray else { return nil }
        return rows.array.compactMap(Self.team)
    }
}
