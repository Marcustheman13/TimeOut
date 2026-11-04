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
        if access == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refreshAccess()
        }
        if access == .allowed { UIApplication.shared.registerForRemoteNotifications() }
    }

    // MARK: Push

    /// This phone's address with Apple's push service, once iOS has handed it over.
    private(set) var deviceToken: String?
    /// Where a notification tapped from a closed app wants to go, for when the app has finished opening.
    private var launchTab: String?

    /// Which Apple server can reach this build. Builds from Xcode use the sandbox. TestFlight and the App Store don't.
    private static var pushEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        Task { await API.shared.registerDevice(token, environment: Self.pushEnvironment) }
    }

    func takeLaunchTab() -> String? {
        defer { launchTab = nil }
        return launchTab
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
    /// A push doesn't, because the app shows its own banner for the same thing once it has the news.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard notification.request.trigger is UNPushNotificationTrigger else { return [.banner, .sound, .list] }
        await AppModel.shared.syncSocial()
        return []
    }

    /// Tapping a notification goes to the screen it's about.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let tab = response.notification.request.content.userInfo["tab"] as? String
        await MainActor.run {
            guard let tab else { SettingsModel.open("screentime"); return }
            if AppModel.shared.ready { UIState.shared.go(tab) } else { launchTab = tab }
        }
    }
}

/// iOS only hands over the push token through an app delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Notifier.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("TimeOut: couldn't register for push notifications: \(error)")
    }
}
