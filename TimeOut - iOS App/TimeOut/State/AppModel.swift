import BackgroundTasks
import Foundation
import Observation
import SwiftUI
import UIKit
import UserNotifications

/// App shell logic from the web demo's app.js: boot, the live loop, resolution alerts and Supabase sync.
@Observable
final class AppModel {
    static let shared = AppModel()
    static let backgroundTaskID = "com.marcuswilliams.staketime.resolve"

    /// False until the first session restore finishes (shows the launch screen).
    private(set) var ready = false
    /// Bumped every 5 seconds so relative times ("starts in 4 min") stay current.
    private(set) var tick = 0

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastFull: Date = .distantPast
    @ObservationIgnored private var lastLiveVersion = -1
    @ObservationIgnored private var lastRemoteSync: Date = .distantPast
    @ObservationIgnored private var remoteSyncing = false
    @ObservationIgnored private var started = false

    private var store: Store { .shared }
    private var ui: UIState { .shared }
    private var live: LiveFeed { .shared }

    var inShell: Bool { store.account != nil && store.data?.onboarded == true }

    // MARK: Start

    func start() {
        guard !started else {
            syncRemoteState(force: true)
            ScreenTime.shared.refresh()
            tickNow(force: true)
            return
        }
        started = true
        Net.shared.start()
        Task {
            if await API.shared.initialize() { await restoreServerSession() }
            if store.account == nil { store.loadSession() }
            boot()
            ready = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in AppModel.shared.tickNow(force: false) }
            }
        }
    }

    /// The database decides who is logged in. Re-reads the user on every launch.
    private func restoreServerSession() async {
        guard API.shared.hasToken else { store.logout(); return }
        do {
            let user = try await API.shared.me()
            store.adoptServerUser(user, remote: try await API.shared.loadState())
        } catch let e as AppError {
            if e.status == 401 || e.status == 403 { API.shared.clearToken(); store.logout(); return }
            ui.toast(.loss, "Couldn't load your account", e.message)
        } catch {
            // Offline: keep the session saved on this device so the app still opens.
        }
    }

    func boot() {
        ui.closeAllSheets()
        ui.closeAllPages()
        ui.drawerOpen = false
        guard store.account != nil, let data = store.data else {
            AuthModel.shared.show(.welcome)
            return
        }
        if !data.onboarded {
            AuthModel.shared.startOnboarding()
            return
        }
        ui.tab = Notifier.shared.takeLaunchTab() ?? "home"
        live.refresh(force: true)
        live.refreshUpcoming()
        Task {
            await syncSocial()
            await store.refreshTeams()
        }
        Invites.offer()
        ScreenTime.shared.sync()
        requestNotifications()
        #if DEBUG
        ScreenshotSeed.runIfRequested()
        #endif
    }

    /// Challenge results, friend requests and low-time warnings arrive as notifications while the app is in the background.
    private func requestNotifications() {
        Task { await Notifier.shared.requestIfNeeded() }
    }

    // MARK: Live loop

    func tickNow(force: Bool) {
        let now = TO.now()
        // Resolve as soon as new scores arrive (the web's live:updated event).
        if live.version != lastLiveVersion {
            lastLiveVersion = live.version
            if inShell { notifyResolved(store.resolve(now)) }
        }
        if Races.shared.finalizeIfDone(now), inShell { notifyResolved(store.resolve(now)) }
        if !force && Date().timeIntervalSince(lastFull) < 5 { return }
        lastFull = Date()
        tick &+= 1
        guard inShell else { return }

        live.refresh(now)
        live.refreshUpcoming(now)

        // Midnight reset, challenge resolution and friend activity.
        if store.rollover(now) {
            store.save()
            ui.toast(.info, "Your daily minutes refreshed", "Today's phone limit is \(store.wallet.todayLimit) min after yesterday's challenge results.")
        }
        notifyResolved(store.resolve(now))
        for username in store.socialTick(now) where store.data?.settings.notify.friends == true {
            Notifier.shared.announce(.win, "@\(username) accepted your friend request", "", id: "friend-\(username)", tab: "social")
        }
        ScreenTime.shared.sync()
        store.checkPhoneTime()
        if Date().timeIntervalSince(lastRemoteSync) > 30 { syncRemoteState() }
    }

    func notifyResolved(_ list: [Challenge]) {
        guard store.data?.settings.notify.resolved == true else { return }
        for b in list {
            let title = ChallengeText.title(b)
            // The same id the server's push uses, so a result that arrives both ways only shows once.
            let id = b.supabaseId ?? b.id
            if b.status == "won" { Notifier.shared.announce(.win, "Challenge complete: \(title)", "+\(b.reward - b.pledgeMinutes) earned minutes added to tomorrow's phone time.", id: id, tab: "challenges") }
            else if b.status == "lost" { Notifier.shared.announce(.loss, "Challenge missed: \(title)", "\(b.pledgeMinutes) committed minutes deducted from tomorrow's phone time.", id: id, tab: "challenges") }
            else { Notifier.shared.announce(.info, "Challenge returned: \(title)", "\(b.insurancePaid == true ? "Miss-one protection returned your minutes." : "The game was postponed.") \(b.pledgeMinutes) minutes are available again.", id: id, tab: "challenges") }
        }
    }

    func netChanged() {
        if Net.shared.online { ui.toast(.win, "Back online", "Matchup targets are updating again.") }
    }

    /// Challenges placed on another device (or the website) show up here within 30 seconds.
    func syncRemoteState(force: Bool = false) {
        guard inShell, API.shared.configured, API.shared.hasToken, let server = store.account?.server, !remoteSyncing else { return }
        if !force && Date().timeIntervalSince(lastRemoteSync) < 30 { return }
        lastRemoteSync = Date()
        remoteSyncing = true
        Task {
            defer { remoteSyncing = false }
            await syncSocial()
            guard let state = try? await API.shared.loadState(), inShell else { return }
            store.adoptServerUser(server, remote: state)
        }
    }

    /// Friends and requests from the server, with a banner or notification for anything new.
    /// `quiet` is for after the user's own action, which already says what happened.
    func syncSocial(quiet: Bool = false) async {
        guard inShell, store.usesServerSocial, let state = await API.shared.socialState() else { return }
        let changes = store.applySocial(state)
        guard !quiet, store.data?.settings.notify.friends == true else { return }
        for u in changes.newRequests {
            Notifier.shared.announce(.info, "@\(u) sent you a friend request", "Open Social to accept it.", id: "request-\(u)", tab: "social")
        }
        for u in changes.newFriends {
            Notifier.shared.announce(.win, "You and @\(u) are now friends", "", id: "friend-\(u)", tab: "social")
        }
    }

    func didEnterBackground() {
        // Ask iOS for a moment so the last changes reach the server before the app is suspended.
        let task = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        Task {
            try? await API.shared.flushState()
            UIApplication.shared.endBackgroundTask(task)
        }
        ScreenTime.shared.sync()
        scheduleBackgroundRefresh()
    }

    // MARK: Background resolution

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do { try BGTaskScheduler.shared.submit(request) } catch { print("TimeOut: couldn't schedule a background refresh: \(error)") }
    }

    /// Runs when iOS wakes the app: refresh scores, resolve, tell the user, and publish tomorrow's limit for the monitor.
    /// iOS can launch the app just for this, without the screen ever opening, so the session may not be loaded yet.
    func backgroundRefresh() async {
        scheduleBackgroundRefresh()
        if store.account == nil { store.loadSession() }
        guard inShell else { return }
        let now = TO.now()
        if store.rollover(now) { store.save() }
        live.refresh(force: true)
        for _ in 0..<40 {
            if !live.loading { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        _ = await live.loadOldChallengeGames(TO.now())
        notifyResolved(store.resolve(TO.now()))
        await syncSocial()
        ScreenTime.shared.sync()
        try? await API.shared.flushState()
    }

    // MARK: Links

    /// timeout://invite?invite=user&team=… or the web app's ?invite= links.
    func handle(url: URL) {
        Invites.capture(url)
        if inShell { Invites.offer() }
    }
}

/// Friend and team invite links, like the web app's `TO.invites`.
enum Invites {
    struct Pending: Codable {
        var invite: String; var team: String; var teamName: String; var start: String; var end: String; var key: String
        var code = ""

        enum CodingKeys: String, CodingKey { case invite, team, teamName, start, end, key, code }

        init(invite: String, team: String, teamName: String, start: String, end: String, key: String, code: String) {
            self.invite = invite; self.team = team; self.teamName = teamName; self.start = start; self.end = end; self.key = key; self.code = code
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            invite = try c.decode(String.self, forKey: .invite)
            team = try c.decode(String.self, forKey: .team)
            teamName = try c.decode(String.self, forKey: .teamName)
            start = try c.decode(String.self, forKey: .start)
            end = try c.decode(String.self, forKey: .end)
            key = try c.decode(String.self, forKey: .key)
            code = (try? c.decode(String.self, forKey: .code)) ?? ""
        }
    }
    private static let key = "timeout.invite"

    /// `?invite=username&code=…` is the friend link (`?join=` works too). The code makes it a two-way yes.
    /// A team link adds team, teamName, start, end and key.
    static func friendLink(code: String? = nil) -> String {
        var c = URLComponents(string: API.webURL)!
        var items = [URLQueryItem(name: "invite", value: Store.shared.account?.username ?? "")]
        if let code { items.append(URLQueryItem(name: "code", value: code)) }
        c.queryItems = items
        return c.url?.absoluteString ?? API.webURL
    }

    static func teamLink(_ team: Squad, code: String? = nil) -> String {
        var c = URLComponents(string: API.webURL)!
        let me = Store.shared.account?.username
        // The code belongs to the person sharing, so the link has to name that person too.
        var items = [URLQueryItem(name: "invite", value: code != nil ? me : (team.owner.isEmpty ? me : team.owner)),
                     URLQueryItem(name: "team", value: team.id), URLQueryItem(name: "teamName", value: team.name),
                     URLQueryItem(name: "start", value: team.start), URLQueryItem(name: "end", value: team.end)]
        if let k = team.shareKey { items.append(URLQueryItem(name: "key", value: k)) }
        if let code { items.append(URLQueryItem(name: "code", value: code)) }
        c.queryItems = items
        return c.url?.absoluteString ?? API.webURL
    }

    static func capture(_ url: URL) {
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ k: String) -> String { q.first { $0.name == k }?.value ?? "" }
        var invite = (v("invite").isEmpty ? v("join") : v("invite")).trimmingCharacters(in: .whitespaces)
        if invite.hasPrefix("@") { invite.removeFirst() }
        let team = v("team").trimmingCharacters(in: .whitespaces)
        guard !invite.isEmpty || !team.isEmpty else { return }
        let p = Pending(invite: invite, team: team, teamName: v("teamName"), start: v("start"), end: v("end"), key: v("key"), code: v("code"))
        if let raw = try? JSONEncoder().encode(p) { UserDefaults.standard.set(raw, forKey: key) }
    }

    static var pending: Pending? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    static func offer() {
        guard let p = pending, let acc = Store.shared.account, let d = Store.shared.data, d.onboarded else { return }
        let own = !p.invite.isEmpty && Store.sameUser(p.invite, acc.username)
        let already = !p.team.isEmpty && d.teams.contains { $0.id == p.team && $0.members.contains { Store.sameUser($0, acc.username) } }
        if own && (p.team.isEmpty || already) { clear(); return }
        if UIState.shared.sheetOpen(.invite) { return }
        UIState.shared.openSheet(.invite)
    }

    static func accept() {
        guard let p = pending, let me = Store.shared.account?.username else { return }
        let ui = UIState.shared
        Task {
            var friendResult: String?
            var failure: String?
            if !p.invite.isEmpty && !Store.sameUser(p.invite, me) {
                if Store.shared.usesServerSocial {
                    do {
                        friendResult = try await API.shared.acceptFriendInvite(p.invite, code: p.code)
                        await AppModel.shared.syncSocial(quiet: true)
                    } catch { failure = (error as? AppError)?.message ?? error.localizedDescription }
                } else {
                    Store.shared.addFriend(p.invite)
                    friendResult = "friends"
                }
            }
            var team: Squad?
            if !p.team.isEmpty && !p.teamName.isEmpty && !p.start.isEmpty && !p.end.isEmpty {
                let key = p.key.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil ? p.key : nil
                do {
                    team = try Store.shared.joinTeam(.init(id: p.team, name: p.teamName, start: p.start, end: p.end, owner: p.invite.isEmpty ? nil : p.invite,
                                                           shareKey: key, members: p.invite.isEmpty ? [] : [p.invite]))
                } catch let e as AppError {
                    ui.toast(.warn, "Could not join that team", e.message)
                } catch {}
            }
            clear()
            ui.closeSheet(.invite, silent: true)
            if team != nil { SocialModel.shared.tab = "teams" } else if friendResult == "requested" { SocialModel.shared.tab = "requests" } else if !p.invite.isEmpty { SocialModel.shared.tab = "board" }
            ui.go("social")
            if let failure { ui.toast(.loss, "Couldn't add @\(p.invite)", failure) }
            else if let team { ui.toast(.win, "You joined \(team.name)") }
            else if friendResult == "requested" { ui.toast(.win, "Friend request sent to @\(p.invite)", "That link has expired, so they'll need to accept.") }
            else { ui.toast(.win, "You and @\(p.invite) are now friends") }
        }
    }
}

/// Challenge titles shared by toasts, cards and the share image.
enum ChallengeText {
    static func title(_ b: Challenge) -> String {
        if b.kind == "todo" { return "To-do Combo Goal · \(b.picks.count) task\(b.picks.count == 1 ? "" : "s")" }
        return b.picks.count > 1 ? "\(b.picks.count)-pick Combo Goal" : (b.picks.first?.label ?? "Challenge")
    }

    /// Minutes a win would add, after the 120-minute cap.
    static func toWin(_ b: Challenge) -> Int {
        let raw = b.pledgeMinutes + jsRoundInt(Double(jsRoundInt(Double(b.pledgeMinutes) * b.decimal) - b.pledgeMinutes) * b.multiplier)
        return max(0, min(raw, Rules.maxAllowedMinutes) - b.pledgeMinutes)
    }
}
