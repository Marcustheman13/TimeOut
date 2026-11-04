import BackgroundTasks
import Foundation
import Observation
import SwiftUI
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
        ui.tab = "home"
        live.refresh(force: true)
        live.refreshUpcoming()
        Task { await store.refreshTeams() }
        Invites.offer()
        ScreenTime.shared.sync()
        requestNotifications()
        #if DEBUG
        ScreenshotSeed.runIfRequested()
        #endif
    }

    /// Challenge results and the "5 minutes left" warning arrive as notifications while the app is in the background.
    private func requestNotifications() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
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
            ui.toast(.info, "New day, new 60 minutes", "Today's phone limit is \(store.wallet.todayLimit) min after yesterday's challenges.")
        }
        notifyResolved(store.resolve(now))
        for username in store.socialTick(now) where store.data?.settings.notify.friends == true {
            ui.toast(.win, "@\(username) accepted your friend request")
        }
        ScreenTime.shared.sync()
        store.checkPhoneTime()
        if Date().timeIntervalSince(lastRemoteSync) > 30 { syncRemoteState() }
    }

    func notifyResolved(_ list: [Challenge]) {
        guard store.data?.settings.notify.resolved == true else { return }
        for b in list {
            let title = ChallengeText.title(b)
            if b.status == "won" { ui.toast(.win, "Won: \(title)", "+\(b.reward - b.pledgeMinutes) min added to tomorrow's phone time.") }
            else if b.status == "lost" { ui.toast(.loss, "Lost: \(title)", "−\(b.pledgeMinutes) min from tomorrow's phone time.") }
            else { ui.toast(.info, "Voided: \(title)", "\(b.insurancePaid == true ? "Combo protection paid out." : "The game was postponed.") Your \(b.pledgeMinutes) min pledged came back.") }
        }
    }

    func netChanged() {
        if Net.shared.online { ui.toast(.win, "Back online", "Point values are updating again.") }
    }

    /// Challenges placed on another device (or the website) show up here within 30 seconds.
    func syncRemoteState(force: Bool = false) {
        guard inShell, API.shared.configured, API.shared.hasToken, let server = store.account?.server, !remoteSyncing else { return }
        if !force && Date().timeIntervalSince(lastRemoteSync) < 30 { return }
        lastRemoteSync = Date()
        remoteSyncing = true
        Task {
            defer { remoteSyncing = false }
            guard let state = try? await API.shared.loadState(), inShell else { return }
            store.adoptServerUser(server, remote: state)
        }
    }

    func didEnterBackground() {
        Task { try? await API.shared.flushState() }
        scheduleBackgroundRefresh()
    }

    // MARK: Background resolution

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Runs when iOS wakes the app: refresh scores, resolve, and notify about finished challenges.
    func backgroundRefresh() async {
        scheduleBackgroundRefresh()
        guard inShell else { return }
        live.refresh(force: true)
        for _ in 0..<20 where live.loading { try? await Task.sleep(for: .milliseconds(500)) }
        let resolved = store.resolve(TO.now())
        guard store.data?.settings.notify.resolved == true else { return }
        for b in resolved {
            let content = UNMutableNotificationContent()
            content.title = b.status == "won" ? "Won: \(ChallengeText.title(b))" : b.status == "lost" ? "Lost: \(ChallengeText.title(b))" : "Voided: \(ChallengeText.title(b))"
            content.body = b.status == "won" ? "+\(b.reward - b.pledgeMinutes) min added to tomorrow's phone time."
                : b.status == "lost" ? "−\(b.pledgeMinutes) min from tomorrow's phone time." : "Your \(b.pledgeMinutes) min pledged came back."
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: b.id, content: content, trigger: nil))
        }
        try? await API.shared.flushState()
    }

    // MARK: Links

    /// timeout://invite?invite=user&team=… or the web app's ?invite= links.
    func handle(url: URL) {
        Invites.capture(url)
        if inShell { Invites.offer() }
    }
}

/// Friend and team invite links, like the web demo's `TO.invites`.
enum Invites {
    struct Pending: Codable { var invite: String; var team: String; var teamName: String; var start: String; var end: String; var key: String }
    private static let key = "timeout.invite"

    /// `?invite=username` is the friend link (`?join=` works too). A team link adds team, teamName, start, end and key.
    static func friendLink(_ username: String? = nil) -> String {
        var c = URLComponents(string: API.webURL)!
        c.queryItems = [URLQueryItem(name: "invite", value: username ?? Store.shared.account?.username ?? "")]
        return c.url?.absoluteString ?? API.webURL
    }

    static func teamLink(_ team: Squad) -> String {
        var c = URLComponents(string: API.webURL)!
        var items = [URLQueryItem(name: "invite", value: team.owner.isEmpty ? Store.shared.account?.username : team.owner),
                     URLQueryItem(name: "team", value: team.id), URLQueryItem(name: "teamName", value: team.name),
                     URLQueryItem(name: "start", value: team.start), URLQueryItem(name: "end", value: team.end)]
        if let k = team.shareKey { items.append(URLQueryItem(name: "key", value: k)) }
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
        let p = Pending(invite: invite, team: team, teamName: v("teamName"), start: v("start"), end: v("end"), key: v("key"))
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
        if !p.invite.isEmpty && !Store.sameUser(p.invite, me) { Store.shared.addFriend(p.invite) }
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
        if team != nil { SocialModel.shared.tab = "teams" } else if !p.invite.isEmpty { SocialModel.shared.tab = "board" }
        ui.go("social")
        ui.toast(.win, team.map { "You joined \($0.name)" } ?? "You and @\(p.invite) are now friends")
    }
}

/// Challenge titles shared by toasts, cards and the share image.
enum ChallengeText {
    static func title(_ b: Challenge) -> String {
        if b.kind == "todo" { return "To-do combo · \(b.picks.count) task\(b.picks.count == 1 ? "" : "s")" }
        return b.picks.count > 1 ? "\(b.picks.count)-pick combo" : (b.picks.first?.label ?? "Challenge")
    }

    static func toWin(_ b: Challenge) -> Int {
        jsRoundInt(Double(jsRoundInt(Double(b.pledgeMinutes) * b.decimal) - b.pledgeMinutes) * b.multiplier)
    }
}
