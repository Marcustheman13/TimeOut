import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation

/// Values shared with the TimeOutMonitor and TimeOutShield extensions through the App Group.
/// Keep these in sync with `TimeOutMonitor/DeviceActivityMonitorExtension.swift`.
nonisolated enum ScreenTimeShared {
    static let appGroup = "group.marcuswilliams.staketime"
    static let storeName = ManagedSettingsStore.Name("staketime")

    /// Apps being blocked today.
    static let selectionKey = "st.selection"
    /// Smaller selection waiting for midnight (removals never apply the same day).
    static let pendingSelectionKey = "st.pendingSelection"
    static let pendingDayKey = "st.pendingDay"
    /// [dayKey: minutes]: today's limit and tomorrow's projected limit, written by the app.
    static let limitsKey = "st.limits"
    /// [dayKey: minutes]: phone time used on blocked apps, written by the monitor at usage checkpoints.
    static let usageKey = "st.usage"
    /// "<dayKey>|<limit>|<selectionVersion>" of the registered monitor.
    static let registeredKey = "st.registered"
    static let limitReachedKey = "st.limitReachedDay"
    static let overrideUntilKey = "st.overrideUntil"
    static let selectionVersionKey = "st.selectionVersion"
    /// "W-L" record, shown on the custom lock screen.
    static let recordKey = "st.record"
    static let enforcedDaysKey = "st.enforcedDays"
    static let reachedDaysKey = "st.reachedDays"
    static let usedEventPrefix = "staketime.used."

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func mark(_ day: String, in key: String) {
        var days = defaults.stringArray(forKey: key) ?? []
        guard !days.contains(day) else { return }
        days.append(day)
        defaults.set(Array(days.suffix(45)), forKey: key)
    }

    /// Usage checkpoints: every 5 minutes, then every minute in the last 5.
    static func checkpoints(for limit: Int) -> [Int] {
        guard limit > 1 else { return [] }
        var marks = Set(stride(from: 5, to: limit, by: 5))
        for minute in max(1, limit - 5)..<limit { marks.insert(minute) }
        return marks.sorted()
    }
}

extension DeviceActivityName {
    static let timeOutDaily = Self("staketime.daily")
    static let timeOutOverride = Self("staketime.override")
}

extension DeviceActivityEvent.Name {
    static let timeOutLimit = Self("staketime.limit")
}

/// Turns the wallet's daily phone-time limit into a real Screen Time limit on the apps the user picks.
///
/// The web demo only simulates locked apps. Here "Enforce app limits" registers a Device Activity schedule:
/// the TimeOutMonitor extension records usage, blocks the chosen apps at today's limit, and re-registers at midnight.
/// Adding apps blocks them right away; removing apps waits until midnight so a limit can't be dodged mid-day.
@Observable
final class ScreenTime {
    static let shared = ScreenTime()

    enum Status: Equatable { case notDetermined, denied, approved }

    private(set) var status: Status = .notDetermined
    private(set) var isShieldActive = false
    private(set) var overrideUntil: Date?
    private(set) var lastError: String?
    /// Minutes used on blocked apps today, from the last checkpoint.
    private(set) var usedToday = 0
    private(set) var selection: FamilyActivitySelection
    private(set) var pendingSelection: FamilyActivitySelection?
    /// What the picker edits. Applied through `applyDraft()` so the midnight rule holds.
    var draft = FamilyActivitySelection()

    @ObservationIgnored private let center = DeviceActivityCenter()
    @ObservationIgnored private let store = ManagedSettingsStore(named: ScreenTimeShared.storeName)
    private var defaults: UserDefaults { ScreenTimeShared.defaults }

    private init() {
        let d = ScreenTimeShared.defaults
        selection = Self.decode(d.data(forKey: ScreenTimeShared.selectionKey)) ?? FamilyActivitySelection()
        pendingSelection = Self.decode(d.data(forKey: ScreenTimeShared.pendingSelectionKey))
        refreshStatus()
    }

    var hasSelection: Bool { !Self.isEmpty(selection) }
    var selectionSummary: String { Self.summary(selection) }

    var pendingRemovalSummary: String? {
        guard let pending = pendingSelection else { return nil }
        var removed = FamilyActivitySelection()
        removed.applicationTokens = selection.applicationTokens.subtracting(pending.applicationTokens)
        removed.categoryTokens = selection.categoryTokens.subtracting(pending.categoryTokens)
        removed.webDomainTokens = selection.webDomainTokens.subtracting(pending.webDomainTokens)
        return Self.isEmpty(removed) ? nil : Self.summary(removed)
    }

