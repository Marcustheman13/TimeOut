import Foundation
import Observation
import UIKit
import UserNotifications

/// Everything TimeOut tells the user. In the app that's a banner at the top of the screen.
/// With the app in the background it's a real iPhone notification.
@Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    enum Access: Equatable { case unknown, notDetermined, denied, allowed }
    private(set) var access: Access = .unknown

    private var center: UNUserNotificationCenter { .current() }

    func install() {
        center.delegate = self
        Task { await refreshAccess() }
    }

    func refreshAccess() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: access = .notDetermined
        case .denied: access = .denied
        default: access = .allowed
        }
    }

    func requestIfNeeded() async {
        await refreshAccess()
        guard access == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshAccess()
    }

    /// Shows a banner while TimeOut is on screen, and a notification when it isn't.
    func announce(_ kind: ToastKind, _ title: String, _ body: String, id: String, tab: String) {
        if UIApplication.shared.applicationState == .active {
            UIState.shared.toast(kind, title, body)
        } else {
            post(title, body, id: id, tab: tab)
        }
    }

    private func post(_ title: String, _ body: String, id: String, tab: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["tab": tab]
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    /// A notification that lands while the app is open, like the Screen Time monitor's low-time warning, still shows.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Tapping a notification goes to the screen it's about.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let tab = response.notification.request.content.userInfo["tab"] as? String
        await MainActor.run {
            if let tab { UIState.shared.go(tab) } else { SettingsModel.open("screentime") }
        }
    }
}
