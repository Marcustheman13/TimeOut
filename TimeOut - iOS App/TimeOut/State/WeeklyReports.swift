import Foundation
import Observation

/// One weekly review, as the server wrote it (supabase/functions/weekly-report). The app only draws it.
struct WeeklyReport: Identifiable, Hashable {
    struct Tile: Hashable { var label: String; var value: String }
    struct Day: Hashable {
        var weekday: String
        /// Minutes on the blocked apps, or nil when the phone didn't record that day.
        var used: Int?
        var limit: Int
        /// "under", "over" or "none".
        var status: String
    }

    /// The Monday of the week it covers, yyyy-MM-dd.
    var week: String
    var range: String
    /// "crushed", "steady", "slipped" or "risky".
    var weekType: String
    var label: String
    var headline: String
    var summary: String
    var insight: String
    var suggestion: String
    var tiles: [Tile]
    /// The day-by-day table, or nil until the phone has recorded screen time.
    var days: [Day]?
    var read: Bool

    var id: String { week }
}

/// The reports for the signed-in person, newest week first. Reports are written once a week on the server.
@Observable
final class WeeklyReports {
    static let shared = WeeklyReports()

    private(set) var list: [WeeklyReport] = []
    /// False until the first answer from the server, so the screen can say "loading" instead of "no report yet".
    private(set) var loaded = false
    @ObservationIgnored private var lastRefresh = Date.distantPast

    var unread: Int { list.filter { !$0.read }.count }

    /// Fetches the latest reports. Quiet when there are none, or the server can't be reached.
    /// Skips the request if one ran in the last few minutes, unless `force` is set.
    func refresh(force: Bool = false) async {
        guard Store.shared.usesServerSocial else { return }
        if !force && Date().timeIntervalSince(lastRefresh) < 300 { return }
        guard let fresh = await API.shared.weeklyReports() else { return }
        lastRefresh = Date()
        // A week opened a moment ago may not be marked read on the server yet, so keep what this device already knows.
        let seen = Set(list.filter(\.read).map(\.week))
        list = fresh.map { var r = $0; if seen.contains(r.week) { r.read = true }; return r }
        loaded = true
        announceIfNew()
    }

    /// Tells the person once when a new report arrives: a banner if the app is open, a notification if it isn't.
    /// Not if they turned the weekly report off in Settings.
    private func announceIfNew() {
        guard let newest = list.first, !newest.read, Store.shared.data?.settings.notify.weekly != false else { return }
        let key = "timeout.weekly.announced.\(Store.shared.account?.id ?? "")"
        guard UserDefaults.standard.string(forKey: key) != newest.week else { return }
        UserDefaults.standard.set(newest.week, forKey: key)
        Notifier.shared.announce(.info, "Your weekly report is ready", newest.headline, id: "weekly-\(newest.week)", tab: "weekly")
    }

    /// Opening a report counts as reading it.
    func markRead(_ week: String) {
        guard let i = list.firstIndex(where: { $0.week == week }), !list[i].read else { return }
        list[i].read = true
        Task { await API.shared.markWeeklyReportRead(week) }
    }

    /// For logging out, so the next person on this phone doesn't see the last one's reports.
    func reset() {
        list = []
        loaded = false
        lastRefresh = .distantPast
    }
}
