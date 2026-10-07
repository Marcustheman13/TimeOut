//  StakeTime's custom lock screen, shown instead of Apple's default Screen Time shield.
//  Keys and names must match ScreenTimeShared in the app.

import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

private enum Shared {
    static let appGroup = "group.marcuswilliams.staketime"
    static let limitsKey = "st.limits"
    static let recordKey = "st.record"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
}

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shield(for: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        shield(for: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shield(for: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        shield(for: webDomain.domain)
    }

    private func shield(for name: String?) -> ShieldConfiguration {
        let limits = Shared.defaults.dictionary(forKey: Shared.limitsKey) as? [String: Int] ?? [:]
        let tomorrow = limits[dayKey(offset: 1)] ?? 60
        let record = Shared.defaults.string(forKey: Shared.recordKey)

        // Short, scannable lines: what happened, when it ends, where you stand, what you can do.
        let delta = tomorrow - 60
        let change = delta > 0 ? "  (+\(delta))" : delta < 0 ? "  (−\(-delta))" : ""
        var lines = [
            "\(name ?? "This app") unlocks at midnight.",
            "",
            "Tomorrow's limit: \(tomorrow) min\(change)",
        ]
        if let record { lines.append("Your record: \(record)") }
        lines += ["", "Win picks in StakeTime to earn time back.", "Emergency unlock is in the app."]

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 0.92),
            // Replace ShieldLogo in StakeTimeShield/Assets.xcassets with the real logo (square, 240×240 px).
            icon: UIImage(named: "ShieldLogo")
                ?? UIImage(systemName: "hourglass.bottomhalf.filled")?.withTintColor(Self.green, renderingMode: .alwaysOriginal),
            title: .init(text: "Time's up for today", color: .white),
            subtitle: .init(text: lines.joined(separator: "\n"), color: UIColor(white: 0.72, alpha: 1)),
            primaryButtonLabel: .init(text: "Close", color: .black),
            primaryButtonBackgroundColor: Self.green
        )
    }

    private static let green = UIColor(red: 0.13, green: 0.84, blue: 0.43, alpha: 1)

    private func dayKey(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
