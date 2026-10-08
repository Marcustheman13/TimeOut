import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation

/// Values shared with the Device Activity Monitor extension through the App Group.
/// Keep these in sync with `ScreenTimeMonitor/DeviceActivityMonitorExtension.swift`.
nonisolated enum ScreenTimeShared {
    static let appGroup = "group.marcuswilliams.staketime"
    static let storeName = ManagedSettingsStore.Name("staketime")

    /// Apps being limited today.
    static let selectionKey = "st.selection"
    /// Smaller selection waiting for midnight (commitment lock: removals never apply the same day).
    static let pendingSelectionKey = "st.pendingSelection"
    static let pendingDayKey = "st.pendingDay"
    /// [dayKey: minutes] — today's limit and tomorrow's projected limit, written by the app.
    static let limitsKey = "st.limits"
    /// [dayKey: minutes] — phone time used on limited apps, written by the monitor at usage checkpoints.
    static let usageKey = "st.usage"
    /// "<dayKey>|<limit>|<selectionVersion>" of the currently registered monitor.
    static let registeredKey = "st.registered"
    /// Day on which the limit was reached (shield is up).
    static let limitReachedKey = "st.limitReachedDay"
    static let overrideUntilKey = "st.overrideUntil"
    static let selectionVersionKey = "st.selectionVersion"
    /// "W-L" record, shown on the custom lock screen.
    static let recordKey = "st.record"
    /// Set while limits are enforced, so revoking access can be detected.
    static let wasEnforcingKey = "st.wasEnforcing"

    /// Days limits were running, and days the limit was reached — used to score the clean streak.
    static let enforcedDaysKey = "st.enforcedDays"
    static let reachedDaysKey = "st.reachedDays"
    /// When limits were first turned on (grace period for lock tiers).
    static let enforcingSinceKey = "st.enforcingSince"

    static let usedEventPrefix = "staketime.used."

    /// Appends a day to a short list stored in the App Group.
    static func mark(_ day: String, in key: String) {
        var days = defaults.stringArray(forKey: key) ?? []
        guard !days.contains(day) else { return }
        days.append(day)
        defaults.set(Array(days.suffix(45)), forKey: key)
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    /// Usage checkpoints: every 5 minutes, then every minute in the last 5. More checkpoints mean a more
    /// accurate "time left", but iOS wakes the monitor for each one, so this keeps it to ~15 a day.
    static func checkpoints(for limit: Int) -> [Int] {
        guard limit > 1 else { return [] }
        var marks = Set(stride(from: 5, to: limit, by: 5))
        for minute in max(1, limit - 5)..<limit { marks.insert(minute) }
        return marks.sorted()
    }
}

extension DeviceActivityName {
    static let stakeTimeDaily = Self("staketime.daily")
    static let stakeTimeOverride = Self("staketime.override")
}

extension DeviceActivityEvent.Name {
    static let stakeTimeLimit = Self("staketime.limit")
}

/// Turns the wallet's daily limit into a real Screen Time limit on the apps the user picks.
///
/// The app registers a daily Device Activity schedule with usage checkpoints and one event at the limit.
/// The monitor extension records usage at each checkpoint, raises the shield at the limit, and re-registers
/// the next day's limit at midnight.
///
/// Commitment lock: adding apps takes effect immediately, removing apps waits until midnight, and revoking
/// Screen Time access is detected and forfeits the day's betting (see `AppModel.syncScreenTime`).
@Observable
final class ScreenTimeManager {
    enum Status: Equatable {
        case notDetermined, denied, approved
    }

    private(set) var status: Status = .notDetermined
    private(set) var isShieldActive = false
    private(set) var overrideUntil: Date?
    private(set) var lastError: String?
    /// Minutes used on limited apps today, from the last checkpoint.
    private(set) var usedToday = 0

    /// Apps limited today.
    private(set) var selection: FamilyActivitySelection
    /// The selection that takes over at midnight, when the user removed something.
    private(set) var pendingSelection: FamilyActivitySelection?
    /// What the picker edits. Applied through `applyDraft()` so the commitment rules hold.
    var draft = FamilyActivitySelection()

    private let center = DeviceActivityCenter()
    private let store = ManagedSettingsStore(named: ScreenTimeShared.storeName)
    private var defaults: UserDefaults { ScreenTimeShared.defaults }

    init() {
        let defaults = ScreenTimeShared.defaults
        selection = Self.decode(defaults.data(forKey: ScreenTimeShared.selectionKey)) ?? FamilyActivitySelection()
        pendingSelection = Self.decode(defaults.data(forKey: ScreenTimeShared.pendingSelectionKey))
        refreshStatus()
    }

    var hasSelection: Bool { !Self.isEmpty(selection) }

    var selectionSummary: String { Self.summary(selection) }

    /// Number of apps, categories and sites limited today. Used for lock status.
    var lockedItemCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    /// Lock points: apps and sites 1 each, whole categories 3.
    var lockPoints: Int {
        Rewards.lockPoints(apps: selection.applicationTokens.count, categories: selection.categoryTokens.count,
                           sites: selection.webDomainTokens.count)
    }

    /// Minutes used on limited apps over the last 7 days.
    var weeklyUsage: Int {
        let usage = defaults.dictionary(forKey: ScreenTimeShared.usageKey) as? [String: Int] ?? [:]
        let cutoff = DayClock.key(DayClock.key(), offsetBy: -6)
        return usage.filter { $0.key >= cutoff }.values.reduce(0, +)
    }

    /// Still inside the first week of limits, when usage history is too short to judge.
    var inGracePeriod: Bool {
        let since = defaults.double(forKey: ScreenTimeShared.enforcingSinceKey)
        guard since > 0 else { return true }
        return Date().timeIntervalSince1970 - since < Double(Rewards.graceDays) * 86_400
    }

    func wasEnforced(on day: String) -> Bool {
        (defaults.stringArray(forKey: ScreenTimeShared.enforcedDaysKey) ?? []).contains(day)
    }

    func reachedLimit(on day: String) -> Bool {
        (defaults.stringArray(forKey: ScreenTimeShared.reachedDaysKey) ?? []).contains(day)
    }

    /// e.g. "2 apps" — what disappears from the list at midnight.
    var pendingRemovalSummary: String? {
        guard let pending = pendingSelection else { return nil }
        var removed = FamilyActivitySelection()
        removed.applicationTokens = selection.applicationTokens.subtracting(pending.applicationTokens)
        removed.categoryTokens = selection.categoryTokens.subtracting(pending.categoryTokens)
        removed.webDomainTokens = selection.webDomainTokens.subtracting(pending.webDomainTokens)
        return Self.isEmpty(removed) ? nil : Self.summary(removed)
    }

    /// Limits are enforced only once the user has granted access and picked what to limit.
    var isEnforcing: Bool { status == .approved && hasSelection }

    var isOverrideActive: Bool { (overrideUntil ?? .distantPast) > .now }

    // MARK: Authorization

    func refreshStatus() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: status = .approved
        case .denied: status = .denied
        default: status = .notDetermined
        }
        let today = DayClock.key()
        isShieldActive = defaults.string(forKey: ScreenTimeShared.limitReachedKey) == today
        let until = defaults.double(forKey: ScreenTimeShared.overrideUntilKey)
        overrideUntil = until > 0 ? Date(timeIntervalSince1970: until) : nil
        let usage = defaults.dictionary(forKey: ScreenTimeShared.usageKey) as? [String: Int] ?? [:]
        usedToday = usage[today] ?? 0
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = "Screen Time access wasn't granted: \(error.localizedDescription)"
        }
        refreshStatus()
    }

    /// True once if limits were being enforced and Screen Time access has since been revoked.
    func consumeRevocation() -> Bool {
        guard defaults.bool(forKey: ScreenTimeShared.wasEnforcingKey), status != .approved else { return false }
        defaults.set(false, forKey: ScreenTimeShared.wasEnforcingKey)
        return true
    }

    // MARK: Limits

    /// Publishes today's and tomorrow's limits and (re)registers monitoring when anything changed.
    func sync(todayKey: String, todayLimit: Int, tomorrowKey: String, tomorrowLimit: Int, now: Date = .now) {
        defaults.set([todayKey: todayLimit, tomorrowKey: tomorrowLimit], forKey: ScreenTimeShared.limitsKey)
        promotePendingIfDue(today: todayKey)
        pruneUsage(today: todayKey)
        refreshStatus()

        guard isEnforcing else {
            if defaults.string(forKey: ScreenTimeShared.registeredKey) != nil {
                center.stopMonitoring([.stakeTimeDaily, .stakeTimeOverride])
                store.clearAllSettings()
                defaults.removeObject(forKey: ScreenTimeShared.registeredKey)
                defaults.removeObject(forKey: ScreenTimeShared.limitReachedKey)
            }
            // Access still granted but nothing selected (e.g. a midnight removal emptied the list) isn't tampering.
            if status == .approved { defaults.set(false, forKey: ScreenTimeShared.wasEnforcingKey) }
            return
        }
        defaults.set(true, forKey: ScreenTimeShared.wasEnforcingKey)
        ScreenTimeShared.mark(todayKey, in: ScreenTimeShared.enforcedDaysKey)
        if defaults.object(forKey: ScreenTimeShared.enforcingSinceKey) == nil {
            defaults.set(now.timeIntervalSince1970, forKey: ScreenTimeShared.enforcingSinceKey)
        }

        // An expired override: put the shield back if the limit was already hit.
        if let until = overrideUntil, until <= now {
            defaults.removeObject(forKey: ScreenTimeShared.overrideUntilKey)
            overrideUntil = nil
            if isShieldActive { applyShield() }
        }

        let version = defaults.integer(forKey: ScreenTimeShared.selectionVersionKey)
        let signature = "\(todayKey)|\(todayLimit)|\(version)"
        guard defaults.string(forKey: ScreenTimeShared.registeredKey) != signature else { return }

        // The limit changed (new day, a late result, or new app selection). Lift the shield and re-measure —
        // `includesPastActivity` counts usage from earlier today, so events re-fire if they're already over.
        if !isOverrideActive {
            store.clearAllSettings()
        }
        defaults.removeObject(forKey: ScreenTimeShared.limitReachedKey)
        isShieldActive = false
        defaults.set(signature, forKey: ScreenTimeShared.registeredKey)

        do {
            try startDailyMonitoring(limit: todayLimit)
            if todayLimit <= 0 {
                markLimitReached(today: todayKey)
            }
            lastError = nil
        } catch {
            lastError = "Couldn't start the screen time limit: \(error.localizedDescription)"
            defaults.removeObject(forKey: ScreenTimeShared.registeredKey)
        }
    }

    private func startDailyMonitoring(limit: Int) throws {
        center.stopMonitoring([.stakeTimeDaily])
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        if limit > 0 {
            events[.stakeTimeLimit] = event(minutes: limit)
            for minute in ScreenTimeShared.checkpoints(for: limit) {
                events[DeviceActivityEvent.Name(ScreenTimeShared.usedEventPrefix + String(minute))] = event(minutes: minute)
            }
        }
        try center.startMonitoring(.stakeTimeDaily, during: schedule, events: events)
    }

    private func event(minutes: Int) -> DeviceActivityEvent {
        DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(hour: minutes / 60, minute: minutes % 60),
            includesPastActivity: true
        )
    }

    private func markLimitReached(today: String) {
        defaults.set(today, forKey: ScreenTimeShared.limitReachedKey)
        ScreenTimeShared.mark(today, in: ScreenTimeShared.reachedDaysKey)
        isShieldActive = true
        if !isOverrideActive { applyShield() }
    }

    private func applyShield() {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    private func pruneUsage(today: String) {
        guard var usage = defaults.dictionary(forKey: ScreenTimeShared.usageKey) as? [String: Int] else { return }
        let cutoff = DayClock.key(today, offsetBy: -7)
        usage = usage.filter { $0.key >= cutoff }
        defaults.set(usage, forKey: ScreenTimeShared.usageKey)
    }

    // MARK: Emergency override

    /// Lifts the shield for `BetBook.overrideMinutes`. The monitor extension re-applies it when the window ends.
    func emergencyUnlock(now: Date = .now) throws {
        let end = now.addingTimeInterval(TimeInterval(BetBook.overrideMinutes * 60) + 30)
        let calendar = Calendar.current
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: now),
            intervalEnd: calendar.dateComponents(parts, from: end),
            repeats: false
        )
        center.stopMonitoring([.stakeTimeOverride])
        try center.startMonitoring(.stakeTimeOverride, during: schedule)
        store.clearAllSettings()
        defaults.set(end.timeIntervalSince1970, forKey: ScreenTimeShared.overrideUntilKey)
        overrideUntil = end
    }

    // MARK: Selection (commitment lock)

    /// Loads what the picker should show: tomorrow's list if a removal is pending, otherwise today's.
    func prepareDraft() {
        draft = pendingSelection ?? selection
    }

    /// Applies the picker result. Additions lock immediately; removals are held until midnight.
    func applyDraft(now: Date = .now) {
        let next = draft
        var effective = selection
        effective.applicationTokens.formUnion(next.applicationTokens)
        effective.categoryTokens.formUnion(next.categoryTokens)
        effective.webDomainTokens.formUnion(next.webDomainTokens)

        if !Self.sameItems(effective, selection) {
            selection = effective
            save(selection, key: ScreenTimeShared.selectionKey)
            defaults.set(defaults.integer(forKey: ScreenTimeShared.selectionVersionKey) + 1, forKey: ScreenTimeShared.selectionVersionKey)
        }

        if Self.sameItems(next, effective) || !isEnforcing {
            // Nothing removed — or limits aren't running yet, so there's nothing to get around.
            if !isEnforcing && !Self.sameItems(next, selection) {
                selection = next
                save(selection, key: ScreenTimeShared.selectionKey)
                defaults.set(defaults.integer(forKey: ScreenTimeShared.selectionVersionKey) + 1, forKey: ScreenTimeShared.selectionVersionKey)
            }
            cancelPendingRemoval()
        } else {
            pendingSelection = next
            save(next, key: ScreenTimeShared.pendingSelectionKey)
            defaults.set(DayClock.key(DayClock.key(for: now), offsetBy: 1), forKey: ScreenTimeShared.pendingDayKey)
        }
    }

    func cancelPendingRemoval() {
        pendingSelection = nil
        defaults.removeObject(forKey: ScreenTimeShared.pendingSelectionKey)
        defaults.removeObject(forKey: ScreenTimeShared.pendingDayKey)
    }

    /// At midnight the smaller list takes over. The monitor extension does the same if the app isn't running.
    private func promotePendingIfDue(today: String) {
        if let day = defaults.string(forKey: ScreenTimeShared.pendingDayKey), day <= today,
           let data = defaults.data(forKey: ScreenTimeShared.pendingSelectionKey) {
            defaults.set(data, forKey: ScreenTimeShared.selectionKey)
            defaults.set(defaults.integer(forKey: ScreenTimeShared.selectionVersionKey) + 1, forKey: ScreenTimeShared.selectionVersionKey)
            defaults.removeObject(forKey: ScreenTimeShared.pendingSelectionKey)
            defaults.removeObject(forKey: ScreenTimeShared.pendingDayKey)
        }
        // Pick up a promotion done by the extension, too.
        selection = Self.decode(defaults.data(forKey: ScreenTimeShared.selectionKey)) ?? FamilyActivitySelection()
        pendingSelection = Self.decode(defaults.data(forKey: ScreenTimeShared.pendingSelectionKey))
    }

    private func save(_ value: FamilyActivitySelection, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func decode(_ data: Data?) -> FamilyActivitySelection? {
        data.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
    }

    private static func isEmpty(_ s: FamilyActivitySelection) -> Bool {
        s.applicationTokens.isEmpty && s.categoryTokens.isEmpty && s.webDomainTokens.isEmpty
    }

    private static func sameItems(_ a: FamilyActivitySelection, _ b: FamilyActivitySelection) -> Bool {
        a.applicationTokens == b.applicationTokens && a.categoryTokens == b.categoryTokens && a.webDomainTokens == b.webDomainTokens
    }

    private static func summary(_ s: FamilyActivitySelection) -> String {
        let apps = s.applicationTokens.count
        let categories = s.categoryTokens.count
        let sites = s.webDomainTokens.count
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if categories > 0 { parts.append("\(categories) categor\(categories == 1 ? "y" : "ies")") }
        if sites > 0 { parts.append("\(sites) site\(sites == 1 ? "" : "s")") }
        return parts.isEmpty ? "None selected" : parts.joined(separator: ", ")
    }
}
