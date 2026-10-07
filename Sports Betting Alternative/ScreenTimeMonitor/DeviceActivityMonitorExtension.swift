//  Paste this over the template file in the "ScreenTimeMonitor" Device Activity Monitor extension target.
//  See Setup/SCREEN_TIME_SETUP.md. Keys and names must match ScreenTimeShared in the app.

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UserNotifications

private enum Shared {
    static let appGroup = "group.marcuswilliams.staketime"
    static let storeName = ManagedSettingsStore.Name("staketime")
    static let selectionKey = "st.selection"
    static let pendingSelectionKey = "st.pendingSelection"
    static let pendingDayKey = "st.pendingDay"
    static let usageKey = "st.usage"
    static let usedEventPrefix = "staketime.used."
    static let enforcedDaysKey = "st.enforcedDays"
    static let reachedDaysKey = "st.reachedDays"

    static func mark(_ day: String, in key: String) {
        var days = defaults.stringArray(forKey: key) ?? []
        guard !days.contains(day) else { return }
        days.append(day)
        defaults.set(Array(days.suffix(45)), forKey: key)
    }
    static let limitsKey = "st.limits"
    static let registeredKey = "st.registered"
    static let limitReachedKey = "st.limitReachedDay"
    static let overrideUntilKey = "st.overrideUntil"
    static let selectionVersionKey = "st.selectionVersion"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    /// Same as ScreenTimeShared.checkpoints in the app.
    static func checkpoints(for limit: Int) -> [Int] {
        guard limit > 1 else { return [] }
        var marks = Set(stride(from: 5, to: limit, by: 5))
        for minute in max(1, limit - 5)..<limit { marks.insert(minute) }
        return marks.sorted()
    }
}

private extension DeviceActivityName {
    static let stakeTimeDaily = Self("staketime.daily")
    static let stakeTimeOverride = Self("staketime.override")
}

private extension DeviceActivityEvent.Name {
    static let stakeTimeLimit = Self("staketime.limit")
}

/// Runs in the background, even when StakeTime isn't open:
/// - at midnight, lifts yesterday's lock and registers today's limit (60 + yesterday's net − penalties)
/// - at midnight, applies any app removals the user queued (commitment lock)
/// - records usage at checkpoints so the app can show time left, and warns at 5 minutes left
/// - when usage reaches the limit, locks the chosen apps
/// - when an emergency unlock window ends, locks them again
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: Shared.storeName)
    private var defaults: UserDefaults { Shared.defaults }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == .stakeTimeDaily else { return }

        let today = dayKey()
        promotePendingSelection(today: today)
        let limit = (defaults.dictionary(forKey: Shared.limitsKey) as? [String: Int])?[today] ?? 60
        let version = defaults.integer(forKey: Shared.selectionVersionKey)
        let signature = "\(today)|\(limit)|\(version)"

        // The app registers monitoring itself (which also triggers this callback) and stores the signature first.
        // Only act when a new day started without the app re-registering.
        guard defaults.string(forKey: Shared.registeredKey) != signature else { return }
        defaults.set(signature, forKey: Shared.registeredKey)
        defaults.removeObject(forKey: Shared.limitReachedKey)
        store.clearAllSettings()

        guard let selection = loadSelection() else { return }
        if selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty {
            // A midnight removal emptied the list: stop limiting until the user picks apps again.
            DeviceActivityCenter().stopMonitoring([.stakeTimeDaily])
            defaults.removeObject(forKey: Shared.registeredKey)
            return
        }
        Shared.mark(today, in: Shared.enforcedDaysKey)
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        if limit > 0 {
            events[.stakeTimeLimit] = event(selection, minutes: limit)
            for minute in Shared.checkpoints(for: limit) {
                events[DeviceActivityEvent.Name(Shared.usedEventPrefix + String(minute))] = event(selection, minutes: minute)
            }
        }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        let center = DeviceActivityCenter()
        center.stopMonitoring([.stakeTimeDaily])
        try? center.startMonitoring(.stakeTimeDaily, during: schedule, events: events)

        if limit <= 0 {
            defaults.set(today, forKey: Shared.limitReachedKey)
            Shared.mark(today, in: Shared.reachedDaysKey)
            shield(selection)
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let today = dayKey()
        let limit = (defaults.dictionary(forKey: Shared.limitsKey) as? [String: Int])?[today] ?? 60

        if event.rawValue.hasPrefix(Shared.usedEventPrefix) {
            guard let minutes = Int(event.rawValue.dropFirst(Shared.usedEventPrefix.count)) else { return }
            recordUsage(minutes, today: today)
            if minutes == limit - 5 && limit >= 10 && !overrideActive {
                notify("5 minutes left", "Your limited apps lock when today's \(limit) min run out.")
            }
            return
        }

        guard event == .stakeTimeLimit else { return }
        recordUsage(limit, today: today)
        defaults.set(today, forKey: Shared.limitReachedKey)
        Shared.mark(today, in: Shared.reachedDaysKey)
        guard !overrideActive, let selection = loadSelection() else { return }
        shield(selection)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == .stakeTimeOverride else { return }
        defaults.removeObject(forKey: Shared.overrideUntilKey)
        if defaults.string(forKey: Shared.limitReachedKey) == dayKey(), let selection = loadSelection() {
            shield(selection)
        }
    }

    // MARK: Helpers

    private func event(_ selection: FamilyActivitySelection, minutes: Int) -> DeviceActivityEvent {
        DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(hour: minutes / 60, minute: minutes % 60),
            includesPastActivity: true
        )
    }

    /// Usage only ever goes up during a day (checkpoints can re-fire when monitoring restarts).
    private func recordUsage(_ minutes: Int, today: String) {
        var usage = defaults.dictionary(forKey: Shared.usageKey) as? [String: Int] ?? [:]
        usage[today] = max(usage[today] ?? 0, minutes)
        defaults.set(usage, forKey: Shared.usageKey)
    }

    /// Commitment lock: a removal queued yesterday takes effect now.
    private func promotePendingSelection(today: String) {
        guard let day = defaults.string(forKey: Shared.pendingDayKey), day <= today,
              let data = defaults.data(forKey: Shared.pendingSelectionKey) else { return }
        defaults.set(data, forKey: Shared.selectionKey)
        defaults.set(defaults.integer(forKey: Shared.selectionVersionKey) + 1, forKey: Shared.selectionVersionKey)
        defaults.removeObject(forKey: Shared.pendingSelectionKey)
        defaults.removeObject(forKey: Shared.pendingDayKey)
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "staketime.warning", content: content, trigger: nil))
    }

    private var overrideActive: Bool {
        defaults.double(forKey: Shared.overrideUntilKey) > Date().timeIntervalSince1970
    }

    private func shield(_ selection: FamilyActivitySelection) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    private func loadSelection() -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: Shared.selectionKey) else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    private func dayKey(for date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
