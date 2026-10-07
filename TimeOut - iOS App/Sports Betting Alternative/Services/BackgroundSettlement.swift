import BackgroundTasks
import Foundation
import UserNotifications

/// Settles bets while the app is closed using iOS background app refresh.
///
/// iOS decides when to actually wake the app (often within an hour, sometimes longer, and less often in Low Power
/// Mode or if the app is rarely used), so this is best-effort. Opening the app always settles immediately.
nonisolated enum BackgroundSettlement {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in AppInfo.plist.
    static let taskID = "com.marcuswilliams.staketime.settle"

    /// Asks iOS for a wake-up while any bet is open; cancels the request otherwise.
    static func schedule(hasOpenBets: Bool) {
        let scheduler = BGTaskScheduler.shared
        guard hasOpenBets else {
            scheduler.cancel(taskRequestWithIdentifier: taskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? scheduler.submit(request)
    }
}

/// Local notifications for bets that settle while the app isn't on screen.
nonisolated enum Notifier {
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func betSettled(_ bet: Bet) {
        let content = UNMutableNotificationContent()
        let friend = bet.friendStake.map { " (\($0))" } ?? ""
        switch bet.status {
        case .won:
            content.title = "Winner! \(bet.title)"
            content.body = bet.isFriendBet ? "You won your friend bet\(friend)." : "\(bet.netMinutes.signedMinutes) added to tomorrow's screen time."
        case .lost:
            content.title = "Bet lost: \(bet.title)"
            content.body = bet.isFriendBet ? "You lost your friend bet\(friend)." : "\(bet.netMinutes.signedMinutes) from tomorrow's screen time."
        case .void:
            content.title = "Bet voided"
            content.body = "\(bet.title): game postponed or canceled. Stake refunded."
        case .push:
            content.title = "Push: \(bet.title)"
            content.body = "It's a tie on the line. Stake refunded."
        case .open:
            return
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: bet.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