    /// Real blocking runs when limits are on in TimeOut, access is granted and apps are picked.
    var isEnforcing: Bool { status == .approved && hasSelection && (Store.shared.data?.settings.enforce ?? false) }

    var isOverrideActive: Bool { (overrideUntil ?? .distantPast) > .now }

    // MARK: Authorization

    private func refreshStatus() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: status = .approved
        case .denied: status = .denied
        default: status = .notDetermined
        }
        let today = TO.dayKey()
        isShieldActive = defaults.string(forKey: ScreenTimeShared.limitReachedKey) == today
        let until = defaults.double(forKey: ScreenTimeShared.overrideUntilKey)
        overrideUntil = until > 0 ? Date(timeIntervalSince1970: until) : nil
        let usage = defaults.dictionary(forKey: ScreenTimeShared.usageKey) as? [String: Int] ?? [:]
        usedToday = usage[today] ?? 0
    }

    /// Re-reads access and usage, and passes real usage to the wallet.
    func refresh() {
        refreshStatus()
        if isEnforcing && usedToday > 0 { Store.shared.setUsage(usedToday) }
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = "Screen Time access wasn't granted: \(error.localizedDescription)"
        }
        refreshStatus()
        sync()
    }

    // MARK: Limits

    /// Publishes today's and tomorrow's limits and (re)registers monitoring when anything changed.
    func sync(now: Date = .now) {
        guard let data = Store.shared.data else { return }
        let wl = Store.shared.walletView(data)
        let todayKey = wl.day, tomorrowKey = TO.addDays(todayKey, 1)
        defaults.set([todayKey: wl.todayLimit, tomorrowKey: wl.tomorrowLimit], forKey: ScreenTimeShared.limitsKey)
        let st = Store.shared.myStats
        defaults.set("\(st.w)-\(st.l)", forKey: ScreenTimeShared.recordKey)
        promotePendingIfDue(today: todayKey)
        pruneUsage(today: todayKey)
        refreshStatus()
        if isEnforcing && usedToday > 0 { Store.shared.setUsage(usedToday) }

        guard isEnforcing else {
            if defaults.string(forKey: ScreenTimeShared.registeredKey) != nil {
                center.stopMonitoring([.timeOutDaily, .timeOutOverride])
                store.clearAllSettings()
                defaults.removeObject(forKey: ScreenTimeShared.registeredKey)
                defaults.removeObject(forKey: ScreenTimeShared.limitReachedKey)
            }
            return
        }
        ScreenTimeShared.mark(todayKey, in: ScreenTimeShared.enforcedDaysKey)

        // An expired emergency unlock: put the block back if the limit was already hit.
        if let until = overrideUntil, until <= now {
            defaults.removeObject(forKey: ScreenTimeShared.overrideUntilKey)
            overrideUntil = nil
            if isShieldActive { applyShield() }
        }

        let version = defaults.integer(forKey: ScreenTimeShared.selectionVersionKey)
        let signature = "\(todayKey)|\(wl.todayLimit)|\(version)"
        guard defaults.string(forKey: ScreenTimeShared.registeredKey) != signature else { return }

        // The limit changed (new day, a settled bet, an unlock, or new apps). Lift the block and re-measure:
        // `includesPastActivity` counts earlier usage, so events re-fire if the user is already over.
        if !isOverrideActive { store.clearAllSettings() }
        defaults.removeObject(forKey: ScreenTimeShared.limitReachedKey)
        isShieldActive = false
        defaults.set(signature, forKey: ScreenTimeShared.registeredKey)
        do {
            try startDailyMonitoring(limit: wl.todayLimit)
            if wl.todayLimit <= 0 { markLimitReached(today: todayKey) }
            lastError = nil
        } catch {
            lastError = "Couldn't start the screen time limit: \(error.localizedDescription)"
            defaults.removeObject(forKey: ScreenTimeShared.registeredKey)
        }
    }

    private func startDailyMonitoring(limit: Int) throws {
        center.stopMonitoring([.timeOutDaily])
        let schedule = DeviceActivitySchedule(intervalStart: DateComponents(hour: 0, minute: 0),
                                              intervalEnd: DateComponents(hour: 23, minute: 59, second: 59), repeats: true)
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        if limit > 0 {
            events[.timeOutLimit] = event(minutes: limit)
            for minute in ScreenTimeShared.checkpoints(for: limit) {
                events[DeviceActivityEvent.Name(ScreenTimeShared.usedEventPrefix + String(minute))] = event(minutes: minute)
            }
        }
        try center.startMonitoring(.timeOutDaily, during: schedule, events: events)
    }

    private func event(minutes: Int) -> DeviceActivityEvent {
        DeviceActivityEvent(applications: selection.applicationTokens, categories: selection.categoryTokens, webDomains: selection.webDomainTokens,
                            threshold: DateComponents(hour: minutes / 60, minute: minutes % 60), includesPastActivity: true)
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
        let cutoff = TO.addDays(today, -7)
        usage = usage.filter { $0.key >= cutoff }
        defaults.set(usage, forKey: ScreenTimeShared.usageKey)
    }

    // MARK: Emergency unlock

    /// Lifts the block for the emergency unlock window. The monitor puts it back when the window ends.
    func emergencyUnlock(now: Date = .now) {
        guard isEnforcing else { return }
        let end = now.addingTimeInterval(TimeInterval(Rules.overrideMinutes * 60) + 30)
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(intervalStart: Calendar.current.dateComponents(parts, from: now),
                                              intervalEnd: Calendar.current.dateComponents(parts, from: end), repeats: false)
        center.stopMonitoring([.timeOutOverride])
        do {
            try center.startMonitoring(.timeOutOverride, during: schedule)
            store.clearAllSettings()
            defaults.set(end.timeIntervalSince1970, forKey: ScreenTimeShared.overrideUntilKey)
            overrideUntil = end
        } catch {
            lastError = "Couldn't unlock your apps: \(error.localizedDescription)"
        }
    }

    // MARK: Selection

    /// Loads what the picker should show: tomorrow's list if a removal is pending, otherwise today's.
    func prepareDraft() { draft = pendingSelection ?? selection }

    /// Applies the picker result. Additions block immediately; removals wait until midnight while limits run.
    func applyDraft(now: Date = .now) {
        let next = draft
        var effective = selection
        effective.applicationTokens.formUnion(next.applicationTokens)
        effective.categoryTokens.formUnion(next.categoryTokens)
        effective.webDomainTokens.formUnion(next.webDomainTokens)
        if !Self.sameItems(effective, selection) {
            selection = effective
            save(selection, key: ScreenTimeShared.selectionKey)
            bumpVersion()
        }
        if Self.sameItems(next, effective) || !isEnforcing {
            if !isEnforcing && !Self.sameItems(next, selection) {
                selection = next
                save(selection, key: ScreenTimeShared.selectionKey)
                bumpVersion()
            }
            cancelPendingRemoval()
        } else {
            pendingSelection = next
            save(next, key: ScreenTimeShared.pendingSelectionKey)
            defaults.set(TO.addDays(TO.dayKey(TO.ms(now)), 1), forKey: ScreenTimeShared.pendingDayKey)
        }
        sync()
    }

    func cancelPendingRemoval() {
        pendingSelection = nil
        defaults.removeObject(forKey: ScreenTimeShared.pendingSelectionKey)
        defaults.removeObject(forKey: ScreenTimeShared.pendingDayKey)
    }

    private func bumpVersion() {
        defaults.set(defaults.integer(forKey: ScreenTimeShared.selectionVersionKey) + 1, forKey: ScreenTimeShared.selectionVersionKey)
    }

    private func promotePendingIfDue(today: String) {
        if let day = defaults.string(forKey: ScreenTimeShared.pendingDayKey), day <= today,
           let data = defaults.data(forKey: ScreenTimeShared.pendingSelectionKey) {
            defaults.set(data, forKey: ScreenTimeShared.selectionKey)
            bumpVersion()
            defaults.removeObject(forKey: ScreenTimeShared.pendingSelectionKey)
            defaults.removeObject(forKey: ScreenTimeShared.pendingDayKey)
        }
        selection = Self.decode(defaults.data(forKey: ScreenTimeShared.selectionKey)) ?? FamilyActivitySelection()
        pendingSelection = Self.decode(defaults.data(forKey: ScreenTimeShared.pendingSelectionKey))
    }

    private func save(_ value: FamilyActivitySelection, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
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
        let apps = s.applicationTokens.count, categories = s.categoryTokens.count, sites = s.webDomainTokens.count
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if categories > 0 { parts.append("\(categories) categor\(categories == 1 ? "y" : "ies")") }
        if sites > 0 { parts.append("\(sites) site\(sites == 1 ? "" : "s")") }
        return parts.isEmpty ? "None selected" : parts.joined(separator: ", ")
    }
}
