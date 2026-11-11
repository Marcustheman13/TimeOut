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
    static let privacyURL = URL(string: "https://marcustheman13.github.io/TimeOut/privacy.html")!
    static let supportURL = URL(string: "https://marcustheman13.github.io/TimeOut/support.html")!

    private(set) var configured = true
    private(set) var online = true

    private let tokenKey = "timeout.supabase.session"
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingState: UserData?
    @ObservationIgnored private var lastSaveAt: Date = .distantPast
    @ObservationIgnored private var lastSettingsSnapshot = ""
    @ObservationIgnored private var lastLedgerSnapshot = ""
    @ObservationIgnored private var supportsSharedLedger = true
    @ObservationIgnored private var supportsAppPreferences = true
    @ObservationIgnored private var supportsTierBonusColumns: Bool?
    @ObservationIgnored private var supportsTierPerkColumns: Bool?
    @ObservationIgnored private var placing = Set<String>()
    @ObservationIgnored private var settling = Set<String>()
    @ObservationIgnored private var alertTimes: [String: Date] = [:]
    @ObservationIgnored private var syncedStreak: Int?
    @ObservationIgnored private var inviteCode: String?

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
            let raw = json["msg"].text ?? json["message"].text ?? json["error_description"].text ?? json["error"].text ?? "Request failed (\(status))."
            throw Self.friendlyError(raw, errorCode: json["error_code"].text ?? json["code"].text, status: status)
        }
        return json
    }

    /// Turns Supabase and Postgres errors (like "duplicate key value violates unique constraint") into messages people understand.
    static func friendlyError(_ raw: String, errorCode: String?, status: Int) -> AppError {
        let m = raw.lowercased(), code = (errorCode ?? "").lowercased()
        func err(_ c: String, _ message: String, _ field: String? = nil, _ fieldText: String? = nil) -> AppError {
            AppError(code: c, message: message, fields: field.map { [$0: fieldText ?? message] } ?? [:], status: status)
        }
        if m.contains("profiles_username_key") || (m.contains("duplicate key") && m.contains("username")) {
            return err("taken", "That username is taken. Try another.", "username")
        }
        if m.contains("database error saving new user") {
            return err("taken", "We couldn't create your account. That username may already be taken, so try another.", "username", "Try a different username.")
        }
        if code == "user_already_exists" || code == "email_exists" || m.contains("user already registered") {
            return err("taken", "An account with this email already exists. Log in instead.", "email", "An account with this email already exists.")
        }
        if code == "email_not_confirmed" || m.contains("email not confirmed") {
            return err("email_not_confirmed", "Confirm your email first. Open the link we sent you, or send a new one.")
        }
        if code == "invalid_credentials" || m.contains("invalid login credentials") {
            return err("bad_login", "That email or password is incorrect.", "password", "Check your email and password, then try again.")
        }
        if m.contains("rate limit") || code.contains("rate_limit") {
            return err("rate_limit", "Too many emails or tries in a short time. Wait a few minutes, then try again.")
        }
        if m.contains("unable to validate email") || m.contains("invalid format") || code == "email_address_invalid" {
            return err("invalid", "Enter a valid email address.", "email")
        }
        if code == "weak_password" || m.contains("password should") || m.contains("password is") {
            return err("invalid", raw, "password")
        }
        if m.contains("duplicate key") {
            return err("taken", "That's already taken. Try something else.")
        }
        if m.contains("jwt") {
            return err("bad_token", "Your session expired. Log in again.")
        }
        // Our own database functions explain themselves. Everything else from the database is technical.
        if code == "p0001" {
            let known = ["sign in required": "Your session expired. Log in again.", "not enough challenge minutes": "You're out of pledge minutes for today. Pledges reopen at midnight.",
                         "wallet is not set up": AppError.unavailable]
            return AppError(code: "supabase_error", message: known[m] ?? raw, status: status, debug: raw)
        }
        let technical = code.hasPrefix("pgrst") || code.range(of: "^[0-9a-z]{5}$", options: .regularExpression) != nil || status >= 500
            || m.range(of: "schema cache|relation |column |function |syntax|permission denied|violates|row-level|supabase|postgres|request failed", options: .regularExpression) != nil
        if technical { return AppError(code: "supabase_error", message: AppError.unavailable, status: status, debug: raw) }
        if status == 401 || status == 403 { return err("bad_token", "Your session expired. Log in again.") }
        var fields: [String: String] = [:]
        if m.contains("username") { fields["username"] = raw } else if m.contains("email") { fields["email"] = raw } else if m.contains("password") { fields["password"] = raw }
        return AppError(code: status == 409 ? "taken" : "supabase_error", message: raw, fields: fields, status: status, debug: raw)
    }

    private func authRequest(_ path: String, _ body: [String: Any], auth: Bool = false) async throws -> JSON {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await send(URL(string: "\(Self.baseURL)/auth/v1/\(path)")!, method: "POST", body: data, auth: auth)
    }

    private func ensureFreshSession() async throws {
        guard let s = stored, let refresh = s.refresh_token else { return }
        if (s.expires_at ?? 0) > Date().timeIntervalSince1970 + 60 { return }
        do {
            let fresh = try await authRequest("token?grant_type=refresh_token", ["refresh_token": refresh])
            saveSession(fresh)
        } catch let e as AppError where (400..<500).contains(e.status ?? 0) {
            // The login was revoked or used on another device: sign out instead of failing every sync.
            sessionExpired()
            throw AppError(code: "bad_token", message: "Your session expired. Log in again.", status: 401)
        }
    }

    private func sessionExpired() {
        guard token != nil else { return }
        clearToken()
        pendingState = nil
        saveTask?.cancel(); saveTask = nil
        lastSettingsSnapshot = ""
        Slip.shared.clear()
        Store.shared.logout()
        AppModel.shared.boot()
        UIState.shared.toast(.warn, "Your session expired", "Log in again to keep your challenges in sync.")
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
        // Launch with -offline to test without Supabase: accounts are saved on this device only.
        if ProcessInfo.processInfo.arguments.contains("-offline") { configured = false; online = false }
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
        async let challengeRowsTask = rest("challenges?select=*,challenge_picks(*)&user_id=eq.\(safe)&order=placed_at.desc")
        var walletRows: JSON
        do {
            walletRows = try await rest("wallets?select=\(bonus),tier_boosts_by_day,tier_insurance_by_week&user_id=eq.\(safe)&limit=1")
        } catch let e as AppError where e.raw.range(of: "tier_boosts_by_day|tier_insurance_by_week|column .*does not exist", options: .regularExpression) != nil {
            hasPerks = false
            do {
                walletRows = try await rest("wallets?select=\(bonus)&user_id=eq.\(safe)&limit=1")
            } catch let e2 as AppError where e2.raw.range(of: "tier_bonus_day|tier_bonus_minutes|column .*does not exist", options: .regularExpression) != nil {
                hasBonus = false
                walletRows = try await rest("wallets?select=\(base)&user_id=eq.\(safe)&limit=1")
            }
        }
        let challengeRows = try await challengeRowsTask
        supportsTierBonusColumns = hasBonus
        supportsTierPerkColumns = hasPerks
        var settingsRows: JSON
        do {
            settingsRows = try await rest("user_settings?select=followed_sports,timezone,notifications_enabled,app_preferences&user_id=eq.\(safe)&limit=1")
            supportsAppPreferences = true
        } catch let e as AppError where e.raw.range(of: "app_preferences", options: .caseInsensitive) != nil {
            supportsAppPreferences = false
            settingsRows = try await rest("user_settings?select=followed_sports,timezone,notifications_enabled&user_id=eq.\(safe)&limit=1")
        }
        // "pushed" and "push" are the previous database labels, kept so a database that has not
        // run server/db/rename-challenge-vocabulary.sql still loads.
        let statusMap = ["pending": "open", "won": "won", "lost": "lost", "tied": "tie", "pushed": "tie", "voided": "void", "cancelled": "void"]
        let resultMap = ["pending": "pending", "win": "won", "loss": "lost", "tie": "tie", "push": "tie", "void": "void"]
        var state = RemoteState()
        state.challenges = challengeRows.array.map { row in
            let picks: [Pick] = row["challenge_picks"].array.map { pick in
                let eventId = pick["espn_event_id"].string ?? ""
                let market = pick["market"].string ?? "winner", side = pick["side"].string ?? ""
                let line = pick["line"].number
                let matchup = pick["matchup"].string ?? ""
                var l = Pick(selId: "\(eventId)|\(market)|\(side)", kind: "game", market: market, price: Int(pick["accepted_value"].number ?? 100),
                            label: Sim.pickLabel(market: market, side: side, line: line, matchup: matchup), marketLabel: Sim.marketTitle(market), matchup: matchup)
                l.gameId = eventId; l.league = pick["league"].string; l.side = side; l.line = line
                l.result = resultMap[pick["result"].string ?? ""] ?? "pending"
                return l
            }
            let decimal = row["combined_value"].number ?? 1
            let placedAt = LiveFeed.parseDate(row["placed_at"].string) ?? TO.now()
            var challenge = Challenge(id: "supabase-\(row["id"].string ?? "")", kind: "sports", placedAt: placedAt, dayKey: TO.dayKey(placedAt),
                          pledgeMinutes: Int(row["pledge_minutes"].number ?? 0), picks: picks, decimal: decimal, american: PointValueMath.fromDecimal(decimal))
            challenge.supabaseId = row["id"].string
            challenge.boosted = row["boosted"].truthy
            challenge.insured = row["insured"].truthy
            challenge.multiplier = row["multiplier"].number ?? 1
            challenge.status = statusMap[row["status"].string ?? ""] ?? "open"
            challenge.reward = Int(row["actual_reward_minutes"].number ?? 0)
            challenge.potentialReward = Int(row["potential_reward_minutes"].number ?? 0)
            challenge.resolvedAt = LiveFeed.parseDate(row["resolved_at"].string)
            challenge.supabaseSynced = row["status"].string != "pending"
            return challenge
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
            for v in (prefs["sports"] as? [String]) ?? settings["followed_sports"].array.compactMap({ $0.string }) {
                if Sim.realLeagues.contains(v), !followed.contains(v) { followed.append(v) }
            }
            if !followed.isEmpty { prefs["sports"] = followed }
            state.settings = prefs
            state.appPreferencesReady = supportsAppPreferences
        }
        if supportsSharedLedger {
            do {
                let rows = try await rest("user_settings?select=shared_ledger&user_id=eq.\(safe)&limit=1")
                let ledger = rows[0]["shared_ledger"]
                if ledger.isObject, let raw = try? JSONSerialization.data(withJSONObject: Self.any(ledger)),
                   let decoded = try? JSONDecoder().decode(SharedLedger.self, from: raw) {
                    state.shared = decoded
                    lastLedgerSnapshot = Self.ledgerSnapshot(decoded)
                }
            } catch {
                noteLedgerError(error) // server/db/supabase-shared-ledger.sql may not have been run
            }
        }
        return state
    }

    private static func ledgerSnapshot(_ ledger: SharedLedger) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(ledger)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func noteLedgerError(_ error: Error) {
        if let e = error as? AppError, e.raw.range(of: "shared_ledger", options: .caseInsensitive) != nil { supportsSharedLedger = false }
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
        case .array(let a): return a.map { any($0) }
        case .object(let o): return o.mapValues { any($0) }
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
                if Self.isOutOfMinutes((error as? AppError)?.raw ?? "") { notify("minutes", .loss, "Out of pledge minutes", "Pledges reopen at midnight."); return }
                notify("sync", .warn, "Couldn't sync your changes", "They're saved on this device, and TimeOut will try again.")
            }
        }
    }

    private func notify(_ key: String, _ kind: ToastKind, _ title: String, _ msg: String) {
        if let last = alertTimes[key], Date().timeIntervalSince(last) < 15 { return }
        alertTimes[key] = Date()
        UIState.shared.toast(kind, title, msg)
    }

    private static func isOutOfMinutes(_ m: String) -> Bool {
        m.range(of: "insufficient|not enough|out of (challenging )?(minutes|balance)|challenge minutes", options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func rpcMissing(_ m: String, _ name: String) -> Bool {
        m.range(of: name, options: .caseInsensitive) != nil
            && m.range(of: "schema cache|function.*(not found|does not exist|could not find)", options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func perkExhausted(_ m: String) -> Bool {
        m.range(of: "no point-value boosts left|no combo protection left", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private struct RejectedChallenge: Error { var challengeId: String; var reason: String }

    func flushState() async throws {
        saveTask?.cancel(); saveTask = nil
        guard let data = pendingState, token != nil else { return }
        pendingState = nil
        guard let id = tokenUserId else { pendingState = data; throw AppError(code: "bad_token", message: "Your session is invalid. Log in again.") }
        do {
            var settingsValue: [String: Any] = [
                "followed_sports": data.settings.sports,
                "timezone": TimeZone.current.identifier,
                "notifications_enabled": data.settings.notify.resolved || data.settings.notify.friends || data.settings.notify.lowTime,
            ]
            if supportsAppPreferences { settingsValue["app_preferences"] = Store.dictionary(data.settings) }
            let snapshotData = try JSONSerialization.data(withJSONObject: settingsValue, options: [.sortedKeys])
            let snapshot = String(data: snapshotData, encoding: .utf8) ?? ""
            if snapshot != lastSettingsSnapshot {
                _ = try await rest("user_settings?user_id=eq.\(Self.enc(id))", method: "PATCH", body: settingsValue, extra: ["Prefer": "return=minimal"])
                lastSettingsSnapshot = snapshot
            }
            // Its own column and its own write, so these frequent updates can't overwrite a settings change from another device.
            if supportsSharedLedger {
                var ledger = Store.shared.sharedLedger(data)
                // Another device may have recorded newer records since this one last read them: never write an older number over them.
                if let rows = try? await rest("user_settings?select=shared_ledger&user_id=eq.\(Self.enc(id))&limit=1"),
                   rows[0]["shared_ledger"].isObject,
                   let raw = try? JSONSerialization.data(withJSONObject: Self.any(rows[0]["shared_ledger"])),
                   let theirs = try? JSONDecoder().decode(SharedLedger.self, from: raw) {
                    ledger = ledger.merged(with: theirs)
                }
                let ledgerSnapshot = Self.ledgerSnapshot(ledger)
                if ledgerSnapshot != lastLedgerSnapshot,
                   let raw = try? JSONEncoder().encode(ledger), let body = try? JSONSerialization.jsonObject(with: raw) {
                    do {
                        _ = try await rest("user_settings?user_id=eq.\(Self.enc(id))", method: "PATCH", body: ["shared_ledger": body], extra: ["Prefer": "return=minimal"])
                        lastLedgerSnapshot = ledgerSnapshot
                    } catch {
                        noteLedgerError(error)
                    }
                }
            }
            for challenge in data.challenges {
                guard Store.syncsToServer(challenge) else { continue }
                var supabaseId = challenge.supabaseId
                if supabaseId == nil && !placing.contains(challenge.id) {
                    placing.insert(challenge.id)
                    defer { placing.remove(challenge.id) }
                    supabaseId = try await placeRemote(challenge, data)
                }
                guard let sid = supabaseId, challenge.status != "open", challenge.supabaseSynced != true, !settling.contains(sid) else { continue }
                settling.insert(sid)
                defer { settling.remove(sid) }
                let status = ["tie": "tied", "void": "voided"][challenge.status] ?? challenge.status
                let picks: [[String: Any]] = challenge.picks.map { pick in
                    ["espn_event_id": pick.gameId ?? "", "market": pick.market, "side": pick.side ?? "", "line": pick.line as Any? ?? NSNull(), "result": pick.result]
                }
                let resolved = try await rest("rpc/timeout_resolve_challenge", method: "POST", body: ["p_challenge_id": sid, "p_status": status, "p_actual_reward": challenge.reward, "p_pick_results": picks])
                let synced = resolved.bool != false
                update(challenge.id) { $0.supabaseSynced = synced }
            }
            // Friends see this streak. The app works it out on the device, so the server needs telling.
            if syncedStreak != data.wallet.streakDays {
                _ = try? await rest("rpc/timeout_set_streak", method: "POST", body: ["p_streak": data.wallet.streakDays], timeout: 4)
                syncedStreak = data.wallet.streakDays
            }
            lastSaveAt = Date()
        } catch let rejected as RejectedChallenge {
            pendingState = nil
            refund(rejected.challengeId)
            switch rejected.reason {
            case "perkMigration": notify("perk", .loss, "That perk isn't available right now", "Your pledge wasn't saved and your minutes were returned. Try it again without the perk.")
            case "perkUsed": notify("perk", .warn, "Perk already used", "You already used this perk on another device. Your pledge wasn't saved and your minutes were returned.")
            case "bonusMigration": notify("bonus", .loss, "Your pledge wasn't saved", "Your minutes were returned. Please try again in a few minutes.")
            default: notify("minutes", .loss, "Out of pledge minutes", "Pledges reopen at midnight. Your minutes were returned.")
            }
        } catch {
            pendingState = pendingState ?? data
            throw error
        }
    }

    /// Saves one challenge through the newest RPC the database has, falling back like the web demo.
    private func placeRemote(_ challenge: Challenge, _ data: UserData) async throws -> String {
        let reward = challenge.reward > 0 ? challenge.reward
            : min(Rules.maxAllowedMinutes, max(0, challenge.pledgeMinutes + jsRoundInt(Double(jsRoundInt(Double(challenge.pledgeMinutes) * challenge.decimal) - challenge.pledgeMinutes) * challenge.multiplier)))
        let bonusToday = data.wallet.bonusDay == data.wallet.dayKey ? data.wallet.bonusGranted : 0
        let picks: [[String: Any]] = challenge.picks.map { pick in
            ["espn_event_id": pick.gameId ?? "", "league": pick.league ?? "unknown", "matchup": pick.matchup, "market": pick.market,
             "side": pick.side ?? "", "line": pick.line as Any? ?? NSNull(), "accepted_value": pick.price]
        }
        let legacy: [String: Any] = ["p_pledge_minutes": challenge.pledgeMinutes, "p_combined_value": challenge.decimal, "p_potential_reward": reward,
                                     "p_current_day": data.wallet.dayKey, "p_picks": picks]
        var args = legacy
        args["p_use_boost"] = challenge.boosted
        args["p_use_insurance"] = challenge.insured
        args["p_multiplier"] = challenge.multiplier
        let perk = challenge.boosted || challenge.insured
        func reject(_ error: AppError) -> Error {
            if Self.isOutOfMinutes(error.raw) {
                return RejectedChallenge(challengeId: challenge.id, reason: supportsTierBonusColumns == false && bonusToday > 0 ? "bonusMigration" : "minutes")
            }
            return error
        }
        var saved: JSON
        do {
            if perk && supportsTierPerkColumns == false { throw RejectedChallenge(challengeId: challenge.id, reason: "perkMigration") }
            saved = try await rest("rpc/timeout_place_challenge_with_perks", method: "POST", body: args)
        } catch let e as AppError {
            if Self.rpcMissing(e.raw, "timeout_place_challenge_with_perks") {
                if perk { throw RejectedChallenge(challengeId: challenge.id, reason: "perkMigration") }
                do {
                    saved = try await rest("rpc/\(bonusToday > 0 ? "timeout_place_challenge_with_tiers" : "timeout_place_challenge")", method: "POST", body: legacy)
                } catch let e2 as AppError { throw reject(e2) }
            } else if Self.rpcMissing(e.raw, "timeout_place_challenge_with_tiers") && !perk {
                do { saved = try await rest("rpc/timeout_place_challenge", method: "POST", body: legacy) } catch let e2 as AppError { throw reject(e2) }
            } else if Self.perkExhausted(e.raw) {
                throw RejectedChallenge(challengeId: challenge.id, reason: "perkUsed")
            } else {
                throw reject(e)
            }
        }
        guard let challengeId = saved.string ?? saved["id"].string else { throw AppError(code: "supabase_error", message: AppError.unavailable, debug: "No challenge ID came back.") }
        update(challenge.id) { $0.supabaseId = challengeId; $0.supabaseSynced = false }
        return challengeId
    }

    private func update(_ challengeId: String, _ fn: (inout Challenge) -> Void) {
        let store = Store.shared
        guard var d = store.data, let i = d.challenges.firstIndex(where: { $0.id == challengeId }) else { return }
        fn(&d.challenges[i])
        store.data = d
        store.saveQuiet()
    }

    /// The server refused a challenge: take it off and give the pledge back.
    private func refund(_ challengeId: String) {
        let store = Store.shared
        guard var d = store.data, let challenge = d.challenges.first(where: { $0.id == challengeId }) else { return }
        d.challenges.removeAll { $0.id == challengeId }
        d.wallet.balance = max(0, d.wallet.balance + challenge.pledgeMinutes)
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

    /// Emails a password-reset link. Opening it signs the person in on the website, where Account can set a new password.
    func sendPasswordReset(_ email: String) async throws {
        _ = try await authRequest("recover?redirect_to=\(Self.enc(Self.returnURL))", ["email": email.trimmingCharacters(in: .whitespaces)])
    }

    /// Permanently deletes the signed-in account and its data (server/db/supabase-delete-account.sql).
    func deleteAccount() async throws {
        do {
            _ = try await rest("rpc/timeout_delete_account", method: "POST", body: [String: Any]())
        } catch let e as AppError where Self.rpcMissing(e.raw, "timeout_delete_account") {
            throw AppError(code: "not_set_up", message: "We can't delete your account right now. Please try again later, or contact support from the Help page.")
        }
        pendingState = nil
        saveTask?.cancel(); saveTask = nil
        clearToken()
        lastSettingsSnapshot = ""
        inviteCode = nil
    }

    func logout() async {
        try? await flushState()
        // While still signed in, so this phone stops getting this account's notifications.
        if token != nil, let device = Notifier.shared.deviceToken {
            _ = try? await rest("rpc/timeout_unregister_device", method: "POST", body: ["p_token": device], timeout: 4)
        }
        if token != nil { _ = try? await send(URL(string: "\(Self.baseURL)/auth/v1/logout")!, method: "POST") }
        clearToken()
        lastSettingsSnapshot = ""
        inviteCode = nil
        syncedStreak = nil
    }

    // MARK: Push

    /// Tells the server where this account's notifications go. A failure can wait: this runs again on every launch.
    func registerDevice(_ device: String, environment: String) async {
        guard token != nil else { return }
        do {
            _ = try await rest("rpc/timeout_register_device", method: "POST", body: ["p_token": device, "p_environment": environment], timeout: 8)
        } catch {
            print("TimeOut: couldn't register this phone for push: \(error)")
        }
    }

    // MARK: People

    struct FoundUser: Hashable { var username: String; var name: String; var photo: String? }

    /// Usernames matching a query. A failure is just no extra rows.
    func searchUsers(_ query: String) async -> [FoundUser] {
        var safe = query.trimmingCharacters(in: .whitespaces)
        if safe.hasPrefix("@") { safe.removeFirst() }
        safe = String(safe.prefix(20).filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }.filter(\.isASCII))
        guard !safe.isEmpty, configured, token != nil else { return [] }
        let me = Store.shared.account?.username.lowercased() ?? ""
        var rows = try? await rest("rpc/timeout_search_users", method: "POST", body: ["p_query": safe], timeout: 4)
        if rows == nil {
            // A database without the friends update: read profiles directly.
            let like = safe.replacingOccurrences(of: "_", with: "\\_")
            rows = try? await rest("profiles?select=username,name:display_name,photo:avatar_url&username=ilike.*\(Self.enc(like))*&limit=8", timeout: 4)
        }
        var out: [FoundUser] = []
        for r in rows?.array ?? [] {
            guard let u = r["username"].text, u.lowercased() != me, !out.contains(where: { $0.username.lowercased() == u.lowercased() }),
                  u.range(of: #"^[a-zA-Z0-9_.]{1,20}$"#, options: .regularExpression) != nil else { continue }
            out.append(FoundUser(username: u, name: r["name"].text ?? u, photo: r["photo"].text))
        }
        return Array(out.prefix(8))
    }

    // MARK: Friends

    struct SocialRequest { var id: String; var username: String; var name: String; var photo: String?; var at: Ms }
    struct SocialState { var friends: [SocialProfile]; var requestsIn: [SocialRequest]; var requestsOut: [SocialRequest] }

    /// Friends and requests from the server. Nil when it can't be reached or doesn't have the friends update yet.
    func socialState() async -> SocialState? {
        guard configured, token != nil, let json = try? await rest("rpc/timeout_social_state", method: "POST", body: [String: Any](), timeout: 6), json.isObject else { return nil }
        func request(_ r: JSON) -> SocialRequest? {
            guard let u = r["username"].text else { return nil }
            return SocialRequest(id: r["id"].string ?? u, username: u, name: r["name"].text ?? u, photo: r["photo"].text, at: LiveFeed.parseDate(r["at"].string) ?? TO.now())
        }
        let friends: [SocialProfile] = json["friends"].array.compactMap { f in
            guard let u = f["username"].text else { return nil }
            let share = PrivacySettings(record: f["share"]["record"].bool ?? false, minutes: f["share"]["minutes"].bool ?? false, challenges: f["share"]["challenges"].bool ?? false)
            let picks: [SharedPick] = f["picks"].array.map { c in
                let legs = c["picks"].array
                let label = legs.map { Sim.pickLabel(market: $0["market"].string ?? "winner", side: $0["side"].string ?? "", line: $0["line"].number, matchup: $0["matchup"].string ?? "") }.joined(separator: " + ")
                return SharedPick(label: label, matchup: legs.count > 1 ? "\(legs.count)-pick Combo Goal" : (legs.first?["matchup"].string ?? ""),
                                  price: PointValueMath.fromDecimal(c["combinedValue"].number ?? 1), pledgeMinutes: Int(c["pledgeMinutes"].number ?? 0))
            }
            return SocialProfile(username: u, name: f["name"].text ?? u, photo: f["photo"].text, w: Int(f["w"].number ?? 0), l: Int(f["l"].number ?? 0),
                                 net: Int(f["net"].number ?? 0), tier: f["tier"].text ?? "rookie", streak: Int(f["streak"].number ?? 0), share: share, picks: picks)
        }
        return SocialState(friends: friends, requestsIn: json["requestsIn"].array.compactMap(request), requestsOut: json["requestsOut"].array.compactMap(request))
    }

    // MARK: Weekly report

    /// The person's published weekly reports, newest first. Nil when it can't be reached or the database doesn't have them yet.
    func weeklyReports() async -> [WeeklyReport]? {
        guard configured, token != nil, let json = try? await rest("rpc/timeout_my_weekly_reports", method: "POST", body: ["p_limit": 12], timeout: 6), json.isArray else { return nil }
        return json.array.compactMap { item in
            let r = item["report"]
            guard let week = item["weekStart"].string, let headline = r["headline"].text else { return nil }
            let days: [WeeklyReport.Day]? = r["days"].isArray ? r["days"].array.map {
                WeeklyReport.Day(weekday: $0["weekday"].string ?? "", used: $0["used"].number.map { Int($0) }, limit: Int($0["limit"].number ?? 0), status: $0["status"].string ?? "none")
            } : nil
            return WeeklyReport(
                week: week, range: r["range"].string ?? "", weekType: r["weekType"].string ?? "steady", label: r["label"].string ?? "",
                headline: headline, summary: r["summary"].string ?? "", insight: r["insight"].string ?? "", suggestion: r["suggestion"]["text"].string ?? "",
                tiles: r["tiles"].array.compactMap { t in t["label"].string.map { WeeklyReport.Tile(label: $0, value: t["value"].string ?? "") } },
                days: days, read: item["read"].bool ?? false)
        }
    }

    func markWeeklyReportRead(_ week: String) async {
        guard configured, token != nil else { return }
        _ = try? await rest("rpc/timeout_mark_weekly_report_read", method: "POST", body: ["p_week": week], timeout: 6)
    }

    /// Runs one friends function. Turns "the database doesn't have it yet" into a sentence people can act on.
    private func friendCall(_ name: String, _ body: [String: Any]) async throws -> JSON {
        do {
            return try await rest("rpc/\(name)", method: "POST", body: body, timeout: 8)
        } catch let e as AppError where Self.rpcMissing(e.raw, name) {
            throw AppError(code: "not_set_up", message: "Friends aren't available right now. Please try again in a few minutes.")
        }
    }

    /// "requested", or "friends" when they had already asked you.
    func sendFriendRequest(_ username: String) async throws -> String {
        try await friendCall("timeout_send_friend_request", ["p_username": username]).string ?? "requested"
    }
    func answerFriendRequest(_ username: String, accept: Bool) async throws {
        let done = try await friendCall("timeout_answer_friend_request", ["p_username": username, "p_accept": accept])
        // The server answers false when it couldn't find that request. Don't pretend it worked.
        if done.bool == false {
            throw AppError(code: "request_missing", message: "Couldn't \(accept ? "accept" : "decline") the request from @\(username). Pull to refresh and try again.")
        }
    }
    func cancelFriendRequest(_ username: String) async throws {
        _ = try await friendCall("timeout_cancel_friend_request", ["p_username": username])
    }
    func removeFriend(_ username: String) async throws {
        _ = try await friendCall("timeout_remove_friend", ["p_username": username])
    }
    /// "friends", "requested" (no valid code, so it is an ordinary request) or "self".
    func acceptFriendInvite(_ username: String, code: String) async throws -> String {
        try await friendCall("timeout_accept_friend_invite", ["p_username": username, "p_code": code]).string ?? "requested"
    }
    /// The secret for this account's invite links. Nil only when the server can't provide one; the link then sends a request.
    func myInviteCode() async -> String? {
        if let inviteCode { return inviteCode }
        guard configured, token != nil, let code = (try? await rest("rpc/timeout_my_invite_code", method: "POST", body: [String: Any](), timeout: 4))?.string else { return nil }
        inviteCode = code
        return code
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

    func teamStandings(_ id: String, key: String) async -> [TeamStanding]? {
        guard canUseTeams, let rows = try? await rest("rpc/timeout_team_standings", method: "POST", body: ["p_id": id, "p_key": key], timeout: 4), rows.isArray else { return nil }
        return rows.array.compactMap { r in
            guard let u = r["username"].text else { return nil }
            return TeamStanding(username: u, photo: r["photo"].text, tier: r["tier"].text ?? "rookie", hidden: r["hidden"].bool ?? true,
                                w: Int(r["w"].number ?? 0), l: Int(r["l"].number ?? 0), net: Int(r["net"].number ?? 0))
        }
    }

    /// Teams this signed-in profile is on. Nil means "don't change the local list".
    func myTeams() async -> [RemoteTeam]? {
        guard canUseTeams, let rows = try? await rest("rpc/timeout_my_teams", method: "POST", body: [String: Any](), timeout: 4), rows.isArray else { return nil }
        return rows.array.compactMap(Self.team)
    }
}
